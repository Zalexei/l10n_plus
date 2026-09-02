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
import 'model/argument.dart';
import 'model/dart_identifiers.dart';
import 'model/localization_model.dart';
import 'model/model_builder.dart';
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

/// Outcome of one pipeline run.
final class GenerationResult {
  /// Creates a result.
  GenerationResult({
    required this.diagnostics,
    required this.files,
    this.keys = const [],
    this.ignoredCount = 0,
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
      ),
    for (final child in namespace.children)
      ..._keysOf(child, [...prefix, child.dartName]),
  ];

  /// Reads the project's Dart sources and reports translations nothing uses.
  ///
  /// The output directory is skipped: what the generator wrote is not a use.
  /// So are `.dart_tool` and `build`, which hold copies of it.
  UnusedKeyReport findUnusedKeys(GenerationResult result) =>
      UnusedKeyScanner.scan(keys: result.keys, sources: _readDartSources());

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
    final baseSignatures = <String, MessageSignature>{
      for (final message in base.messages.values)
        message.path: MessageSignature.infer(
          message.body,
          translationKey: message.path,
          diagnostics: diagnostics,
        ),
    };

    CrossLocaleValidator.validate(
      base: base,
      others: locales.where((locale) => locale != base).toList(growable: false),
      baseSignatures: baseSignatures,
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
