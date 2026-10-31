import '../ast/message_ast.dart';
import '../ast/rich_ast.dart';
import '../config.dart';
import '../model/localization_model.dart';
import '../overrides/override_fingerprint.dart';
import '../overrides/override_schema.dart';
import '../plural/cldr_plural_rules.dart';
import 'intl_formatters.dart';

/// Emits the locale independent Dart API and one implementation per locale.
///
/// Design notes that the output depends on:
///
/// * every generated class is `const` constructible and every namespace
///   accessor returns a `const` instance, so the whole translation tree is
///   canonicalized at compile time and reading `t.auth.login.title` allocates
///   nothing;
/// * plural rules are inlined as Dart conditions for the locale being emitted,
///   so no rule table reaches the app;
/// * output order is fully determined by the base locale document order, which
///   makes regeneration byte for byte stable;
/// * with `runtime_overrides` on, every message body asks the override store
///   for its text before returning its literal, and nothing else changes — the
///   same compiled condition picks the same branch, the same formatter renders
///   the same argument, and what an override supplies is one branch's words.
///   With it off not a byte moves, which is what makes the option safe to add
///   to a library whose argument is that there is no run time path.
final class DartEmitter {
  /// Creates an emitter for [model].
  DartEmitter(this.model, this.config);

  /// The model to emit.
  final LocalizationModel model;

  /// Generation options; read for `format_plural_numbers`.
  final L10nPlusConfig config;

  /// The format `#` uses when `format_plural_numbers` is on.
  ///
  /// ICU renders `#` with the plural's own number format, which for
  /// `{n, plural, ...}` is the locale's plain decimal pattern.
  static const ArgumentFormat _numberSignFormat = ArgumentFormat(
    ArgumentFormatKind.number,
  );

  /// Name of the operand variable in generated plural bodies.
  ///
  /// Starts with `$` so it can never collide with a translation argument,
  /// whose names are normalized to lower camel case.
  static const String _operands = r'$operands';

  /// Name of the local holding what the override store returned.
  ///
  /// Starts with `$` for the same reason [_operands] does.
  static const String _override = r'$override';

  /// Name of the per class constant every override lookup is keyed by.
  ///
  /// A `static const` on the implementation class rather than a field: the
  /// classes have to stay `const` constructible, and a class level constant is
  /// also the only place the locale is known for a nested namespace, which
  /// carries no `l10nLocale` of its own.
  static const String _localeField = r'_$locale';

  final Map<String, List<OverrideMessage>> _overrideMessages = {};

  /// Every override lookup the last [emit] wrote, per locale file tag.
  ///
  /// Recorded while emitting rather than derived a second time, so
  /// `check-overrides` validates against the lookups the application performs
  /// and cannot drift from them. Empty unless `runtime_overrides` is on.
  OverrideCatalog get overrides => config.runtimeOverrides
      ? OverrideCatalog([
          for (final locale in model.locales)
            OverrideSchema(
              localeTag: locale.tag,
              language: locale.locale.language,
              messages: {
                for (final message
                    in _overrideMessages[locale.tag] ??
                        const <OverrideMessage>[])
                  message.key: message,
              },
            ),
        ])
      : const OverrideCatalog([]);

  final Map<String, FormatterBinding> _formatters = {};

  /// Formatters the last [emit] needed, sorted by name.
  ///
  /// Empty when no message formats a number or a date, which is what keeps
  /// `package:intl` out of projects that do not need it.
  List<FormatterBinding> get formatters => (_formatters.keys.toList(
    growable: false,
  )..sort()).map((name) => _formatters[name]!).toList(growable: false);

  /// Renders the library as one file per locale plus a shared file.
  ///
  /// The shared file holds the imports, the locale enum, the select enums and
  /// the interfaces, and declares one `part` per locale. Each part holds that
  /// locale's implementation classes and the formatters that format *for* it,
  /// so editing one language rewrites one file.
  ///
  /// "For it", not "used by it": with `fill_missing_from_base` an
  /// untranslated message renders as the base locale does, so a locale's part
  /// can call a formatter belonging to the base. Every part is a part of one
  /// library, so declaring it in both would not compile.
  ///
  /// `part` rather than separate libraries: the formatters are private top
  /// level finals, parts keep them private and reachable, there is no import
  /// cycle between the shared file and the locales, and the import an
  /// application writes does not change.
  ///
  /// Returns the shared file under [sharedFileName], and each locale's part
  /// under the name [partFileName] gives it.
  Map<String, String> emitSplit({
    required String sharedFileName,
    required String Function(LocaleModel) partFileName,
  }) {
    _overrideMessages.clear();
    final parts = <String, String>{};
    final union = <String, FormatterBinding>{};
    final bodies = <LocaleModel, String>{};
    final owned = <LocaleModel, Map<String, FormatterBinding>>{
      for (final locale in model.locales) locale: {},
    };

    // Locales first: the shared file's imports depend on what they needed.
    for (final locale in model.locales) {
      _formatters.clear();
      final body = StringBuffer();
      _writeImplementation(body, model.root, locale);
      bodies[locale] = body.toString();
      union.addAll(_formatters);
    }

    // Each formatter is declared once, in the part of the locale it formats
    // for, which every other part can reach because they are one library.
    for (final binding in union.values) {
      final owner = model.locales.firstWhere(
        (locale) => locale.dartName == binding.localeDartName,
      );
      owned[owner]![binding.fieldName] = binding;
    }

    for (final locale in model.locales) {
      _formatters
        ..clear()
        ..addAll(owned[locale]!);
      final file = StringBuffer()
        ..writeln('// GENERATED BY l10n_plus. DO NOT MODIFY BY HAND.')
        ..writeln()
        ..writeln("part of '$sharedFileName';")
        ..writeln();
      _writeFormatters(file);
      file.write(bodies[locale]!);
      parts[partFileName(locale)] = file.toString();
    }

    _formatters
      ..clear()
      ..addAll(union);

    final shared = StringBuffer();
    _writeHeader(shared);
    for (final locale in model.locales) {
      shared.writeln("part '${partFileName(locale)}';");
    }
    shared.writeln();
    _writeFormattingInitializer(shared);
    // Declared once in the shared file: the parts are one library with it, so
    // every locale's formatters can reach it.
    _writeDateFormatHelper(shared);
    _writeLocaleEnum(shared);
    for (final selectEnum in model.enums) {
      _writeSelectEnum(shared, selectEnum);
    }
    _writeInterfaces(shared, model.root);

    return {sharedFileName: shared.toString(), ...parts};
  }

