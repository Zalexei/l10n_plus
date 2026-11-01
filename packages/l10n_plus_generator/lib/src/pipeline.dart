import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:l10n_plus/l10n_plus.dart';

import 'ast/translation_tree.dart';
import 'codegen/dart_emitter.dart';
import 'codegen/flutter_emitter.dart';
import 'config.dart';
import 'diagnostic.dart';
import 'icu/icu_parser.dart';
import 'links/link_resolver.dart';
import 'model/argument.dart';
import 'model/dart_identifiers.dart';
import 'model/localization_model.dart';
import 'model/model_builder.dart';
import 'overrides/override_schema.dart';
import 'rich/rich_key.dart';
import 'source/arb_source_parser.dart';
import 'source/json_source_parser.dart';
import 'source/document_merger.dart';
import 'source/file_pattern.dart';
import 'validation/unused_key_scanner.dart';
import 'source/source_parser.dart';
import 'source/yaml_source_parser.dart';
import 'validation/cross_locale_validator.dart';

/// One translation file, already read.
///
/// The pipeline never touches the file system itself: [L10nPlusGenerator.run]
/// loads these with `dart:io`, and the `build_runner` adapter loads them as
/// build assets so that changes trigger a rebuild.
final class TranslationInput {
  /// Creates an input.
  const TranslationInput({
    required this.path,
    required this.uri,
    required this.content,
  });

  /// Path used for locale detection and diagnostics.
  final String path;

  /// Where the file came from, used in diagnostic spans.
  final Uri uri;

  /// File contents.
  final String content;
}

/// A file the generator wants to write.
final class GeneratedFile {
  /// Creates a generated file.
  GeneratedFile({required this.path, required this.contents});

  /// Path relative to the project root.
  final String path;

  /// Formatted Dart source.
  final String contents;
}

/// How much of the base locale one locale actually translates.
///
/// The question a partial rollout is asking. It is only ever interesting
/// alongside `fill_missing_from_base`: without it an untranslated key is an
/// error and there is no partial state to report.
final class LocaleCoverage {
  /// Creates a coverage figure.
  const LocaleCoverage({
    required this.locale,
    required this.translated,
    required this.total,
  });

  /// The locale, as a file tag.
  final String locale;

  /// Messages this locale defines itself.
  final int translated;

  /// Messages the base locale defines.
  final int total;

  /// Messages falling back to the base locale.
  int get untranslated => total - translated;

  /// Whether nothing is missing.
  bool get isComplete => untranslated == 0;

  /// Rounded down, so 99% never reads as complete.
  int get percent => total == 0 ? 100 : (translated * 100) ~/ total;
}

/// Outcome of one pipeline run.
final class GenerationResult {
  /// Creates a result.
  GenerationResult({
    required this.diagnostics,
    required this.files,
    this.keys = const [],
    this.ignoredCount = 0,
    this.coverage = const [],
    this.overrides = const OverrideCatalog([]),
    this.linkedKeys = const {},
  });

  /// Everything reported along the way, in stage order.
  final List<Diagnostic> diagnostics;

  /// Files to write. Empty when generation stopped at an error.
  final List<GeneratedFile> files;

  /// Every message the base locale defines, in generated order.
  ///
  /// For tools that ask questions about the result rather than write it —
  /// today, which keys nothing uses.
  final List<TranslationKey> keys;

  /// How much of the base locale each locale translates, in locale order.
  ///
  /// Empty when generation stopped before a model existed.
  final List<LocaleCoverage> coverage;

  /// Every override lookup the generated code performs, per locale.
  ///
  /// Empty unless `runtime_overrides` is on, which is also what
  /// `check-overrides` refuses on: a bundle checked against a project that
  /// consults nothing would pass and then do nothing.
  ///
  /// Recorded by the emitter as it writes the lookups rather than derived a
  /// second time, so the shape a bundle is validated against is the shape the
  /// application actually asks the store for.
  final OverrideCatalog overrides;

