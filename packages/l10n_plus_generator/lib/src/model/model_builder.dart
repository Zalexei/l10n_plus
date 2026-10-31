import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../ast/message_metadata.dart';
import '../codegen/intl_formatters.dart';
import '../ast/translation_tree.dart';
import '../diagnostic.dart';
import '../validation/cross_locale_validator.dart';
import 'argument.dart';
import 'dart_identifiers.dart';
import 'localization_model.dart';

/// Turns validated translations into the Dart shaped [LocalizationModel].
///
/// This is where translation keys stop being strings: identifiers are
/// normalized, collisions are reported, and select enums are named.
final class ModelBuilder {
  /// Creates a builder.
  ModelBuilder({
    required this.className,
    required this.localeEnumName,
    required this.base,
    required this.locales,
    required this.baseSignatures,
    required this.diagnostics,
  });

  /// Generated root class name.
  final String className;

  /// Generated locale enum name.
  final String localeEnumName;

  /// Base locale messages.
  final LocaleMessages base;

  /// All locales including the base, sorted by tag.
  final List<LocaleMessages> locales;

  /// Signatures inferred from the base locale.
  final Map<String, MessageSignature> baseSignatures;

  /// Where problems are reported.
  final DiagnosticCollector diagnostics;

  final Map<String, SelectEnumModel> _enums = {};
  final Map<String, _TopLevelName> _topLevelNames = {};
  List<LocaleModel> _localeModels = const [];

  /// Builds the model, or returns `null` when a fatal problem was found.
  LocalizationModel? build({
    required LocaleModel baseLocaleModel,
    required LocaleModel fallbackLocaleModel,
    required List<LocaleModel> localeModels,
  }) {
    _localeModels = localeModels;
    // Claimed before the walk, so a key colliding with one of them is reported
    // against the key, which is the thing that can be renamed.
    _claimTopLevel(
      className,
      _TopLevelName('the generated class "$className"'),
    );
    _claimTopLevel(
      localeEnumName,
      _TopLevelName('the generated locale enum "$localeEnumName"'),
    );
    for (final locale in localeModels) {
      _claimTopLevel(
        '$className${locale.classSuffix}',
        _TopLevelName('the ${locale.tag} implementation of "$className"'),
      );
    }

    final root = _namespace(base.root);
    if (diagnostics.hasErrors) return null;

    final enums = _enums.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return LocalizationModel(
      className: className,
      localeEnumName: localeEnumName,
      baseLocale: baseLocaleModel,
      fallbackLocale: fallbackLocaleModel,
      locales: localeModels,
      root: root,
      enums: enums,
    );
  }

  /// Members the generated root class declares itself.
  ///
  /// A top level key normalizing onto one of these would not compile, so it is
  /// reported as a collision instead.
  static const Map<String, String> _rootMembers = {
    'appLocale': 'the generated locale accessor',
    'l10nLocale': 'the generated locale accessor',
    'supportedLocales': 'a generated static member',
    'fallbackLocale': 'a generated static member',
    'forLocale': 'a generated static member',
    'of': 'a generated static member',
    'resolve': 'a generated static member',
  };

  /// Claims one name in the generated file's single top level namespace.
  ///
  /// Returns whether the name was free. Dart has one namespace for classes,
  /// enums, interfaces and top level functions, so a namespace interface, its
  /// per locale implementations and a select enum all compete for the same
  /// names — and two declarations of one name is a file that does not compile.
  /// Member level collisions are `claim`'s job; this is the file level one.
  bool _claimTopLevel(String name, _TopLevelName owner) {
    final previous = _topLevelNames[name];
    if (previous == null) {
      _topLevelNames[name] = owner;
      return true;
    }
    diagnostics.add(
      Diagnostic.error(
        // A select enum on either side keeps the code that case has always
        // reported; everything else is the collision class that used to go
        // undetected until `dart analyze` met the generated file.
        code: previous.isEnum || owner.isEnum
            ? 'enum_name_collision'
            : 'type_name_collision',
        message: 'Two generated declarations are both called "$name".',
        span: owner.span,
        translationKey: owner.translationKey,
        details:
            'Already taken by ${previous.description}.\n'
            'Wanted again by ${owner.description}.\n'
            'Classes, enums and interfaces share one namespace in Dart, so '
            'the generated file would declare "$name" twice. Rename one of '
            'the keys, nest one under a namespace, or rename the generated '
            'class.',
      ),
    );
    return false;
  }