  /// Renders the whole library as one file.
  String emit() {
    _formatters.clear();
    _overrideMessages.clear();

    // The implementations are rendered first because they decide which
    // formatters — and therefore which imports — the header needs, and with
    // `runtime_overrides` on, what the locale enum states as each locale's
    // fingerprint: the slots it is taken over are recorded while the lookups
    // are being written. `emitSplit` emits them first for the same reason.
    final implementations = StringBuffer();
    for (final locale in model.locales) {
      _writeImplementation(implementations, model.root, locale);
    }

    final body = StringBuffer();
    _writeLocaleEnum(body);
    for (final selectEnum in model.enums) {
      _writeSelectEnum(body, selectEnum);
    }
    _writeInterfaces(body, model.root);
    body.write(implementations);

    final buffer = StringBuffer();
    _writeHeader(buffer);
    _writeFormattingInitializer(buffer);
    _writeDateFormatHelper(buffer);
    _writeFormatters(buffer);
    buffer.write(body);
    return buffer.toString();
  }

  void _writeHeader(StringBuffer buffer) {
    buffer
      ..writeln('// GENERATED BY l10n_plus. DO NOT MODIFY BY HAND.')
      ..writeln('// Regenerate with: dart run l10n_plus_generator generate')
      ..writeln()
      ..writeln('// ignore_for_file: type=lint, unnecessary_string_escapes')
      ..writeln();
    if (_usesDateFormats) {
      buffer.writeln("import 'package:intl/date_symbol_data_local.dart';");
    }
    if (_formatters.isNotEmpty) {
      buffer.writeln("import 'package:intl/intl.dart';");
    }
    buffer
      ..writeln("import 'package:l10n_plus/l10n_plus.dart';")
      ..writeln()
      // `of` takes an `L10nLocale` and `appLocale.l10nLocale` returns one, so
      // the type is part of this library's surface. Without the export a file
      // that imports only the generated one cannot name it, which is a
      // second, undocumented import for something the reader never chose.
      //
      // A rich message returns `List<L10nSpan>`, so the span types are part
      // of the surface too — but only in a project that has one, so the
      // export of a project with no rich message does not change.
      ..writeln(
        "export 'package:l10n_plus/l10n_plus.dart' show $_exportedNames;",
      )
      ..writeln();
  }

  /// The runtime names the generated library re-exports.
  ///
  /// `L10nOverrides` joins them when overrides are on, because installing a
  /// bundle is then part of what this library is for and an application should
  /// not need a second import to do it.
  String get _exportedNames => [
    'L10nLocale',
    if (config.runtimeOverrides) ...['L10nOverrideMismatch', 'L10nOverrides'],
    if (_hasRichMessages) ...['L10nSpan', 'L10nTagSpan', 'L10nTextSpan'],
  ].join(', ');

  /// Whether the project has a rich message at all.
  ///
  /// Read for the export list, which stays as it was in every project that
  /// has none.
  bool get _hasRichMessages => _anyRichMessage(model.root);

  static bool _anyRichMessage(NamespaceModel namespace) =>
      namespace.messages.any((message) => message.isRich) ||
      namespace.children.any(_anyRichMessage);

  /// Whether any generated formatter is a `DateFormat`.
  ///
  /// Number symbols ship inside `package:intl`, but date symbols must be
  /// loaded before the first `DateFormat` for a non default locale is built.
  bool get _usesDateFormats =>
      _formatters.values.any((binding) => binding.dartType == 'DateFormat');

  /// Emits the date symbol loader, when date formatting is used at all.
  void _writeFormattingInitializer(StringBuffer buffer) {
    if (!_usesDateFormats) return;
    final name = 'initialize${model.className}Formatting';
    buffer
      ..writeln('/// Loads the ICU date symbols the generated date formats')
      ..writeln('/// need, for every supported locale.')
      ..writeln('///')
      ..writeln('/// Call this once during start up and await it before')
      ..writeln('/// reading any date formatted message. Number formats need')
      ..writeln('/// no initialization.')
      ..writeln('Future<void> $name() async {')
      ..writeln('  for (final locale in ${model.localeEnumName}.values) {')
      ..writeln(
        '    await initializeDateFormatting(locale.l10nLocale.toFileTag());',
      )
      ..writeln('  }')
      ..writeln('}')
      ..writeln();
  }

  /// Emits the helper every generated `DateFormat` is constructed through.
  ///
  /// `DateFormat.yMMMd('ru')` throws while it is *built*, not while it
  /// formats, so the failure lands on the first read of a lazily initialized
  /// top level final — carrying intl's own message, which cannot know that
  /// this file generated an initializer that fixes it.
  ///
  /// Nothing can be loaded lazily here: `initializeDateFormatting` is
  /// asynchronous and a field initializer is not, so the best available
  /// answer is an error that names the call to make.
  void _writeDateFormatHelper(StringBuffer buffer) {
    if (!_usesDateFormats) return;
    final initializer = 'initialize${model.className}Formatting';
    buffer.write('''
/// Builds a [DateFormat], explaining the one way it can fail.
///
/// The ICU symbols a non default locale needs are loaded by
/// [$initializer], which must be awaited once during start up.
DateFormat ${IntlFormatters.dateFormatHelper}(
  String locale,
  DateFormat Function() build,
) {
  try {
    return build();
  } on Exception catch (error) {
    // intl's LocaleDataException is not exported, so the type cannot be
    // named here; the original error is carried rather than swallowed.
    throw StateError(
      'Date symbols for "\$locale" are not loaded.\\n'
      'Call `await $initializer()` once during start up, before reading a '
      'date formatted message.\\n'
      'Underlying error: \$error',
    );
  }
}

''');
  }

  /// Emits one lazily initialized final per locale and style.
  ///
  /// Top level finals are initialized on first use and never again, so a
  /// message method only calls `format` on an object that already exists.
  void _writeFormatters(StringBuffer buffer) {
    if (_formatters.isEmpty) return;
    for (final binding in formatters) {
      buffer.writeln(
        'final ${binding.dartType} ${binding.fieldName} = '
        '${binding.initializer};',
      );
    }
    buffer.writeln();
  }