  /// Every key some message links to, in any locale.
  ///
  /// The `unused` scan reads it: a message reached by `@:brand.name` and never
  /// named in Dart is used, and reporting it would be the one direction that
  /// scan must not err in — a suggestion to delete a key the build depends on.
  final Set<String> linkedKeys;

  /// How many warnings `ignore_diagnostics` dropped.
  ///
  /// Surfaced so the CLI can say that the report is shorter than it would
  /// have been, rather than a project quietly forgetting what it silenced.
  final int ignoredCount;

  /// Whether any error was reported.
  bool get hasErrors => diagnostics.any((d) => d.severity == Severity.error);
}

/// Reads translations, validates them and produces Dart source.
///
/// The pipeline performs no writes: the CLI, and later a `build_runner`
/// adapter, decide what to do with [GenerationResult.files].
final class L10nPlusGenerator {
  /// Creates a generator for [config] rooted at [projectRoot].
  L10nPlusGenerator({
    required this.config,
    required this.projectRoot,
    this.parsers = defaultParsers,
  });

  /// The formats read out of the box.
  static const List<TranslationSourceParser> defaultParsers = [
    JsonSourceParser(),
    ArbSourceParser(),
    YamlSourceParser(),
  ];

  /// Generation options.
  final L10nPlusConfig config;

  /// Directory every relative path is resolved against.
  final String projectRoot;

  /// Source format parsers, matched by file extension.
  final List<TranslationSourceParser> parsers;