  /// Claims the interface and every per locale implementation of a namespace.
  ///
  /// The implementations are claimed only when the interface itself was free.
  /// Otherwise one pair of colliding keys would be reported once per locale,
  /// and a ten locale project would print eleven errors for one rename.
  void _claimNamespace(String interfaceName, TranslationGroup group) {
    final free = _claimTopLevel(
      interfaceName,
      _TopLevelName(
        'the namespace "${group.path}"',
        span: group.keySpan,
        translationKey: group.path,
      ),
    );
    if (!free) return;
    for (final locale in _localeModels) {
      _claimTopLevel(
        '$interfaceName${locale.classSuffix}',
        _TopLevelName(
          'the ${locale.tag} implementation of the namespace "${group.path}"',
          span: group.keySpan,
          translationKey: group.path,
        ),
      );
    }
  }

  NamespaceModel _namespace(TranslationGroup group) {
    // The root's name is the generated class, claimed before the walk began.
    final interfaceName = group.path.isEmpty
        ? className
        : '\$${DartIdentifiers.upperCamelPath(group.path.split('.'))}';
    if (group.path.isNotEmpty) _claimNamespace(interfaceName, group);

    final children = <NamespaceModel>[];
    final messages = <MessageModel>[];
    final usedNames = <String, String>{
      if (group.path.isEmpty)
        for (final entry in _rootMembers.entries) entry.key: entry.value,
    };

    void claim(String dartName, TranslationNode node) {
      final previous = usedNames[dartName];
      if (previous != null) {
        final isGenerated =
            _rootMembers.containsKey(dartName) &&
            _rootMembers[dartName] == previous;
        diagnostics.add(
          Diagnostic.error(
            code: 'identifier_collision',
            message: isGenerated
                ? 'Key "${node.path}" collides with $previous.'
                : 'Keys "$previous" and "${node.path}" both become the Dart '
                      'identifier "$dartName".',
            span: node.keySpan,
            translationKey: node.path,
            details: isGenerated
                ? 'The generated class already declares "$dartName". '
                      'Rename the key, or nest it under a namespace.'
                : 'Keys are normalized to lower camel case, so "user_name" '
                      'and "userName" collide. Rename one of them.',
          ),
        );
        return;
      }
      usedNames[dartName] = node.path;
    }

    for (final child in group.children) {
      final dartName = DartIdentifiers.lowerCamel(child.key);
      if (dartName.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_key',
            message: 'Key "${child.key}" cannot be turned into a Dart name.',
            span: child.keySpan,
            translationKey: child.path,
            details: 'Use letters, digits, "_" or "-" in translation keys.',
          ),
        );
        continue;
      }
      claim(dartName, child);