  /// Registers the formatter [format] needs for [locale] and returns the
  /// expression that formats [parameter].
  String _formatCall({
    required ArgumentFormat format,
    required LocaleModel locale,
    required String parameter,
  }) {
    final binding = IntlFormatters.bindingFor(
      format: format,
      localeTag: locale.tag,
      localeDartName: locale.dartName,
    );
    // Unsupported formats are rejected by the parser and the model builder, so
    // reaching this with a null binding would be a generator bug.
    if (binding == null) return parameter;
    _formatters[binding.fieldName] = binding;
    return '${binding.fieldName}.format($parameter)';
  }

  /// The formatter [plural] renders its own count through, if any.
  ///
  /// CLDR reads the operands off the digits that are *displayed*, so a
  /// formatter decides them only where the count actually renders through it.
  /// Two cases fall outside that and keep reading the value: a plural whose
  /// branches are pure words — "Delete the file" against "Delete the files" —
  /// displays no number at all, and a branch that interpolates the count raw
  /// displays `toString()`, which is what [PluralOperands] already reads.
  ArgumentFormat? _renderedCountFormat(
    _MessageContext context,
    PluralNode plural,
  ) => _nestedCountFormat(context, plural.cases, plural.argument);

  ArgumentFormat? _bodyCountFormat(
    _MessageContext context,
    MessageBody body,
    String argument,
  ) {
    for (final node in body.nodes) {
      final format = switch (node) {
        NumberSignNode() when node.argument == argument => _pluralNumberFormat(
          context,
          argument,
        ),
        ArgumentNode() when node.name == argument => context.formatOf(node),
        PluralNode() => _nestedCountFormat(context, node.cases, argument),
        SelectNode() => _nestedCountFormat(context, node.cases, argument),
        _ => null,
      };
      if (format != null) return format;
    }
    return null;
  }

  ArgumentFormat? _nestedCountFormat(
    _MessageContext context,
    Map<Object?, MessageBody> cases,
    String argument,
  ) {
    for (final body in cases.values) {
      final format = _bodyCountFormat(context, body, argument);
      if (format != null) return format;
    }
    return null;
  }

  /// The statement that binds the plural operands.
  ///
  /// CLDR reads the operands off the digits the reader sees, so whenever the
  /// count is rendered through a formatter the operands must come from that
  /// same formatter — otherwise `1` under a currency prints `USD1.00` and
  /// selects `one`, which is the defect `gen_l10n` has. `NumberFormat` knows
  /// its own bounds at run time (a currency's fraction digits depend on the
  /// currency), so they are read from the field rather than baked in here.
  String _operandsStatement(
    _MessageContext context,
    PluralNode plural,
    String selector,
  ) {
    final format = _renderedCountFormat(context, plural);
    final field = format == null
        ? null
        : _formatterField(format: format, locale: context.locale);
    if (field == null) {
      return 'final $_operands = PluralOperands($selector);';
    }
    return 'final $_operands = PluralOperands.formatted($selector, '
        'minimumFractionDigits: $field.minimumFractionDigits, '
        'maximumFractionDigits: $field.maximumFractionDigits,);';
  }

  /// The format a `#` renders through, or `null` when it renders raw.
  ///
  /// A format declared on the count wins: the author asked for money, and
  /// `format_plural_numbers` is the fallback for counts nobody declared.
  ArgumentFormat? _pluralNumberFormat(_MessageContext context, String name) =>
      context.argument(name)?.format ??
      (config.formatPluralNumbers ? _numberSignFormat : null);

  /// Registers the formatter [format] needs for [locale] and returns the name
  /// of the field holding it, for reading something other than `format`.
  String? _formatterField({
    required ArgumentFormat format,
    required LocaleModel locale,
  }) {
    final binding = IntlFormatters.bindingFor(
      format: format,
      localeTag: locale.tag,
      localeDartName: locale.dartName,
    );
    if (binding == null) return null;
    _formatters[binding.fieldName] = binding;
    return binding.fieldName;
  }

  /// This build's overridable surface, per locale file tag.
  ///
  /// Empty unless `runtime_overrides` is on, and read only after the
  /// implementations have been emitted — the lookups are what it is taken
  /// over.
  Map<String, String> get _overrideFingerprints => {
    for (final schema in overrides.locales)
      schema.localeTag: OverrideFingerprint.of(schema),
  };

  void _writeLocaleEnum(StringBuffer buffer) {
    final name = model.localeEnumName;
    final overridable = config.runtimeOverrides;
    final fingerprints = _overrideFingerprints;
    buffer
      ..writeln('/// Every locale this app has translations for.')
      ..writeln('enum $name implements AppLocaleBase {');
    for (final locale in model.locales) {
      final fingerprint = overridable ? ", '${fingerprints[locale.tag]}'" : '';
      buffer
        ..writeln('  /// `${locale.locale.toLanguageTag()}`')
        ..writeln(
          '  ${locale.dartName}(${_localeLiteral(locale)}$fingerprint),',
        );
    }
    buffer
      ..writeln(';')
      ..writeln()
      ..writeln(
        overridable
            ? '  const $name(this.l10nLocale, this.overrideFingerprint);'
            : '  const $name(this.l10nLocale);',
      )
      ..writeln()
      ..writeln('  @override')
      ..writeln('  final L10nLocale l10nLocale;')
      ..writeln();
    if (overridable) {
      buffer
        ..writeln(
          '  /// The overridable surface this build compiled for this locale.',
        )
        ..writeln('  ///')
        ..writeln(
          '  /// The keys, the branches, the placeholders each branch '
          'substitutes and',
        )
        ..writeln(
          '  /// the numbering of the nested choices, as 16 hex digits. '
          'A bundle states',
        )
        ..writeln(
          '  /// the one `check-overrides --stamp` checked it against, and',
        )
        ..writeln('  /// [installOverrides] refuses any other.')
        ..writeln('  final String overrideFingerprint;')
        ..writeln()
        ..writeln(
          '  /// Installs [messages] as the runtime overrides of this locale.',
        )
        ..writeln('  ///')
        ..writeln(
          '  /// [messages] is a decoded bundle: dotted translation keys to a '
          'text, or to',
        )
        ..writeln(
          '  /// a map of branch texts, beside the `@@fingerprint` '
          '`check-overrides`',
        )
        ..writeln(
          '  /// wrote. Throws [L10nOverrideMismatch] and installs nothing '
          'when that',
        )
        ..writeln(
          '  /// fingerprint is not [overrideFingerprint] — the application '
          'then keeps',
        )
        ..writeln(
          '  /// rendering what it compiled, which is the right text for the '
          'build that is',
        )
        ..writeln('  /// running.')
        ..writeln(
          '  void installOverrides(Map<String, Object> messages) => '
          'L10nOverrides.install(l10nLocale, messages, '
          'fingerprint: overrideFingerprint);',
        )
        ..writeln();
    }
    buffer
      ..writeln('  /// The translations of this locale.')
      ..writeln('  ${model.className} get translations => switch (this) {');
    for (final locale in model.locales) {
      buffer.writeln(
        '    $name.${locale.dartName} => '
        'const ${model.className}${locale.classSuffix}(),',
      );
    }
    buffer
      ..writeln('  };')
      ..writeln()
      ..writeln('  /// Parses a locale tag such as `en` or `pt-BR`.')
      ..writeln('  ///')
      ..writeln(
        '  /// Returns `null` when no supported locale matches exactly.',
      )
      ..writeln('  static $name? tryParse(String tag) {')
      ..writeln('    final locale = L10nLocale.tryParse(tag);')
      ..writeln('    if (locale == null) return null;')
      ..writeln('    for (final value in values) {')
      ..writeln('      if (value.l10nLocale == locale) return value;')
      ..writeln('    }')
      ..writeln('    return null;')
      ..writeln('  }')
      ..writeln('}')
      ..writeln();
  }