  /// Reads the input directory from disk and generates.
  ///
  /// Pass the [diagnostics] the configuration was parsed with, so that a
  /// configuration error is part of the result rather than something the
  /// caller has to remember to check separately. `L10nPlusConfig.parse`
  /// returns a usable object with defaults for the values it rejected, so a
  /// caller that only looks at [GenerationResult.hasErrors] would otherwise
  /// generate from a configuration it had already reported as wrong.
  GenerationResult run({DiagnosticCollector? diagnostics}) {
    diagnostics = (diagnostics ?? DiagnosticCollector())
      ..ignore(config.ignoreDiagnostics);
    if (diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }
    final inputs = _readInputs(diagnostics);
    if (inputs == null) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }
    final pubspec = File(resolveProjectPath(projectRoot, 'pubspec.yaml'));
    return generate(
      inputs,
      pubspec: pubspec.existsSync() ? pubspec.readAsStringSync() : null,
      diagnostics: diagnostics,
    );
  }

  /// Explains what was found instead of [wanted], and why.
  ///
  /// Naming the *files* matters more than naming the locales: the usual cause
  /// is a file called `app_en.json`, which parses as the locale `app_EN`
  /// because `app_en` is itself a valid tag. Saying only "found: app_EN"
  /// leaves the reader to work that out.
  String _missingLocaleHelp(
    List<TranslationDocument> documents,
    L10nLocale wanted,
  ) {
    final buffer = StringBuffer('Found:\n');
    for (final document in documents) {
      final name = document.uri.pathSegments.isEmpty
          ? document.uri.toString()
          : document.uri.pathSegments.last;
      buffer.writeln('  $name -> ${document.locale.toFileTag()}');
    }

    final tag = wanted.toFileTag();
    final nearby = documents
        .where((document) {
          final name = p.basenameWithoutExtension(document.uri.path);
          return document.locale != wanted &&
              name.toLowerCase().contains(tag.toLowerCase());
        })
        .toList(growable: false);

    if (nearby.isEmpty) {
      buffer.write(
        'Name a file after the locale, or say where the locale sits with '
        '"file_pattern".',
      );
      return buffer.toString();
    }

    final example = p.basenameWithoutExtension(nearby.first.uri.path);
    final index = example.toLowerCase().indexOf(tag.toLowerCase());
    final pattern =
        '${example.substring(0, index)}{locale}'
        '${example.substring(index + tag.length)}';
    return (buffer..write(
          'The whole name is read as the locale, so "$example" is the '
          'locale "${nearby.first.locale.toFileTag()}".\n'
          'Say where the locale sits:\n'
          '  file_pattern: "$pattern"',
        ))
        .toString();
  }

  /// What each locale translates of the base locale.
  ///
  /// A message counts as translated when the locale has a body of its own;
  /// one filled from the base does not, which is the same rule the emitter
  /// uses to mark a member untranslated.
  static List<LocaleCoverage> _coverageOf(LocalizationModel model) {
    final messages = <MessageModel>[];
    void collect(NamespaceModel namespace) {
      messages.addAll(namespace.messages);
      namespace.children.forEach(collect);
    }

    collect(model.root);
    return [
      for (final locale in model.locales)
        LocaleCoverage(
          locale: locale.locale.toFileTag(),
          translated: messages
              .where((m) => m.bodies.containsKey(locale.tag))
              .length,
          total: messages.length,
        ),
    ];
  }

  /// Every base locale message the last generation produced, flattened.
  static List<TranslationKey> _keysOf(
    NamespaceModel namespace, [
    List<String> prefix = const [],
  ]) => [
    for (final message in namespace.messages)
      TranslationKey(
        path: message.path,
        dartPath: [...prefix, message.dartName],
        keySpan: message.keySpan,
        // A rich message is usually reached through the Flutter wrapper
        // rather than through the span accessor, and both names mean the
        // message is in use.
        leafAliases: message.isRich ? [message.richWrapperName] : const [],
      ),
    for (final child in namespace.children)
      ..._keysOf(child, [...prefix, child.dartName]),
  ];

  /// Reads the project's Dart sources and reports translations nothing uses.
  ///
  /// The output directory is skipped: what the generator wrote is not a use.
  /// So are `.dart_tool` and `build`, which hold copies of it.
  UnusedKeyReport findUnusedKeys(GenerationResult result) =>
      UnusedKeyScanner.scan(
        keys: result.keys,
        sources: _readDartSources(),
        linked: result.linkedKeys,
      );

  List<DartSource> _readDartSources() {
    final root = Directory(projectRoot);
    if (!root.existsSync()) return const [];
    final generated = p.canonicalize(
      resolveProjectPath(projectRoot, config.outputDirectory),
    );

    final sources = <DartSource>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;
      final path = p.canonicalize(entity.path);
      if (p.isWithin(generated, path) || path == generated) continue;
      if (p
          .split(p.relative(path, from: p.canonicalize(projectRoot)))
          .any((part) => part == '.dart_tool' || part == 'build')) {
        continue;
      }
      sources.add(
        DartSource(path: entity.path, content: entity.readAsStringSync()),
      );
    }
    sources.sort((a, b) => a.path.compareTo(b.path));
    return sources;
  }

  /// Runs every stage up to and including code generation, without any IO.
  ///
  /// [pubspec] is the project's `pubspec.yaml`, used only to check whether
  /// `package:intl` is available when the generated code needs it.
  GenerationResult generate(
    List<TranslationInput> inputs, {
    String? pubspec,
    DiagnosticCollector? diagnostics,
  }) {
    // Armed here rather than at construction because a caller that parsed the
    // configuration into this collector — the builder does — must keep the
    // complaints about the configuration itself.
    diagnostics = (diagnostics ?? DiagnosticCollector())
      ..ignore(config.ignoreDiagnostics);
    final documents = _parseInputs(inputs, diagnostics);
    if (documents == null || diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }

    final locales = <LocaleMessages>[];
    for (final document in documents) {
      locales.add(_parseMessages(document, diagnostics));
    }
    if (diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }

    final base = locales.firstWhere(
      (locale) => locale.locale == config.baseLocale,
    );
    // A rich message exists and can be linked *from* nowhere and *to*
    // nothing, so the resolver needs to know which keys they are. Both
    // spellings, because a translation writes the suffix and a link does not.
    final richPaths = <String>{
      for (final message in base.messages.values)
        if (RichKey.isRich(message.leaf.key)) ...{
          message.path,
          RichKey.baseName(message.path),
        },
    };

    // Links are settled before anything compares one locale against another,
    // because a link changes what a message's parameters *are*: a message
    // that links to a plural has to supply its count. Resolved per locale —
    // a translator can write a link too, and a link nothing defines is as
    // wrong in Russian as in English — with the base locale first, so the one
    // diagnostic about a mistake copied into twelve files points at the file
    // the project is maintained in.
    final others = locales
        .where((locale) => locale != base)
        .toList(growable: false);
    final reportedLinks = <String>{};
    final linkedKeys = <String>{};
    final linkArguments = <String, Map<String, List<ArgumentSpec>>>{};
    var baseSignatures = <String, MessageSignature>{};
    for (final locale in [base, ...others]) {
      final isBase = locale == base;
      // A non base locale's signature is inferred twice: here, to feed the
      // resolver, and again by the validator, which is what compares it. Only
      // one of them may report what inference finds, or every kind conflict
      // outside the base locale would be printed twice.
      final signatures = <String, MessageSignature>{
        for (final message in locale.messages.values)
          message.path: MessageSignature.infer(
            message.body,
            translationKey: message.path,
            diagnostics: isBase ? diagnostics : DiagnosticCollector(),
          ),
      };
      final resolution = LinkResolver.resolve(
        signatures: signatures,
        richPaths: richPaths,
        diagnostics: diagnostics,
        reported: reportedLinks,
      );
      linkArguments[locale.locale.toFileTag()] = resolution.arguments;
      for (final signature in signatures.values) {
        for (final link in signature.links) {
          linkedKeys.add(link.path);
        }
      }
      if (!isBase) continue;
      // Folded in rather than re inferred: the resolver has already decided
      // these are compatible with what the message declares itself, and
      // checking them twice would report every conflict twice.
      for (final entry in resolution.arguments.entries) {
        final signature = signatures[entry.key];
        if (signature == null) continue;
        for (final spec in entry.value) {
          signature.arguments.putIfAbsent(spec.name, () => spec);
        }
      }
      baseSignatures = signatures;
    }
    if (diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }

    CrossLocaleValidator.validate(
      base: base,
      others: others,
      baseSignatures: baseSignatures,
      linkArguments: linkArguments,
      diagnostics: diagnostics,
      fillMissingFromBase: config.fillMissingFromBase,
      extraKeys: config.extraKeys,
    );
    if (diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }

    final localeModels = [
      for (final locale in locales)
        LocaleModel(
          locale: locale.locale,
          dartName: DartIdentifiers.lowerCamel(locale.locale.toFileTag()),
        ),
    ];
    final model =
        ModelBuilder(
          className: config.className,
          localeEnumName: config.localeEnumName,
          base: base,
          locales: locales,
          baseSignatures: baseSignatures,
          diagnostics: diagnostics,
        ).build(
          baseLocaleModel: localeModels.firstWhere(
            (locale) => locale.locale == config.baseLocale,
          ),
          fallbackLocaleModel: localeModels.firstWhere(
            (locale) => locale.locale == config.fallbackLocale,
          ),
          localeModels: localeModels,
        );
    if (model == null || diagnostics.hasErrors) {
      return GenerationResult(
        diagnostics: diagnostics.diagnostics,
        files: const [],
        ignoredCount: diagnostics.ignoredCount,
      );
    }

    final formatter = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    );
    final emitter = DartEmitter(model, config);
    final core = <GeneratedFile>[];
    if (config.filePerLocale) {
      final rendered = emitter.emitSplit(
        sharedFileName: config.outputFileName,
        partFileName: (locale) => config.localeOutputFileName(locale.tag),
        deferred: config.deferredLocales,
      );
      rendered.forEach((name, contents) {
        core.add(
          GeneratedFile(
            path: p.join(config.outputDirectory, name),
            contents: formatter.format(contents),
          ),
        );
      });
    } else {
      core.add(
        GeneratedFile(
          path: p.join(config.outputDirectory, config.outputFileName),
          contents: formatter.format(emitter.emit()),
        ),
      );
    }
    if (emitter.formatters.isNotEmpty) {
      _checkIntlDependency(pubspec, diagnostics);
    }
    if (config.flutter.enabled) {
      _checkFlutterDependency(pubspec, diagnostics);
    }
    if (!config.bidiIsolation) {
      _checkBidiIsolation(model, diagnostics);
    }

    final files = <GeneratedFile>[
      ...core,
      if (config.flutter.enabled)
        GeneratedFile(
          path: p.join(config.outputDirectory, config.flutterOutputFileName),
          contents: formatter.format(FlutterEmitter(model, config).emit()),
        ),
    ];

    return GenerationResult(
      diagnostics: diagnostics.diagnostics,
      files: files,
      keys: _keysOf(model.root),
      ignoredCount: diagnostics.ignoredCount,
      coverage: _coverageOf(model),
      overrides: emitter.overrides,
      linkedKeys: linkedKeys,
    );
  }

  /// Warns when generated code will import `package:intl` but the project does
  /// not depend on it.
  ///
  /// Without this the developer meets an unresolved import in generated code,
  /// which reads like a bug in the generator rather than a missing dependency.
  void _checkIntlDependency(String? pubspec, DiagnosticCollector diagnostics) {
    if (pubspec == null) return;

    final Object? document;
    try {
      document = loadYaml(pubspec);
    } on YamlException {
      return; // Not our file to complain about.
    }
    if (document is! YamlMap) return;
    final dependencies = document['dependencies'];
    if (dependencies is YamlMap && dependencies.containsKey('intl')) return;

    diagnostics.add(
      Diagnostic.warning(
        code: 'missing_intl_dependency',
        message:
            'Generated code formats numbers or dates, so it imports '
            'package:intl, but this project does not depend on it.',
        details:
            'Add it to pubspec.yaml:\n'
            '  dependencies:\n'
            '    intl: any',
      ),
    );
  }

  /// Warns when a right to left locale interpolates values that are not
  /// isolated.
  ///
  /// The one diagnostic in the registry about something the *option* does not
  /// do, which needs a reason. A value is whatever somebody typed, so its
  /// direction is not the sentence's, and the bidi algorithm will reorder the
  /// two against each other — measurably, which
  /// `packages/l10n_plus_flutter/test/bidi_isolation_test.dart` does. The
  /// result is text that is wrong on the screen and right in every string
  /// comparison, which is the class of defect this library exists to move to
  /// build time. It cannot be made the default, because it puts two invisible
  /// characters into most generated strings; so it is said once instead.
  ///
  /// Silent for a project with no right to left locale, and for one whose
  /// messages interpolate nothing: the hazard needs a value and a direction to
  /// disagree about.
  void _checkBidiIsolation(
    LocalizationModel model,
    DiagnosticCollector diagnostics,
  ) {
    final rightToLeft = [
      for (final locale in model.locales)
        if (locale.locale.isRightToLeft) locale.locale.toLanguageTag(),
    ];
    if (rightToLeft.isEmpty) return;
    if (!_interpolatesAnything(model.root)) return;

    diagnostics.add(
      Diagnostic.warning(
        code: 'bidi_isolation_off',
        message:
            'Values are interpolated into ${rightToLeft.join(', ')}, which '
            'is written right to left, and nothing isolates them.',
        details:
            'A value is whatever somebody typed, so its direction is not the '
            'sentence\'s, and the two get reordered against each other: a '
            'value ending in "." is laid out with the stop on the wrong side '
            'of it, a value beginning with digits is laid out back to front, '
            'and "-5%" becomes "5%-". Every string comparison still passes.\n'
            'Turn it on in l10n_plus.yaml:\n'
            '  bidi_isolation: true\n'
            'It writes U+2068 and U+2069 around each interpolated value, so a '
            'test comparing a rendered message against a literal has to carry '
            'them too. If that trade is not yours to make, say so:\n'
            '  ignore_diagnostics: [bidi_isolation_off]',
      ),
    );
  }

  /// Whether any message of [namespace] interpolates a value at all.
  ///
  /// A select argument does not count: its value is a generated enum and never
  /// reaches the string.
  static bool _interpolatesAnything(NamespaceModel namespace) =>
      namespace.messages.any(
        (message) =>
            message.arguments.any((argument) => argument.selectEnum == null),
      ) ||
      namespace.children.any(_interpolatesAnything);

  /// Warns when the Flutter glue is about to be generated but the project
  /// cannot compile it.
  ///
  /// `flutter.enabled` is on by default, so a Dart project that writes the
  /// shortest configuration the CLI accepts gets a file built out of
  /// `BuildContext` and `L10nScope`, and a screen of analyzer errors with
  /// nothing saying where they came from. One warning here is the difference
  /// between a one line fix and reading generated code.
  void _checkFlutterDependency(
    String? pubspec,
    DiagnosticCollector diagnostics,
  ) {
    if (pubspec == null) return;

    final Object? document;
    try {
      document = loadYaml(pubspec);
    } on YamlException {
      return; // Not our file to complain about.
    }
    if (document is! YamlMap) return;
    final dependencies = document['dependencies'];
    final declared = dependencies is YamlMap
        ? dependencies.keys.toSet()
        : <Object?>{};

    final missing = [
      for (final name in const ['flutter', 'l10n_plus_flutter'])
        if (!declared.contains(name)) name,
    ];
    if (missing.isEmpty) return;

    diagnostics.add(
      Diagnostic.warning(
        code: 'missing_flutter_dependency',
        message:
            'The Flutter glue is generated because "flutter.enabled" is on, '
            'but this project does not depend on '
            '${missing.join(' or ')}.',
        details:
            'The generated file imports package:flutter and '
            'package:l10n_plus_flutter, so it will not compile here.\n'
            'In a Dart project, turn the glue off:\n'
            '  flutter:\n'
            '    enabled: false\n'
            'In a Flutter project, add what is missing:\n'
            '  dependencies:\n'
            '    flutter:\n'
            '      sdk: flutter\n'
            '    l10n_plus_flutter: any',
      ),
    );
  }

  /// Writes [files] to disk, creating directories as needed.
  ///
  /// Files whose contents are unchanged are left untouched so that build tools
  /// and file watchers do not see spurious modifications.
  List<String> write(List<GeneratedFile> files) {
    final written = <String>[];
    for (final file in files) {
      final target = File(resolveProjectPath(projectRoot, file.path));
      target.parent.createSync(recursive: true);
      if (target.existsSync() && target.readAsStringSync() == file.contents) {
        continue;
      }
      target.writeAsStringSync(file.contents);
      written.add(file.path);
    }
    return written;
  }

  /// Loads every translation file of the input directory.
  List<TranslationInput>? _readInputs(DiagnosticCollector diagnostics) {
    final directory = Directory(
      resolveProjectPath(projectRoot, config.inputDirectory),
    );
    if (!directory.existsSync()) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_input_directory',
          message:
              'Translation directory "${config.inputDirectory}" does not exist.',
          details: 'Looked in ${directory.path}.',
        ),
      );
      return null;
    }

    final extensions = {
      for (final parser in parsers)
        for (final extension in parser.extensions) extension: parser,
    };

    // Recursive: a pattern such as `*/{locale}` puts each locale in its own
    // directory, so the files are not all at the top level any more.
    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => extensions.containsKey(
                p.extension(file.path).replaceFirst('.', ''),
              ),
            )
            .toList(growable: false)
          // Sort by path so that generation order never depends on the file system.
          ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          code: 'no_translation_files',
          message: 'No translation files found in "${config.inputDirectory}".',
          details:
              'Supported extensions: '
              '${(extensions.keys.toList()..sort()).join(', ')}.',
        ),
      );
      return null;
    }

    return [
      for (final file in files)
        TranslationInput(
          path: file.path,
          uri: file.uri,
          content: file.readAsStringSync(),
        ),
    ];
  }

  /// Parses already loaded [inputs] into one document per locale.
  List<TranslationDocument>? _parseInputs(
    List<TranslationInput> inputs,
    DiagnosticCollector diagnostics,
  ) {
    final extensions = {
      for (final parser in parsers)
        for (final extension in parser.extensions) extension: parser,
    };
    // Sort by path so that generation order never depends on the file system.
    final sorted = inputs.toList()..sort((a, b) => a.path.compareTo(b.path));

    if (sorted.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          code: 'no_translation_files',
          message: 'No translation files found in "${config.inputDirectory}".',
          details:
              'Supported extensions: '
              '${(extensions.keys.toList()..sort()).join(', ')}.',
        ),
      );
      return null;
    }

    // Several files may belong to one locale, so they are collected first and
    // merged after, in sorted path order.
    final byLocale = <String, List<TranslationDocument>>{};
    for (final file in sorted) {
      final extension = p.extension(file.path).replaceFirst('.', '');
      final parser = extensions[extension];
      if (parser == null) continue;

      final matched = _matchPath(file.path);
      final hint = matched?.locale;
      if (hint == null && !parser.declaresLocale) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'unrecognized_file_name',
            message:
                'Skipping "${p.basename(file.path)}": ".$extension" has '
                'nowhere to declare a locale, and the path does not match the '
                'file pattern.',
            details:
                'Pattern: ${config.pathPattern}\n'
                'Rename the file to match it, or set "file_pattern".',
          ),
        );
        continue;
      }

      // The path is only a hint: a format that declares its own locale, such
      // as ARB with `@@locale`, decides for itself.
      final document = parser.parse(
        content: file.content,
        uri: file.uri,
        localeHint: hint,
        diagnostics: diagnostics,
      );
      if (document == null) continue;

      // Only a configured pattern is a claim worth checking against.
      if (config.filePattern != null &&
          hint != null &&
          document.locale != hint) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'locale_pattern_mismatch',
            message:
                'File "${p.basename(file.path)}" declares locale '
                '"${document.locale.toFileTag()}" but its path says '
                '"${hint.toFileTag()}".',
            details:
                'Pattern: ${config.pathPattern}\n'
                'The declaration wins; rename the file to agree with it.',
          ),
        );
      }

      (byLocale[document.locale.toFileTag()] ??= []).add(
        matched == null || matched.namespace == null
            ? document
            : _nest(document, matched),
      );
    }

    final documents = [
      for (final entry in byLocale.entries)
        DocumentMerger.merge(entry.value, diagnostics: diagnostics),
    ];

    if (documents.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          code: 'no_translation_files',
          message: 'No usable translation files in "${config.inputDirectory}".',
          details: 'Every file found was skipped; see the warnings above.',
        ),
      );
      return null;
    }

    if (documents.every((d) => d.locale != config.baseLocale)) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_base_locale',
          message:
              'No translation file for the base locale '
              '"${config.baseLocale.toFileTag()}".',
          details: _missingLocaleHelp(documents, config.baseLocale),
        ),
      );
      return null;
    }
    if (documents.every((d) => d.locale != config.fallbackLocale)) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_fallback_locale',
          message:
              'No translation file for the fallback locale '
              '"${config.fallbackLocale.toFileTag()}".',
        ),
      );
      return null;
    }

    documents.sort(
      (a, b) => a.locale.toFileTag().compareTo(b.locale.toFileTag()),
    );
    return documents;
  }

  /// Derives a locale from a file name.
  ///
  /// The base name must be exactly the locale tag: `en.json`, `pt_BR.json`.
  /// Guessing which half of `app_en` is a prefix is not attempted, because
  /// `app_en` is itself a valid locale tag; ARB files say `@@locale` instead.
  /// The locale [path] names according to the configured pattern.
  ///
  /// Matching is on the path relative to the input directory, with `/`
  /// separators and no extension, so `*/{locale}` sees `wallet/en`.
  FileMatch? _matchPath(String path) {
    final root = resolveProjectPath(projectRoot, config.inputDirectory);
    var relative = p.isWithin(root, path)
        ? p.relative(path, from: root)
        : p.basename(path);
    relative = p.withoutExtension(relative).replaceAll(r'\', '/');
    return config.pathPattern.match(relative);
  }

  /// Puts [document]'s keys under the namespace its path named.
  ///
  /// Done before merging, so every rule that governs several files of one
  /// locale — groups merge, leaves collide — applies to the result unchanged.
  static TranslationDocument _nest(TranslationDocument document, FileMatch at) {
    // The document root stays the unnamed root; the namespace groups go
    // between it and what the file actually wrote.
    var children = document.root.children;
    for (final key in at.namespaceSegments.reversed) {
      children = [
        TranslationGroup(
          key: key,
          path: '',
          keySpan: document.root.keySpan,
          children: children,
        ),
      ];
    }
    return TranslationDocument(
      locale: document.locale,
      uri: document.uri,
      root: _repath(
        TranslationGroup(
          key: document.root.key,
          path: '',
          keySpan: document.root.keySpan,
          children: children,
        ),
        '',
      ),
    );
  }

  /// Rewrites every [TranslationNode.path] under [node] to start at [prefix].
  ///
  /// The parser numbered the paths from the file's own root, which is no
  /// longer the document root once a namespace is wrapped around it.
  static TranslationGroup _repath(TranslationGroup node, String prefix) =>
      TranslationGroup(
        key: node.key,
        path: prefix,
        keySpan: node.keySpan,
        children: [
          for (final child in node.children)
            _repathChild(
              child,
              prefix.isEmpty ? child.key : '$prefix.${child.key}',
            ),
        ],
      );

  static TranslationNode _repathChild(TranslationNode node, String path) =>
      switch (node) {
        final TranslationGroup group => _repath(group, path),
        final TranslationLeaf leaf => TranslationLeaf(
          key: leaf.key,
          path: path,
          keySpan: leaf.keySpan,
          raw: leaf.raw,
          valueSpan: leaf.valueSpan,
          contentOffset: leaf.contentOffset,
          metadata: leaf.metadata,
        ),
      };

  LocaleMessages _parseMessages(
    TranslationDocument document,
    DiagnosticCollector diagnostics,
  ) {
    final messages = <String, ParsedMessage>{};
    void walk(TranslationGroup group) {
      for (final child in group.children) {
        switch (child) {
          case final TranslationGroup nested:
            walk(nested);
          case final TranslationLeaf leaf:
            final result = IcuMessageParser.parse(
              leaf.raw,
              valueSpan: leaf.valueSpan,
              contentOffset: leaf.contentOffset,
              translationKey: leaf.path,
            );
            diagnostics.addAll(result.diagnostics);
            final body = result.body;
            if (body != null) {
              messages[leaf.path] = ParsedMessage(leaf: leaf, body: body);
            }
        }
      }
    }

    walk(document.root);
    return LocaleMessages(
      locale: document.locale,
      uri: document.uri,
      root: document.root,
      messages: messages,
    );
  }
}
