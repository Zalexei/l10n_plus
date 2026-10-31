import 'dart:io';

import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;

import '../ast/translation_tree.dart';
import '../config.dart';
import '../diagnostic.dart';
import '../pipeline.dart';
import '../source/source_parser.dart';

/// The source format one translation file is written in.
///
/// The parsers are matched by extension and then forgotten, because nothing
/// downstream of them cares. `import` does: it writes back into the file it
/// read, so it has to know how that file spells a string and where a new key
/// may be inserted.
enum TranslationFileFormat {
  /// Nested JSON.
  json,

  /// Nested YAML.
  yaml,

  /// Flat ARB, with dots in the key for nesting.
  arb;

  /// The format `.extension` means, or `null` when no parser claims it.
  static TranslationFileFormat? ofExtension(String extension) =>
      switch (extension) {
        'json' => TranslationFileFormat.json,
        'yaml' || 'yml' => TranslationFileFormat.yaml,
        'arb' => TranslationFileFormat.arb,
        _ => null,
      };

  /// Whether keys nest through containers rather than through dotted names.
  bool get isNested => this != TranslationFileFormat.arb;
}

/// One translation file of the project, parsed and kept with its own text.
///
/// The text is kept because `import` edits it rather than rewriting it: the
/// only way to leave a developer's key order, indentation, blank lines and
/// comments exactly as they were is to touch nothing but the characters that
/// have to change.
final class CatalogFile {
  /// Creates a file record.
  CatalogFile({
    required this.path,
    required this.relativePath,
    required this.uri,
    required this.content,
    required this.format,
    required this.namespaceSegments,
    required this.document,
  });

  /// Absolute path on disk.
  final String path;

  /// Path relative to the project root, which is what a report prints.
  final String relativePath;

  /// Where the file came from, for diagnostic spans.
  final Uri uri;

  /// The file exactly as it is on disk.
  final String content;

  /// How the file spells a string.
  final TranslationFileFormat format;

  /// Groups the file's keys sit under, from `{namespace}` in `file_pattern`.
  final List<String> namespaceSegments;

  /// The parsed tree, with paths relative to the file's own root.
  final TranslationDocument document;

  /// Full dotted key [leaf] has in the generated API.
  ///
  /// A file matched by a `{namespace}` pattern writes its keys relative to the
  /// namespace, so the file's own path is only part of the answer.
  String keyOf(TranslationLeaf leaf) =>
      [...namespaceSegments, leaf.path].join('.');

  /// The dotted prefix every key of this file starts with, possibly empty.
  String get namespace => namespaceSegments.join('.');
}

/// One message of one locale, and the file it lives in.
final class CatalogMessage {
  /// Creates a message record.
  CatalogMessage({required this.key, required this.file, required this.leaf});

  /// Full dotted key.
  final String key;

  /// The file that defines it.
  final CatalogFile file;

  /// The leaf, which carries the text and its span.
  final TranslationLeaf leaf;

  /// The message exactly as authored, before ICU parsing.
  String get raw => leaf.raw;
}

/// Everything one locale has, across however many files it is spread over.
final class LocaleCatalog {
  /// Creates a locale's catalog.
  LocaleCatalog({
    required this.locale,
    required this.files,
    required this.messages,
  });

  /// The locale.
  final L10nLocale locale;

  /// Its files, in path order.
  final List<CatalogFile> files;

  /// Its messages by full dotted key.
  final Map<String, CatalogMessage> messages;

  /// The locale as a file tag, e.g. `pt_BR`.
  String get tag => locale.toFileTag();
}

/// One row of the interchange: a message, as the base locale writes it.
final class CatalogEntry {
  /// Creates an entry.
  const CatalogEntry({
    required this.key,
    required this.baseText,
    this.description,
  });

  /// Full dotted key.
  final String key;

  /// The base locale's text, exactly as authored.
  final String baseText;

  /// What the source said the message is for, when it said anything.
  ///
  /// ARB carries it as `@key.description`; JSON and YAML have nowhere to put
  /// it, so it is absent there.
  final String? description;
}

/// The project's translations, read for interchange rather than codegen.
///
/// `generate` needs a validated model and throws the files away; `export` and
/// `import` need the opposite — the files, their formats, and where in each
/// one every message physically sits. This is that view.
final class TranslationCatalog {
  TranslationCatalog._({
    required this.config,
    required this.locales,
    required this.entries,
  });

  /// The configuration the catalog was read with.
  final L10nPlusConfig config;

  /// Every locale, the base locale first and the rest by tag.
  ///
  /// Base first because that is the order a translator reads: the source text,
  /// then the languages it becomes.
  final List<LocaleCatalog> locales;

  /// Every message the base locale defines, in base locale document order.
  ///
  /// A key only another locale has is deliberately absent: the base locale is
  /// the generated API, so a key it does not define is not a message anyone
  /// can call, and sending it to a translator would be asking for work that
  /// cannot be used.
  final List<CatalogEntry> entries;