  String _localeLiteral(LocaleModel locale) {
    final buffer = StringBuffer("L10nLocale('${locale.locale.language}'");
    if (locale.locale.script != null) {
      buffer.write(", script: '${locale.locale.script}'");
    }
    if (locale.locale.country != null) {
      buffer.write(", country: '${locale.locale.country}'");
    }
    buffer.write(')');
    return buffer.toString();
  }

  void _writeSelectEnum(StringBuffer buffer, SelectEnumModel selectEnum) {
    buffer
      ..writeln(
        '/// Branches of the `${selectEnum.argumentName}` select in '
        '`${selectEnum.messagePath}`.',
      )
      ..writeln('enum ${selectEnum.name} {');
    for (final value in selectEnum.values) {
      buffer
        ..writeln('  /// ICU branch `${value.icuLabel}`.')
        ..writeln('  ${value.dartName},');
    }
    buffer
      ..writeln('}')
      ..writeln();
  }

  void _writeInterfaces(StringBuffer buffer, NamespaceModel namespace) {
    if (namespace.isRoot) {
      _writeRootInterface(buffer, namespace);
    } else {
      buffer
        ..writeln('/// Translations under `${namespace.path}`.')
        ..writeln('abstract interface class ${namespace.interfaceName} {');
      _writeInterfaceMembers(buffer, namespace);
      buffer
        ..writeln('}')
        ..writeln();
    }
    for (final child in namespace.children) {
      _writeInterfaces(buffer, child);
    }
  }

  void _writeRootInterface(StringBuffer buffer, NamespaceModel namespace) {
    final name = model.className;
    final localeEnum = model.localeEnumName;
    buffer
      ..writeln('/// Locale independent translation API.')
      ..writeln('///')
      ..writeln('/// Obtain an instance with [$name.of], [$name.forLocale] or')
      ..writeln('/// [$localeEnum.translations].')
      ..writeln('abstract interface class $name implements BaseTranslations {')
      ..writeln('  /// Every supported locale.')
      ..writeln(
        '  static const List<$localeEnum> supportedLocales = '
        '$localeEnum.values;',
      )
      ..writeln()
      ..writeln('  /// The locale used when no supported locale matches.')
      ..writeln(
        '  static const $localeEnum fallbackLocale = '
        '$localeEnum.${model.fallbackLocale.dartName};',
      )
      ..writeln()
      ..writeln('  /// Translations of [locale], without any `BuildContext`.')
      ..writeln(
        '  static $name forLocale($localeEnum locale) => locale.translations;',
      )
      ..writeln()
      ..writeln('  /// Best translations for [locale], applying the fallback')
      ..writeln('  /// chain `locale -> language -> fallbackLocale`.')
      ..writeln(
        '  static $name of(L10nLocale? locale) => resolve(locale).translations;',
      )
      ..writeln()
      ..writeln('  /// The supported locale that best matches [locale].')
      ..writeln('  static $localeEnum resolve(L10nLocale? locale) =>')
      ..writeln('      L10nLocaleResolver.resolve(')
      ..writeln('        requested: locale,')
      ..writeln('        supported: supportedLocales,')
      ..writeln('        fallback: fallbackLocale,')
      ..writeln('      );')
      ..writeln()
      ..writeln('  /// The locale these translations belong to.')
      ..writeln('  $localeEnum get appLocale;')
      ..writeln();
    _writeInterfaceMembers(buffer, namespace);
    buffer
      ..writeln('}')
      ..writeln();
  }

  void _writeInterfaceMembers(StringBuffer buffer, NamespaceModel namespace) {
    for (final child in namespace.children) {
      buffer
        ..writeln('  /// Translations under `${child.path}`.')
        ..writeln('  ${child.interfaceName} get ${child.dartName};')
        ..writeln();
    }
    for (final message in namespace.messages) {
      _writeDoc(buffer, message);
      buffer
        ..writeln('  ${_signature(message)};')
        ..writeln();
    }
  }

  /// Writes the doc comment of a message.
  ///
  /// The description declared by the source format comes first, then the base
  /// locale text as a rendering example, then one line per argument. Formats
  /// that carry no metadata, such as plain JSON, produce just the text.
  void _writeDoc(StringBuffer buffer, MessageModel message) {
    final lines = <String>[];

    final description = message.description?.trim();
    if (description != null && description.isNotEmpty) {
      lines.addAll(_escapeDoc(description).split('\n'));
    }

    final baseBody = message.bodies[model.baseLocale.tag];
    final text = baseBody == null ? '' : _docComment(baseBody);
    if (text.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('`${model.baseLocale.locale.toLanguageTag()}`: $text');
    }

    final documented = message.arguments
        .where(
          (argument) =>
              argument.description != null || argument.example != null,
        )
        .toList(growable: false);
    if (documented.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      for (final argument in documented) {
        final parts = <String>[
          if (argument.description != null)
            _escapeDoc(argument.description!.trim()).replaceAll('\n', ' '),
          if (argument.example != null)
            'Example: `${_escapeDoc(argument.example!)}`.',
        ];
        lines.add('- [${argument.dartName}]: ${parts.join(' ')}');
      }
    }

    for (final line in lines) {
      buffer.writeln(line.isEmpty ? '  ///' : '  /// $line');
    }
  }