      switch (child) {
        case final TranslationGroup childGroup:
          children.add(_namespace(childGroup));
        case final TranslationLeaf leaf:
          final message = _message(leaf, dartName);
          if (message != null) messages.add(message);
      }
    }

    return NamespaceModel(
      path: group.path,
      dartName: group.path.isEmpty ? '' : DartIdentifiers.lowerCamel(group.key),
      interfaceName: interfaceName,
      children: children,
      messages: messages,
    );
  }

  MessageModel? _message(TranslationLeaf leaf, String dartName) {
    final signature = baseSignatures[leaf.path];
    if (signature == null) return null;

    final arguments = <ArgumentModel>[];
    final usedParameters = <String, String>{};
    for (final spec in signature.arguments.values) {
      final parameterName = DartIdentifiers.lowerCamel(spec.name);
      if (parameterName.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_argument_name',
            message: 'Argument "${spec.name}" is not a usable Dart name.',
            span: spec.span,
            translationKey: leaf.path,
          ),
        );
        continue;
      }
      final previous = usedParameters[parameterName];
      if (previous != null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'argument_collision',
            message:
                'Arguments "$previous" and "${spec.name}" both become the '
                'Dart parameter "$parameterName".',
            span: spec.span,
            translationKey: leaf.path,
          ),
        );
        continue;
      }
      usedParameters[parameterName] = spec.name;

      final declaration = leaf.metadata.placeholders[spec.name];
      switch (spec.kind) {
        case ArgumentKind.plain:
          // A bundle exported from `gen_l10n` writes `{when}` and puts the
          // formatting in the metadata, so metadata may create a format here.
          final declaredFormat = _resolveCurrency(
            leaf,
            spec,
            _declaredFormat(leaf, spec, declaration),
            declaration,
          );
          arguments.add(
            ArgumentModel(
              name: spec.name,
              dartName: parameterName,
              type: switch ((declaredFormat, declaration?.type)) {
                // A declared numeric type is kept: `"type": "double"` with a
                // `"format"` must generate the same signature as writing
                // `{amount, number}` in the message would.
                (final ArgumentFormat format, _)
                    when format.kind == ArgumentFormatKind.number =>
                  _pluralType(leaf, spec, declaration),
                (final ArgumentFormat format, _) =>
                  IntlFormatters.parameterType(format),
                // `_declaredFormat` already reported why this has no format.
                (null, 'DateTime') => 'DateTime',
                _ => _plainType(leaf, spec, declaration),
              },
              format: declaredFormat,
              description: declaration?.description,
              example: declaration?.example,
            ),
          );
        case ArgumentKind.number:
          arguments.add(
            ArgumentModel(
              name: spec.name,
              dartName: parameterName,
              type: _pluralType(leaf, spec, declaration),
              format: _resolveCurrency(leaf, spec, spec.format, declaration),
              description: declaration?.description,
              example: declaration?.example,
            ),
          );
        case ArgumentKind.date:
        case ArgumentKind.time:
          if (declaration?.type != null && declaration!.type != 'DateTime') {
            diagnostics.add(
              Diagnostic.error(
                code: 'unsupported_placeholder_type',
                message:
                    'Argument "${spec.name}" is formatted as a '
                    '${spec.kind.label}, so it must be declared "DateTime".',
                span: declaration.span,
                translationKey: leaf.path,
                details: 'Declared type: "${declaration.type}".',
              ),
            );
          }
          arguments.add(
            ArgumentModel(
              name: spec.name,
              dartName: parameterName,
              type: 'DateTime',
              format: _resolveCurrency(leaf, spec, spec.format, declaration),
              description: declaration?.description,
              example: declaration?.example,
            ),
          );
        case ArgumentKind.plural:
          // A `gen_l10n` bundle declares the count's rendering in the
          // metadata, and honouring it is what makes the operands come from
          // the formatter rather than from the value — the two cannot be
          // separated without reproducing `USD1.00 card`.
          arguments.add(
            ArgumentModel(
              name: spec.name,
              dartName: parameterName,
              type: _pluralType(leaf, spec, declaration),
              format: _resolveCurrency(
                leaf,
                spec,
                _declaredFormat(leaf, spec, declaration),
                declaration,
              ),
              description: declaration?.description,
              example: declaration?.example,
            ),
          );
        case ArgumentKind.select:
          _resolveCurrency(leaf, spec, null, declaration);
          _reportDroppedFormat(leaf, spec, declaration);
          final selectEnum = _selectEnum(leaf, spec);
          if (selectEnum == null) continue;
          final declaredSelectType = declaration?.type;
          // `"type": "String"` is what `gen_l10n` writes on every select
          // placeholder — its own schema requires it — and `Object` is what
          // it writes when the type is left out. Warning about either puts a
          // line of noise on every select of every imported bundle, about
          // something the exporting tool chose and nobody can change without
          // hand editing a generated file. A declared `int` or `DateTime` is
          // a different matter: that is an author who thinks this argument is
          // a number, and it still warns.
          if (declaredSelectType != null &&
              !_neutralSelectTypes.contains(declaredSelectType)) {
            diagnostics.add(
              Diagnostic.warning(
                code: 'ignored_placeholder_type',
                message:
                    'Type "$declaredSelectType" on select argument '
                    '"${spec.name}" is ignored.',
                span: declaration!.span,
                translationKey: leaf.path,
                details:
                    'A select argument always generates the enum '
                    '"${selectEnum.name}".',
              ),
            );
          }
          arguments.add(
            ArgumentModel(
              name: spec.name,
              dartName: parameterName,
              type: selectEnum.name,
              selectEnum: selectEnum,
              description: declaration?.description,
              example: declaration?.example,
            ),
          );
      }
    }

    for (final declaration in leaf.metadata.placeholders.values) {
      if (signature.arguments.containsKey(declaration.name)) continue;
      diagnostics.add(
        Diagnostic.warning(
          code: 'unused_placeholder_declaration',
          message:
              'Placeholder "${declaration.name}" is declared but never used '
              'in the message.',
          span: declaration.span,
          translationKey: leaf.path,
          details: signature.arguments.isEmpty
              ? 'The message takes no arguments.'
              : 'The message uses: ${signature.arguments.keys.join(', ')}.',
        ),
      );
    }

    final bodies = <String, MessageBody>{};
    for (final locale in locales) {
      final message = locale.messages[leaf.path];
      if (message != null) bodies[locale.locale.toFileTag()] = message.body;
    }

    return MessageModel(
      path: leaf.path,
      dartName: dartName,
      keySpan: leaf.keySpan,
      arguments: arguments,
      bodies: bodies,
      formatOverrides: _formatOverrides(leaf, arguments),
      description: leaf.metadata.description,
    );
  }

  /// Folds the base locale's declared currency settings into [format].
  ///
  /// Returns [format] unchanged when nothing was declared. Everything else —
  /// settings on something that is not a currency, a malformed code, a symbol
  /// on a style that has no `symbol:` parameter, or a code that disagrees with
  /// the one written in the message — is an error, because the alternative is
  /// money rendered wrongly.
  /// Reports a `format:` on a select argument, which has no number to format.
  ///
  /// A plural count is formatted — see the plural case above — but a select
  /// argument chooses a branch, and there is nothing a `NumberFormat` could
  /// be applied to. Reported rather than discarded in silence, which is the
  /// rule everywhere else here.
  ///
  /// A warning rather than an error: the declaration comes from the exporting
  /// tool at least as often as from the author, and the generated output is
  /// still exactly what this generator promises.
  void _reportDroppedFormat(
    TranslationLeaf leaf,
    ArgumentSpec spec,
    PlaceholderMetadata? declaration,
  ) {
    final format = declaration?.format;
    if (format == null) return;
    diagnostics.add(
      Diagnostic.warning(
        code: 'dropped_placeholder_format',
        message:
            'Placeholder "${spec.name}" declares "format", but a '
            '${spec.kind.label} argument is not formatted.',
        span: declaration!.span,
        translationKey: leaf.path,
        details:
            'Declared: $format.\n'
            'A select argument chooses a branch; there is no number to '
            'format. Drop the declaration.',
      ),
    );
  }

  ArgumentFormat? _resolveCurrency(
    TranslationLeaf leaf,
    ArgumentSpec spec,
    ArgumentFormat? format,
    PlaceholderMetadata? declaration,
  ) {
    final declared = declaration?.currency;
    if (declared == null) return format;
    final span = declaration!.currencySpan ?? declaration.span;

    // `decimalDigits` is not a currency setting: `decimalPercentPattern`
    // takes it and is not money. Everything else in the declaration is.
    final onlyDigits = declared.code == null && declared.symbol == null;
    final accepted =
        format != null &&
        (IntlFormatters.acceptsCurrencyOptions(format) ||
            (onlyDigits && IntlFormatters.acceptsDecimalDigits(format)));
    if (!accepted) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unexpected_currency_code',
          message: onlyDigits
              ? 'Placeholder "${spec.name}" declares "decimalDigits" but is '
                    'not formatted in a style that takes them.'
              : 'Placeholder "${spec.name}" declares currency settings but is '
                    'not formatted as a currency.',
          span: span,
          translationKey: leaf.path,
          details: onlyDigits
              ? 'Declared: $declared.\n'
                    'Current formatting: ${format ?? 'none'}.\n'
                    'Styles that take "decimalDigits": '
                    '${_sorted(IntlFormatters.decimalDigitsStyles)}.'
              : 'Declared: $declared.\n'
                    'Current formatting: ${format ?? 'none'}.\n'
                    'Add "format": "currency" next to it, or write '
                    '{${spec.name}, number, currency} in the message.',
        ),
      );
      return format;
    }

    if (declared.code case final String code) {
      if (!IntlFormatters.isValidCurrencyCode(code)) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_currency_code',
            message: 'Invalid currency code "$code".',
            span: declaration.currencyCodeSpan ?? span,
            translationKey: leaf.path,
            details:
                'Expected an ISO 4217 code of three upper case letters.\n'
                '  found: $code',
          ),
        );
        return format;
      }
      final written = format.currency?.code;
      if (written != null && written != code) {
        diagnostics.add(
          Diagnostic.error(
            code: 'conflicting_currency_code',
            message:
                'Placeholder "${spec.name}" declares two different currencies.',
            span: declaration.currencyCodeSpan ?? span,
            translationKey: leaf.path,
            details:
                'In the message:\n'
                '  ${format.style}:$written\n'
                'In "optionalParameters":\n'
                '  $code',
          ),
        );
        return format;
      }
    }

    if (declared.symbol != null &&
        !IntlFormatters.acceptsCurrencySymbol(format)) {
      diagnostics.add(_symbolNotAccepted(leaf.path, spec.name, format, span));
      return format;
    }

    // What the message wrote wins; the metadata fills in the rest.
    final merged = (format.currency ?? const CurrencyOptions()).merge(declared);
    return ArgumentFormat(format.kind, format.style, merged);
  }

  /// [values] sorted and comma separated, for a diagnostic's details.
  static String _sorted(Set<String> values) =>
      (values.toList()..sort()).join(', ');

  /// Declared types that say nothing about a select argument.
  ///
  /// The spelling an ARB exporter uses for "this is a select"; see the use
  /// site for why they are silent.
  static const Set<String> _neutralSelectTypes = {'String', 'Object'};

  /// Dart types a `{placeholder}` may be declared as.
  ///
  /// Anything needing locale aware formatting, `DateTime` above all, is
  /// rejected rather than silently rendered with `toString`.
  static const Map<String, String> _plainTypes = {
    'String': 'String',
    'Object': 'Object',
    'int': 'int',
    'num': 'num',
    'double': 'double',
  };

  /// Dart types a plural argument may be declared as.
  static const Map<String, String> _numericTypes = {
    'int': 'int',
    'num': 'num',
    'double': 'double',
  };

  /// Formatting each non base locale declared in its own metadata.
  ///
  /// The base locale decides *whether* an argument is money or a date, and so
  /// how its Dart type is spelled; that is the API contract and cannot vary.
  /// Which style renders it, in which currency, with what symbol and how many
  /// fraction digits, is presentation, and a bundle is entitled to its own — a
  /// Russian file quoting roubles without kopecks is right, not a divergence
  /// to be flattened onto the base.
  Map<String, Map<String, ArgumentFormat>> _formatOverrides(
    TranslationLeaf baseLeaf,
    List<ArgumentModel> arguments,
  ) {
    final overrides = <String, Map<String, ArgumentFormat>>{};
    for (final locale in locales) {
      if (locale.locale == base.locale) continue;
      final message = locale.messages[baseLeaf.path];
      if (message == null) continue;

      final perArgument = <String, ArgumentFormat>{};
      for (final argument in arguments) {
        final declaration = message.leaf.metadata.placeholders[argument.name];
        if (declaration == null) continue;
        final override = _overrideFor(baseLeaf, locale, argument, declaration);
        if (override != null) perArgument[argument.name] = override;
      }
      if (perArgument.isNotEmpty) {
        overrides[locale.locale.toFileTag()] = perArgument;
      }
    }
    return overrides;
  }

  /// One locale's declaration for one argument, or `null` when it adds nothing.
  ArgumentFormat? _overrideFor(
    TranslationLeaf baseLeaf,
    LocaleMessages locale,
    ArgumentModel argument,
    PlaceholderMetadata declaration,
  ) {
    final declaredStyle = argument.format?.kind == ArgumentFormatKind.number
        ? IntlFormatters.canonicalNumberStyle(declaration.format)
        : declaration.format;
    final declaredCurrency = declaration.currency;
    if (declaredStyle == null && declaredCurrency == null) return null;

    final inheritedFormat = argument.format;
    if (inheritedFormat == null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unexpected_placeholder_format',
          message:
              'Placeholder "${argument.name}" declares formatting in '
              '${locale.locale.toFileTag()}, but the base locale formats it '
              'in no way at all.',
          span: declaration.span,
          translationKey: baseLeaf.path,
          details:
              'Declared here: '
              '${declaredStyle ?? declaredCurrency}.\n'
              'The base locale decides the generated type, so formatting '
              'cannot be introduced by one locale alone. Declare it in '
              '${base.locale.toFileTag()} too, or write it in the message.',
        ),
      );
      return null;
    }

    var format = inheritedFormat;
    if (declaredStyle != null && declaredStyle != inheritedFormat.style) {
      final restyled = ArgumentFormat(inheritedFormat.kind, declaredStyle);
      if (!IntlFormatters.isSupported(restyled)) {
        diagnostics.add(
          Diagnostic.error(
            code: 'unsupported_placeholder_format',
            message:
                'Unknown ${inheritedFormat.kind.label} format '
                '"$declaredStyle".',
            span: declaration.span,
            translationKey: baseLeaf.path,
            details:
                'The base locale formats "${argument.name}" as a '
                '${inheritedFormat.kind.label}, so only those styles apply.\n'
                'Supported: '
                '${IntlFormatters.supportedStyles(inheritedFormat.kind).join(', ')}.',
          ),
        );
        return null;
      }
      // The kind is inherited, never redeclared, so the parameter type is the
      // same in every locale however the value is rendered.
      format = ArgumentFormat(
        inheritedFormat.kind,
        declaredStyle,
        IntlFormatters.acceptsDecimalDigits(restyled)
            ? inheritedFormat.currency
            : null,
      );
    }

    if (declaredCurrency == null) {
      return format == inheritedFormat ? null : format;
    }
    return _mergeLocaleCurrency(
      baseLeaf,
      locale,
      argument,
      declaration,
      format,
      declaredCurrency,
      inheritedFormat,
    );
  }

  /// Folds one locale's declared currency settings into its [format].
  ArgumentFormat? _mergeLocaleCurrency(
    TranslationLeaf baseLeaf,
    LocaleMessages locale,
    ArgumentModel argument,
    PlaceholderMetadata declaration,
    ArgumentFormat format,
    CurrencyOptions declared,
    ArgumentFormat inheritedFormat,
  ) {
    final span = declaration.currencySpan ?? declaration.span;
    final onlyDigits = declared.code == null && declared.symbol == null;
    if (!IntlFormatters.acceptsCurrencyOptions(format) &&
        !(onlyDigits && IntlFormatters.acceptsDecimalDigits(format))) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unexpected_currency_code',
          message: onlyDigits
              ? 'Placeholder "${argument.name}" declares "decimalDigits" but '
                    'is not formatted in a style that takes them.'
              : 'Placeholder "${argument.name}" declares currency settings '
                    'but is not formatted as a currency.',
          span: span,
          translationKey: baseLeaf.path,
          details:
              'Declared here: $declared.\n'
              'Formatting in ${locale.locale.toFileTag()}: $format.',
        ),
      );
      return null;
    }

    if (declared.code case final String code
        when !IntlFormatters.isValidCurrencyCode(code)) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_currency_code',
          message: 'Invalid currency code "$code".',
          span: declaration.currencyCodeSpan ?? span,
          translationKey: baseLeaf.path,
          details:
              'Expected an ISO 4217 code of three upper case letters.\n'
              '  found: $code',
        ),
      );
      return null;
    }

    if (declared.symbol != null &&
        !IntlFormatters.acceptsCurrencySymbol(format)) {
      diagnostics.add(
        _symbolNotAccepted(baseLeaf.path, argument.name, format, span),
      );
      return null;
    }

    final inherited = format.currency ?? const CurrencyOptions();
    final merged = declared.merge(inherited);
    final result = ArgumentFormat(format.kind, format.style, merged);
    if (result == inheritedFormat) return null;

    // Only a disagreement about the *currency* is worth a warning. A different
    // symbol or fraction digit count is presentation and is expected to vary —
    // roubles without kopecks beside dollars with cents is the reason this
    // feature exists, not a mistake.
    final baseCode = inheritedFormat.currency?.code;
    if (baseCode != null && merged.code != null && baseCode != merged.code) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'currency_options_mismatch',
          message:
              'Argument "${argument.name}" is rendered in a different '
              'currency than in the base locale.',
          span: declaration.currencyCodeSpan ?? span,
          translationKey: baseLeaf.path,
          details:
              'Base locale ${base.locale.toFileTag()}:\n'
              '  $baseCode\n'
              '${locale.locale.toFileTag()} locale:\n'
              '  ${merged.code}\n'
              'Both compile; the two locales quote different money.',
        ),
      );
    }
    return result;
  }

  /// Reports a `symbol` on a style that has no `symbol:` parameter.
  static Diagnostic _symbolNotAccepted(
    String path,
    String argument,
    ArgumentFormat format,
    SourceSpan span,
  ) => Diagnostic.error(
    code: 'unsupported_currency_option',
    message:
        'The "${format.style}" style takes no explicit symbol for argument '
        '"$argument".',
    span: span,
    translationKey: path,
    details:
        '"simpleCurrency" derives the symbol from the currency, which is the '
        'whole difference between it and "currency".\n'
        'Use "format": "currency" with the symbol, or drop the symbol.',
  );

  /// Formats declared in metadata for an argument the message wrote plainly.
  ///
  /// ARB bundles say `{"when": {"type": "DateTime", "format": "yMMMd"}}` and
  /// write `{when}` in the message; honouring that is what makes a `gen_l10n`
  /// bundle generate correctly without editing every message.
  ArgumentFormat? _declaredFormat(
    TranslationLeaf leaf,
    ArgumentSpec spec,
    PlaceholderMetadata? declaration,
  ) {
    final type = declaration?.type;
    final style = declaration?.format;
    if (type == null && style == null) return null;

    final ArgumentFormatKind kind;
    if (type == 'DateTime') {
      if (style == null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'missing_placeholder_format',
            message:
                'Placeholder "${spec.name}" is declared as "DateTime" but no '
                'format is given.',
            span: declaration!.span,
            translationKey: leaf.path,
            details:
                'Dates have no single correct rendering, so the format must '
                'be explicit. Add "format": "yMMMd" next to the type, or '
                'write {${spec.name}, date, yMMMd} in the message.\n'
                'Available: '
                '${IntlFormatters.supportedStyles(ArgumentFormatKind.date).join(', ')}.',
          ),
        );
        return null;
      }
      kind = ArgumentFormatKind.date;
    } else if (style != null && _numericTypes.containsKey(type)) {
      kind = ArgumentFormatKind.number;
    } else {
      return null;
    }

    final format = ArgumentFormat(
      kind,
      kind == ArgumentFormatKind.number
          ? IntlFormatters.canonicalNumberStyle(style)
          : style,
    );
    if (!IntlFormatters.isSupported(format)) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unsupported_placeholder_format',
          message: 'Unknown ${kind.label} format "$style".',
          span: declaration!.span,
          translationKey: leaf.path,
          details:
              'Supported: ${IntlFormatters.supportedStyles(kind).join(', ')}.',
        ),
      );
      return null;
    }
    return format;
  }

  String _plainType(
    TranslationLeaf leaf,
    ArgumentSpec spec,
    PlaceholderMetadata? declaration,
  ) => _resolveType(
    leaf: leaf,
    spec: spec,
    declaration: declaration,
    allowed: _plainTypes,
    fallback: 'String',
  );

  String _pluralType(
    TranslationLeaf leaf,
    ArgumentSpec spec,
    PlaceholderMetadata? declaration,
  ) => _resolveType(
    leaf: leaf,
    spec: spec,
    declaration: declaration,
    allowed: _numericTypes,
    fallback: 'num',
  );

  String _resolveType({
    required TranslationLeaf leaf,
    required ArgumentSpec spec,
    required PlaceholderMetadata? declaration,
    required Map<String, String> allowed,
    required String fallback,
  }) {
    final declared = declaration?.type;
    if (declared == null) return fallback;

    final resolved = allowed[declared];
    if (resolved != null) return resolved;

    diagnostics.add(
      Diagnostic.error(
        code: 'unsupported_placeholder_type',
        message:
            'Placeholder type "$declared" is not supported for the '
            '${spec.kind.label} argument "${spec.name}".',
        span: declaration!.span,
        translationKey: leaf.path,
        details: declared == 'DateTime'
            ? 'Write {${spec.name}, date, yMMMd} in the message to format it '
                  'as a date.'
            : 'Supported here: ${(allowed.keys.toList()..sort()).join(', ')}.',
      ),
    );
    return fallback;
  }

  SelectEnumModel? _selectEnum(TranslationLeaf leaf, ArgumentSpec spec) {
    final name =
        DartIdentifiers.upperCamelPath(leaf.path.split('.')) +
        DartIdentifiers.upperCamel(spec.name);

    final free = _claimTopLevel(
      name,
      _TopLevelName(
        'the enum for "${leaf.path}" argument "${spec.name}"',
        span: spec.span,
        translationKey: leaf.path,
        isEnum: true,
      ),
    );
    if (!free) return null;

    final values = <EnumValueModel>[];
    final used = <String, String>{};
    for (final option in spec.selectOptions) {
      final valueName = DartIdentifiers.enumConstant(option);
      if (valueName.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_select_branch',
            message: 'Select branch "$option" is not a usable Dart name.',
            span: spec.span,
            translationKey: leaf.path,
          ),
        );
        continue;
      }
      final previous = used[valueName];
      if (previous != null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'select_branch_collision',
            message:
                'Select branches "$previous" and "$option" both become the '
                'enum value "$valueName".',
            span: spec.span,
            translationKey: leaf.path,
          ),
        );
        continue;
      }
      used[valueName] = option;
      values.add(EnumValueModel(dartName: valueName, icuLabel: option));
    }

    final model = SelectEnumModel(
      name: name,
      values: values,
      messagePath: leaf.path,
      argumentName: spec.name,
    );
    _enums[name] = model;
    return model;
  }
}

/// One declaration the generated file puts in Dart's top level namespace.
///
/// Recorded so a collision can name both sides: the reader needs to know what
/// already took the name as much as what wanted it again.
final class _TopLevelName {
  const _TopLevelName(
    this.description, {
    this.span,
    this.translationKey,
    this.isEnum = false,
  });

  /// Human readable phrase naming the declaration, e.g. `the namespace "auth"`.
  final String description;

  /// Where the key that produced it is, when it came from a key at all.
  final SourceSpan? span;

  /// Dotted translation key behind the declaration, when there is one.
  final String? translationKey;

  /// Whether this is a select enum, which decides the diagnostic code.
  final bool isEnum;
}