  /// The base locale.
  LocaleCatalog get base => locales.first;

  /// Every locale but the base one.
  List<LocaleCatalog> get targets => locales.skip(1).toList(growable: false);

  /// The locale with this file [tag], or `null`.
  LocaleCatalog? localeFor(String tag) {
    for (final locale in locales) {
      if (locale.tag == tag) return locale;
    }
    return null;
  }

  /// Reads every translation file of the project.
  ///
  /// Returns `null` when there is nothing to work with, having said why.
  /// Everything the parsers report goes to [diagnostics], so a file that is
  /// not valid JSON is the caller's problem to refuse on.
  ///
  /// Reading stops at the parsers on purpose. Validation is not run, and must
  /// not be: a locale missing half its keys, or carrying a key the base locale
  /// dropped last week, is an error under the default configuration — and it
  /// is also exactly the project that needs a translator. A round trip that
  /// only worked on projects with nothing left to translate would be a
  /// workflow for nobody.
  static TranslationCatalog? load({
    required L10nPlusConfig config,
    required String projectRoot,
    required DiagnosticCollector diagnostics,
    List<TranslationSourceParser> parsers = L10nPlusGenerator.defaultParsers,
  }) {
    final root = resolveProjectPath(projectRoot, config.inputDirectory);
    final directory = Directory(root);
    if (!directory.existsSync()) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_input_directory',
          message:
              'Translation directory "${config.inputDirectory}" does not '
              'exist.',
          details: 'Looked in $root.',
        ),
      );
      return null;
    }

    final byExtension = {
      for (final parser in parsers)
        for (final extension in parser.extensions) extension: parser,
    };
    final files =
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => byExtension.containsKey(
                p.extension(file.path).replaceFirst('.', ''),
              ),
            )
            .toList(growable: false)
          // Path order, so that a report never depends on the file system.
          ..sort((a, b) => a.path.compareTo(b.path));

    final byLocale = <String, List<CatalogFile>>{};
    for (final file in files) {
      final extension = p.extension(file.path).replaceFirst('.', '');
      final parser = byExtension[extension]!;
      final format = TranslationFileFormat.ofExtension(extension);
      if (format == null) continue;

      var relative = p.isWithin(root, file.path)
          ? p.relative(file.path, from: root)
          : p.basename(file.path);
      relative = p.withoutExtension(relative).replaceAll(r'\', '/');
      final matched = config.pathPattern.match(relative);
      if (matched == null && !parser.declaresLocale) continue;

      final content = file.readAsStringSync();
      final document = parser.parse(
        content: content,
        uri: file.uri,
        localeHint: matched?.locale,
        diagnostics: diagnostics,
      );
      if (document == null) continue;

      (byLocale[document.locale.toFileTag()] ??= []).add(
        CatalogFile(
          path: file.path,
          relativePath: p.relative(file.path, from: projectRoot),
          uri: file.uri,
          content: content,
          format: format,
          namespaceSegments: matched?.namespaceSegments ?? const [],
          document: document,
        ),
      );
    }

    final baseTag = config.baseLocale.toFileTag();
    if (!byLocale.containsKey(baseTag)) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_base_locale',
          message: 'No translation file for the base locale "$baseTag".',
          details:
              'The base locale defines which messages exist, so there is '
              'nothing to export or import without it.',
        ),
      );
      return null;
    }

    final tags = byLocale.keys.toList()..sort();
    final locales = [
      for (final tag in [baseTag, ...tags.where((tag) => tag != baseTag)])
        _localeCatalogOf(byLocale[tag]!),
    ];

    final entries = <CatalogEntry>[];
    for (final file in locales.first.files) {
      for (final leaf in leavesOf(file.document.root)) {
        entries.add(
          CatalogEntry(
            key: file.keyOf(leaf),
            baseText: leaf.raw,
            description: leaf.metadata.description,
          ),
        );
      }
    }

    return TranslationCatalog._(
      config: config,
      locales: locales,
      entries: entries,
    );
  }

  static LocaleCatalog _localeCatalogOf(List<CatalogFile> files) {
    final messages = <String, CatalogMessage>{};
    for (final file in files) {
      for (final leaf in leavesOf(file.document.root)) {
        final key = file.keyOf(leaf);
        // First file wins, which is what the merger does with a duplicate;
        // the duplicate itself is an error the validation run already made.
        messages.putIfAbsent(
          key,
          () => CatalogMessage(key: key, file: file, leaf: leaf),
        );
      }
    }
    return LocaleCatalog(
      locale: files.first.document.locale,
      files: files,
      messages: messages,
    );
  }
}

/// Every leaf under [group], in document order.
Iterable<TranslationLeaf> leavesOf(TranslationGroup group) sync* {
  for (final child in group.children) {
    switch (child) {
      case final TranslationLeaf leaf:
        yield leaf;
      case final TranslationGroup nested:
        yield* leavesOf(nested);
    }
  }
}