  void _writeImplementation(
    StringBuffer buffer,
    NamespaceModel namespace,
    LocaleModel locale,
  ) {
    final className = '${namespace.interfaceName}${locale.classSuffix}';
    final helpers = <String>[];

    buffer
      ..writeln(
        namespace.isRoot
            ? '/// `${locale.locale.toLanguageTag()}` translations.'
            : '/// `${locale.locale.toLanguageTag()}` translations under '
                  '`${namespace.path}`.',
      )
      ..writeln('class $className implements ${namespace.interfaceName} {')
      ..writeln(
        '  /// Creates the ${locale.locale.toLanguageTag()} '
        '${namespace.isRoot ? 'translations' : 'namespace'}.',
      )
      ..writeln('  const $className();')
      ..writeln();

    // Only where something reads it: a namespace of nothing but children
    // performs no lookup, and an unused constant in generated code is noise
    // the reader has to rule out.
    if (config.runtimeOverrides &&
        namespace.messages.any((message) => !message.isRich)) {
      buffer
        ..writeln('  /// The locale every override lookup here is keyed by.')
        ..writeln(
          '  static const L10nLocale $_localeField = '
          '${_localeLiteral(locale)};',
        )
        ..writeln();
    }

    if (namespace.isRoot) {
      buffer
        ..writeln('  @override')
        ..writeln(
          '  ${model.localeEnumName} get appLocale => '
          '${model.localeEnumName}.${locale.dartName};',
        )
        ..writeln()
        ..writeln('  @override')
        ..writeln(
          '  L10nLocale get l10nLocale => const ${_localeLiteral(locale)};',
        )
        ..writeln();
    }

    for (final child in namespace.children) {
      buffer
        ..writeln('  @override')
        ..writeln(
          '  ${child.interfaceName} get ${child.dartName} => '
          'const ${child.interfaceName}${locale.classSuffix}();',
        )
        ..writeln();
    }

    for (final message in namespace.messages) {
      // An untranslated message renders exactly as the base locale renders
      // it: its text, its plural rules, its formatting. Half translating it —
      // English words under Russian plural rules — would be stranger than
      // leaving it alone, and the warning already says it is untranslated.
      final translated = message.bodies[locale.tag];
      final body = translated ?? message.bodies[model.baseLocale.tag];
      if (body == null) continue; // Reported by the validator.
      final source = translated == null ? model.baseLocale : locale;
      final context = _MessageContext(message, source);
      buffer.writeln('  @override');
      if (translated == null) {
        buffer.writeln(
          '  /// Untranslated: renders as '
          '`${model.baseLocale.locale.toLanguageTag()}`.',
        );
      }
      // A rich message falls back the same way its plain body does: the
      // locale's own markup, or the base locale's when it has none.
      final richNodes = message.isRich
          ? message.richBodies[source.tag] ??
                message.richBodies[model.baseLocale.tag]
          : null;
      _writeMember(
        buffer,
        message,
        body,
        context,
        name: message.dartName,
        richNodes: richNodes,
      );
      buffer.writeln();
      helpers.addAll(context.helpers);
      if (config.runtimeOverrides) {
        (_overrideMessages[locale.tag] ??= []).add(
          OverrideMessage(
            key: message.path,
            keySpan: message.keySpan,
            isRich: message.isRich,
            slots: List.of(context.slots),
            pluralCategories: Map.of(context.pluralCategories),
            choices: Map.of(context.choiceSelectors),
          ),
        );
      }
    }

    for (final helper in helpers) {
      buffer
        ..write(helper)
        ..writeln();
    }

    buffer
      ..writeln('}')
      ..writeln();

    for (final child in namespace.children) {
      _writeImplementation(buffer, child, locale);
    }
  }

  void _writeMember(
    StringBuffer buffer,
    MessageModel message,
    MessageBody body,
    _MessageContext context, {
    required String name,
    List<RichNode>? richNodes,
  }) {
    final signature = _signature(message, name: name);
    if (richNodes != null) {
      // A rich message is always one expression: it cannot be a plural or a
      // select, so there is nothing to branch on and no helper to generate.
      buffer.writeln(
        '  $signature => '
        '${_richList(richNodes, context, constant: message.isGetter)};',
      );
      return;
    }
    if (body.isSingleChoice) {
      buffer.writeln('  $signature {');
      for (final line in _choiceStatements(body.nodes.single, context)) {
        buffer.writeln('    $line');
      }
      buffer.writeln('  }');
      return;
    }
    if (!config.runtimeOverrides) {
      buffer.writeln('  $signature => ${_expression(body, context)};');
      return;
    }
    // A message with one form has one slot, named by the key alone. The
    // expression form cannot hold a lookup, so the member becomes a block —
    // which changes nothing about the class being `const`.
    buffer.writeln('  $signature {');
    for (final line in _overridableReturn(body, context, branch: null)) {
      buffer.writeln('    $line');
    }
    buffer.writeln('  }');
  }

  /// The statements that return [body], consulting the override store first.
  ///
  /// Without `runtime_overrides` this is the single `return` it always was.
  /// With it, the lookup comes first and the literal stays as the answer when
  /// nothing is installed — so the compiled text is still what the application
  /// renders, and an override is an exception rather than a layer.
  ///
  /// The expression is built before the values are collected, because building
  /// it is what numbers the nested choices the values refer to.
  List<String> _overridableReturn(
    MessageBody body,
    _MessageContext context, {
    required String? branch,
  }) {
    final expression = _expression(body, context);
    if (!config.runtimeOverrides) return ['return $expression;'];

    final values = _fillValues(body, context);
    context.slots.add(
      OverrideSlot(branch: branch, tokens: values.keys.toSet()),
    );

    final key = _escapeContent(context.message.path);
    final arguments = branch == null
        ? "$_localeField, '$key'"
        : "$_localeField, '$key', '${_escapeContent(branch)}'";
    // An override with nothing to substitute is returned as it stands, so a
    // message of plain words costs one map lookup and no map literal — and
    // the guard fits on one line, which is why the braces are conditional
    // rather than a style choice: a `fill` call wraps, and an unbraced `if`
    // spread over two lines is not something to write into every message.
    if (values.isEmpty) {
      return [
        'final $_override = L10nOverrides.text($arguments);',
        'if ($_override != null) return $_override;',
        'return $expression;',
      ];
    }
    final pairs = values.entries
        .map((entry) => "'${entry.key}': ${entry.value}")
        .join(', ');
    return [
      'final $_override = L10nOverrides.text($arguments);',
      'if ($_override != null) {',
      '  return L10nOverrides.fill($_override, {$pairs});',
      '}',
      'return $expression;',
    ];
  }

  /// The already rendered value of every token [body]'s slot substitutes.
  ///
  /// Every argument of the message, not only the ones this branch's literal
  /// interpolates: the build time check validates placeholders against the
  /// message, so a reword that adds `{count}` to a branch that did not show it
  /// is accepted — and a token the checker accepts must be one the runtime
  /// substitutes, or the check would be passing something that renders as
  /// `{count}` on a screen.
  ///
  /// Each value is formatted exactly as the literal formats it: the format
  /// written in this branch if there is one, otherwise the one the message or
  /// the locale's metadata declared. `#` is the plural count in scope, after
  /// any `offset:`. A nested choice contributes its own rendering under `#n`,
  /// which is what lets the sentence *around* a plural be reworded.
  Map<String, String> _fillValues(MessageBody body, _MessageContext context) {
    final values = <String, String>{};
    for (final argument in context.message.arguments) {
      // A select argument's value is a generated enum; substituting it would
      // print `ProfileGreetingGender.male`. Left out, so the checker refuses
      // `{gender}` instead of the runtime rendering it.
      if (argument.selectEnum != null) continue;
      values[argument.name] = _argumentValue(context, argument, body);
    }

    final count = context.currentCount;
    if (count != null) {
      final name = context.numberSignName(count);
      final format = _pluralNumberFormat(context, count);
      values['#'] = format == null
          ? '$name.toString()'
          : _formatCall(
              format: format,
              locale: context.locale,
              parameter: name,
            );
    }

    for (final node in body.nodes) {
      if (node is! PluralNode && node is! SelectNode) continue;
      final nested = context.nestedChoice(node);
      if (nested != null) values['#${nested.index}'] = nested.call;
    }
    return values;
  }

  /// The expression a token stands for, rendered as the literal renders it.
  String _argumentValue(
    _MessageContext context,
    ArgumentModel argument,
    MessageBody body,
  ) {
    ArgumentFormat? format;
    for (final node in body.nodes) {
      if (node is ArgumentNode && node.name == argument.name) {
        format = context.formatOf(node);
        break;
      }
    }
    format ??= context.declaredFormat(argument.name);
    if (format != null) {
      return _formatCall(
        format: format,
        locale: context.locale,
        parameter: argument.dartName,
      );
    }
    if (argument.type == 'String') return argument.dartName;
    // `toString()` rather than an interpolation, which is what the literal
    // compiles to anyway and needs no brace rules for an escaped identifier.
    return '${argument.dartName}.toString()';
  }

  String _signature(MessageModel message, {String? name}) {
    final memberName = name ?? message.dartName;
    // A rich message returns the span list itself: data, no Flutter types,
    // and `const` when nothing has to be interpolated into it. The typed
    // `TextSpan` wrapper lives in the Flutter glue, which is the only
    // generated file allowed to know what a `TextSpan` is.
    final type = message.isRich ? 'List<L10nSpan>' : 'String';
    if (message.isGetter) return '$type get $memberName';
    final parameters = message.arguments
        .map((argument) => 'required ${argument.type} ${argument.dartName}')
        .join(', ');
    return '$type $memberName({$parameters})';
  }

  /// Renders rich [nodes] as a `List<L10nSpan>` literal.
  ///
  /// `const` is applied to the outer literal only, and only for a message
  /// with no arguments: every text run is then a plain string literal, so the
  /// whole tree is canonicalized at compile time and reading the message
  /// allocates nothing — the same guarantee the namespace accessors give.
  String _richList(
    List<RichNode> nodes,
    _MessageContext context, {
    required bool constant,
  }) {
    final elements = nodes.map((node) => _richSpan(node, context)).join(', ');
    return '${constant ? 'const ' : ''}[$elements]';
  }

  String _richSpan(RichNode node, _MessageContext context) => switch (node) {
    // A text run is an ordinary message body, so it renders through the same
    // expression builder as any string: a placeholder becomes an
    // interpolation and a declared format becomes a formatter call.
    RichTextNode(:final body) => 'L10nTextSpan(${_expression(body, context)})',
    RichTagNode(:final tag, :final children) =>
      "L10nTagSpan('${_escapeContent(tag)}', "
          '${_richList(children, context, constant: false)})',
  };

  /// Renders [body] as a single Dart expression.
  String _expression(MessageBody body, _MessageContext context) {
    if (body.nodes.isEmpty) return "''";

    if (body.nodes.length == 1) {
      final node = body.nodes.single;
      if (node is LiteralNode) return _stringLiteral(node.value);
      if (node is ArgumentNode) {
        final argument = context.argument(node.name);
        final format = context.formatOf(node);
        if (format != null && argument != null) {
          return _formatCall(
            format: format,
            locale: context.locale,
            parameter: argument.dartName,
          );
        }
        if (argument != null && argument.type == 'String') {
          return argument.dartName;
        }
      }
      if (node is PluralNode || node is SelectNode) {
        return context.helperCall(node, this);
      }
    }

    final buffer = StringBuffer();
    for (var index = 0; index < body.nodes.length; index++) {
      final node = body.nodes[index];
      switch (node) {
        case LiteralNode():
          buffer.write(_escapeContent(node.value));
        case ArgumentNode():
          final argument = context.argument(node.name);
          final format = context.formatOf(node);
          if (format != null && argument != null) {
            final call = _formatCall(
              format: format,
              locale: context.locale,
              parameter: argument.dartName,
            );
            buffer.write('\${$call}');
          } else {
            buffer.write(
              _interpolate(context.parameterName(node.name), body.nodes, index),
            );
          }
        case NumberSignNode():
          final value = context.numberSignName(node.argument);
          final format = _pluralNumberFormat(context, node.argument);
          if (format != null) {
            final call = _formatCall(
              format: format,
              locale: context.locale,
              parameter: value,
            );
            buffer.write('\${$call}');
          } else {
            buffer.write(_interpolate(value, body.nodes, index));
          }
        case PluralNode():
        case SelectNode():
          buffer.write('\${${context.helperCall(node, this)}}');
      }
    }
    return "'$buffer'";
  }

  /// Emits `$name` when the following literal cannot extend the identifier,
  /// and `${name}` otherwise.
  String _interpolate(String name, List<MessageNode> nodes, int index) {
    // An escaped identifier such as `class$` must always use braces: `$class$`
    // would interpolate `class` and leave a stray dollar sign.
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
      return '\${$name}';
    }
    final next = index + 1 < nodes.length ? nodes[index + 1] : null;
    if (next is LiteralNode && next.value.isNotEmpty) {
      final first = next.value.codeUnitAt(0);
      final continues =
          (first >= 0x61 && first <= 0x7a) ||
          (first >= 0x41 && first <= 0x5a) ||
          (first >= 0x30 && first <= 0x39) ||
          first == 0x5f;
      if (continues) return '\${$name}';
    }
    return '\$$name';
  }

  /// Renders a plural or select node as the statements of a method body.
  List<String> _choiceStatements(MessageNode node, _MessageContext context) {
    switch (node) {
      case final SelectNode select:
        final argument = context.argument(select.argument);
        final selectEnum = argument?.selectEnum;
        if (argument == null || selectEnum == null) return ["return '';"];
        context.choiceSelectors[context.choicePrefix] =
            '${select.argument}:select';
        if (!config.runtimeOverrides) {
          final lines = <String>['return switch (${argument.dartName}) {'];
          for (final value in selectEnum.values) {
            final branch = select.cases[value.icuLabel];
            final body = branch == null ? "''" : _expression(branch, context);
            lines.add('  ${selectEnum.name}.${value.dartName} => $body,');
          }
          lines.add('};');
          return lines;
        }
        // A switch expression cannot hold a lookup, so overrides turn this
        // into a switch statement over the same enum — still exhaustive, so
        // the method still provably returns. Each case is a block of its own
        // because the cases of one switch share a scope, and every one of them
        // declares the same local.
        final lines = <String>['switch (${argument.dartName}) {'];
        for (final value in selectEnum.values) {
          final branch = select.cases[value.icuLabel];
          lines.add('  case ${selectEnum.name}.${value.dartName}:');
          if (branch == null) {
            lines.add("    return '';");
            continue;
          }
          lines.add('    {');
          for (final line in _overridableReturn(
            branch,
            context,
            branch: context.branchPath(value.icuLabel),
          )) {
            lines.add('      $line');
          }
          lines.add('    }');
        }
        lines.add('}');
        return lines;

      case final PluralNode plural:
        final argument = context.argument(plural.argument);
        if (argument == null) return ["return '';"];

        // With `offset:`, `#` and the category rules see the adjusted value,
        // while explicit `=N` branches still match the original one.
        final selector = plural.offset == 0
            ? argument.dartName
            : '\$${argument.dartName}Offset';
        // Recorded before the branches are walked: a branch may nest a choice
        // of its own, which pushes a prefix of its own.
        context.choiceSelectors[context.choicePrefix] =
            '${plural.argument}:${plural.type.name}';
        context.pushNumberSign(plural.argument, selector);

        final lines = <String>[];
        final exact =
            plural.cases.entries
                .where((entry) => entry.key is ExactPluralCase)
                .toList(growable: false)
              ..sort((a, b) => a.key.compareTo(b.key));
        for (final entry in exact) {
          final value = (entry.key as ExactPluralCase).value;
          lines.add('if (${argument.dartName} == $value) {');
          for (final line in _overridableReturn(
            entry.value,
            context,
            branch: context.branchPath(entry.key.label),
          )) {
            lines.add('  $line');
          }
          lines.add('}');
        }
        final afterExact = lines.length;

        final language = context.locale.locale.language;
        final rules = plural.type == PluralType.ordinal
            ? CldrPluralRules.ordinalForLanguage(language)
            : CldrPluralRules.forLanguage(language);
        final categories = <PluralCategory, MessageBody>{
          for (final entry in plural.cases.entries)
            if (entry.key case final CategoryPluralCase key)
              key.category: entry.value,
        };

        // Recorded for `check-overrides`, which has to tell a category this
        // locale cannot produce from one this message merely left out.
        context.pluralCategories[context.choicePrefix] = {
          for (final category in rules?.categories ?? const <PluralCategory>{})
            category.name,
        };

        final conditions =
            rules?.conditions ?? const <PluralCategory, String>{};
        final applicable = conditions.entries
            .where((entry) => categories.containsKey(entry.key))
            .toList(growable: false);
        if (applicable.isNotEmpty) {
          lines.add(_operandsStatement(context, plural, selector));
        }
        for (final entry in applicable) {
          final condition = entry.value.replaceAll('@', '$_operands.');
          lines.add('if ($condition) {');
          for (final line in _overridableReturn(
            categories[entry.key]!,
            context,
            branch: context.branchPath(entry.key.name),
          )) {
            lines.add('  $line');
          }
          lines.add('}');
        }

        final other = categories[PluralCategory.other];
        if (other == null) {
          lines.add("return '';");
        } else {
          lines.addAll(
            _overridableReturn(
              other,
              context,
              branch: context.branchPath(PluralCategory.other.name),
            ),
          );
        }
        context.popNumberSign(plural.argument);

        // Declare the adjusted value only when something reads it, so the
        // generated code never trips the unused local variable warning, and
        // as late as possible so the `=N` branches can return without
        // computing it.
        if (plural.offset != 0 &&
            lines.any((line) => line.contains(selector))) {
          final usedByExactBranch = lines
              .take(afterExact)
              .any((line) => line.contains(selector));
          lines.insert(
            usedByExactBranch ? 0 : afterExact,
            'final $selector = ${argument.dartName} - ${plural.offset};',
          );
        }
        return lines;

      case LiteralNode():
      case ArgumentNode():
      case NumberSignNode():
        return ["return '';"];
    }
  }

  /// Builds the source of a private helper method for a nested choice node.
  String _buildHelper(String name, MessageNode node, _MessageContext context) {
    final buffer = StringBuffer();
    final parameters = context.message.arguments
        .map((argument) => 'required ${argument.type} ${argument.dartName}')
        .join(', ');
    buffer.writeln('  String $name({$parameters}) {');
    for (final line in _choiceStatements(node, context)) {
      buffer.writeln('    $line');
    }
    buffer.writeln('  }');
    return buffer.toString();
  }

  static String _docComment(MessageBody body) {
    final buffer = StringBuffer();
    for (final node in body.nodes) {
      switch (node) {
        case LiteralNode():
          buffer.write(node.value);
        case ArgumentNode():
          buffer.write(
            node.format == null
                ? '{${node.name}}'
                : '{${node.name}, ${node.format}}',
          );
        case NumberSignNode():
          buffer.write('#');
        case PluralNode():
          buffer.write('{${node.argument}, plural, ...}');
        case SelectNode():
          buffer.write('{${node.argument}, select, ...}');
      }
    }
    final text = _escapeDoc(buffer.toString()).replaceAll('\n', ' ').trim();
    const limit = 80;
    if (text.length <= limit) return text;
    return '${text.substring(0, limit - 1)}…';
  }

  /// Escapes text that goes into a doc comment.
  ///
  /// Square brackets would otherwise be read as unresolved DartDoc references,
  /// which the analyzer reports on a clean project.
  static String _escapeDoc(String value) =>
      value.replaceAll('[', r'\[').replaceAll(']', r'\]');

  static String _stringLiteral(String value) => "'${_escapeContent(value)}'";

  static String _escapeContent(String value) {
    final buffer = StringBuffer();
    for (final unit in value.runes) {
      switch (unit) {
        case 0x5c: // backslash
          buffer.write(r'\\');
        case 0x27: // '
          buffer.write(r"\'");
        case 0x24: // $
          buffer.write(r'\$');
        case 0x0a:
          buffer.write(r'\n');
        case 0x0d:
          buffer.write(r'\r');
        case 0x09:
          buffer.write(r'\t');
        default:
          buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }
}

/// Per message emission state: parameter lookup and generated helpers.
final class _MessageContext {
  _MessageContext(this.message, this.locale);

  /// The message being emitted.
  final MessageModel message;

  /// The locale being emitted.
  final LocaleModel locale;

  /// Source of private helper methods generated for nested choices.
  final List<String> helpers = [];

  /// Override slots emitted for this message, in emission order.
  ///
  /// Filled by the emitter as it writes each lookup, and read afterwards to
  /// build the schema `check-overrides` validates against.
  final List<OverrideSlot> slots = [];

  int _counter = 0;

  /// The argument named [name], or `null` when it is not part of the signature.
  ArgumentModel? argument(String name) {
    for (final argument in message.arguments) {
      if (argument.name == name) return argument;
    }
    return null;
  }

  /// Dart parameter name of [name], falling back to the raw name.
  String parameterName(String name) => argument(name)?.dartName ?? name;

  /// The categories the locale can produce, per choice path prefix.
  final Map<String, Set<String>> pluralCategories = {};

  /// What each choice selects on, per choice path prefix.
  ///
  /// `argument:kind`, recorded for the fingerprint. The branch names alone do
  /// not identify a nested choice: two plurals with the same categories have
  /// the same slot names in either order, and the order is what `0/` means.
  final Map<String, String> choiceSelectors = {};

  /// The branch path prefix of the choice being emitted.
  String get choicePrefix => _choices.isEmpty ? '' : '${_choices.last}';

  /// The branch path of the branch labelled [label].
  ///
  /// A branch of the message itself is its own label. A branch of a nested
  /// choice carries that choice's number, which is the same number its
  /// rendering has as the `#n` token of the text around it — so `0/one` and
  /// `{#0}` are two views of the one place in the message, and both stay put
  /// as long as the message's structure does. Flat rather than hierarchical:
  /// the numbers are unique within a message already, and a path of three
  /// segments would be one more thing for a bundle to get wrong.
  String branchPath(String label) =>
      _choices.isEmpty ? label : '${_choices.last}/$label';

  /// The format declared for [name], with no node of its own to consult.
  ///
  /// What a bare `{name}` in this locale would render through, which is also
  /// what a token standing for an argument this branch does not interpolate
  /// has to render through.
  ArgumentFormat? declaredFormat(String name) => _resolveFormat(name, null);

  /// The format [node] renders with in this locale.
  ///
  /// The message always beats the metadata, in every locale: what is written
  /// in the string decides the style. Otherwise this locale's own declaration
  /// applies, and failing that the base locale's. Either way the locale's
  /// currency settings are folded in, so a bundle can pin its own currency or
  /// fraction digits without restating the style.
  ArgumentFormat? formatOf(ArgumentNode node) =>
      _resolveFormat(node.name, node.format);

  ArgumentFormat? _resolveFormat(String name, ArgumentFormat? inMessage) {
    final override = message.formatOverrides[locale.tag]?[name];
    final format = inMessage ?? override ?? argument(name)?.format;
    if (format == null) return null;

    final options = override?.currency;
    if (options == null || !IntlFormatters.acceptsCurrencyOptions(format)) {
      return format;
    }
    return ArgumentFormat(
      format.kind,
      format.style,
      options.merge(format.currency ?? const CurrencyOptions()),
    );
  }

  final Map<String, List<String>> _numberSigns = {};
  final List<String> _countStack = [];
  final List<int> _choices = [];
  final Map<MessageNode, ({int index, String call})> _nested = {};

  /// The plural argument `#` refers to here, or `null` outside a plural.
  String? get currentCount => _countStack.lastOrNull;

  /// The helper number and call expression recorded for a nested choice.
  ({int index, String call})? nestedChoice(MessageNode node) => _nested[node];

  /// The expression `#` stands for inside the plural on [argument].
  ///
  /// With `offset:` this is the adjusted local, not the parameter itself.
  String numberSignName(String argument) =>
      _numberSigns[argument]?.lastOrNull ?? parameterName(argument);

  /// Records what `#` means while a plural's branches are emitted.
  void pushNumberSign(String argument, String expression) {
    (_numberSigns[argument] ??= []).add(expression);
    _countStack.add(argument);
  }

  /// Undoes the matching [pushNumberSign].
  void popNumberSign(String argument) {
    _numberSigns[argument]?.removeLast();
    _countStack.removeLast();
  }

  /// Registers a helper for [node] and returns the call expression.
  String helperCall(MessageNode node, DartEmitter emitter) {
    final index = _counter++;
    final name = '_${message.dartName}\$$index';
    final arguments = message.arguments
        .map((argument) => '${argument.dartName}: ${argument.dartName}')
        .join(', ');
    final call = '$name($arguments)';
    // Recorded before the helper is built: its own body may nest further, and
    // the enclosing text needs this number whichever way that goes.
    _nested[node] = (index: index, call: call);
    _choices.add(index);
    helpers.add(emitter._buildHelper(name, node, this));
    _choices.removeLast();
    return call;
  }
}
