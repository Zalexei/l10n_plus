import 'dart:convert';

import 'bundle.dart';
import 'catalog.dart';
import 'csv.dart';

/// A file `export` wants to write.
final class ExportFile {
  /// Creates an export file.
  const ExportFile({required this.name, required this.contents});

  /// File name, with no directory part.
  final String name;

  /// What to write into it.
  final String contents;
}

/// How much of the base locale one locale has, as `export` counted it.
final class ExportCoverage {
  /// Creates a figure.
  const ExportCoverage({
    required this.localeTag,
    required this.translated,
    required this.total,
  });

  /// The locale, as a file tag.
  final String localeTag;

  /// Messages this locale has text for.
  final int translated;

  /// Messages the base locale defines.
  final int total;

  /// Messages this locale has nothing for.
  int get untranslated => total - translated;
}

/// What one `export` produced.
final class ExportResult {
  /// Creates a result.
  const ExportResult({
    required this.files,
    required this.messageCount,
    required this.coverage,
  });

  /// The files to write, in the order they should be reported.
  final List<ExportFile> files;

  /// How many messages the base locale defines.
  final int messageCount;

  /// Per locale coverage, base locale first.
  final List<ExportCoverage> coverage;
}

/// Writes every message out in a format something else can read.
///
/// Nothing here touches the file system: the CLI decides where the bytes go,
/// which is the same split the generation pipeline uses and the reason both
/// can be tested without a temporary directory.
abstract final class TranslationExporter {
  /// Exports [catalog] in [format].
  static ExportResult export({
    required TranslationCatalog catalog,
    required InterchangeFormat format,
    String csvFileName = defaultCsvFileName,
  }) => switch (format) {
    InterchangeFormat.csv => _csv(catalog, csvFileName),
    InterchangeFormat.arb => _arb(catalog),
  };

  /// Default name of the single file `--format=csv` writes.
  static const String defaultCsvFileName = 'l10n_plus_export.csv';

  static ExportResult _csv(TranslationCatalog catalog, String fileName) {
    final tags = [for (final locale in catalog.locales) locale.tag];
    final records = <List<String>>[
      [
        InterchangeBundle.keyColumn,
        InterchangeBundle.descriptionColumn,
        ...tags,
      ],
    ];

    for (final entry in catalog.entries) {
      records.add([
        entry.key,
        entry.description ?? '',
        for (final locale in catalog.locales)
          // Absent, not empty: an untranslated message leaves the cell blank,
          // which is what a translator looks for and what `import` reads as
          // "nothing supplied here".
          locale.messages[entry.key]?.raw ?? '',
      ]);
    }

    return ExportResult(
      files: [ExportFile(name: fileName, contents: Csv.encode(records))],
      messageCount: catalog.entries.length,
      coverage: _coverageOf(catalog),
    );
  }

  /// One ARB bundle per locale, ready for a translation management system.
  ///
  /// An untranslated message is left out entirely rather than written with the
  /// base locale's text, because a bundle that answers "yes, translated" for
  /// every key is how English ends up shipping as Russian. Leaving it out is
  /// also what a partially translated `app_ru.arb` looks like in any Flutter
  /// project, so a vendor already knows what it means.
  ///
  /// The base text travels with each target bundle as `source_text`, which is
  /// the ARB attribute for exactly that, so a translator sees what they are
  /// translating without opening a second file.
  static ExportResult _arb(TranslationCatalog catalog) {
    final files = <ExportFile>[];
    for (final locale in catalog.locales) {
      final isBase = locale.tag == catalog.base.tag;
      final buffer = StringBuffer('{\n');
      buffer.write('  "@@locale": ${jsonEncode(locale.tag)}');

      for (final entry in catalog.entries) {
        final message = locale.messages[entry.key];
        if (message == null) continue;
        buffer.write(',\n\n');
        buffer.write('  ${jsonEncode(entry.key)}: ${jsonEncode(message.raw)}');

        final metadata = <String>[
          if (entry.description != null)
            '    "description": ${jsonEncode(entry.description)}',
          if (!isBase) '    "source_text": ${jsonEncode(entry.baseText)}',
          ...?_placeholders(catalog, entry.key),
        ];
        if (metadata.isEmpty) continue;
        // `@key` only ever next to its `key`: metadata on its own is an error
        // in this generator's own ARB reader, so writing it would produce a
        // bundle we could not read back.
        buffer.write(',\n  ${jsonEncode('@${entry.key}')}: {\n');
        buffer.write(metadata.join(',\n'));
        buffer.write('\n  }');
      }

      buffer.write('\n}\n');
      files.add(
        ExportFile(name: '${locale.tag}.arb', contents: buffer.toString()),
      );
    }

    return ExportResult(
      files: files,
      messageCount: catalog.entries.length,
      coverage: _coverageOf(catalog),
    );
  }

  /// The base locale's placeholder declarations, as ARB metadata lines.
  ///
  /// Only the three attributes a translator is served by: what the argument
  /// is, an example of it, and what it means. A placeholder's `format` and its
  /// currency settings are presentation, they are declared per locale, and
  /// `import` never writes metadata back — carrying them would be claiming a
  /// round trip the import does not make.
  static List<String>? _placeholders(TranslationCatalog catalog, String key) {
    final declared =
        catalog.base.messages[key]?.leaf.metadata.placeholders ?? const {};
    if (declared.isEmpty) return null;

    final rendered = <String>[];
    declared.forEach((name, placeholder) {
      final attributes = <String>[
        if (placeholder.type != null)
          '        "type": ${jsonEncode(placeholder.type)}',
        if (placeholder.example != null)
          '        "example": ${jsonEncode(placeholder.example)}',
        if (placeholder.description != null)
          '        "description": ${jsonEncode(placeholder.description)}',
      ];
      if (attributes.isEmpty) {
        rendered.add('      ${jsonEncode(name)}: {}');
        return;
      }
      rendered.add(
        '      ${jsonEncode(name)}: {\n${attributes.join(',\n')}\n      }',
      );
    });
    return ['    "placeholders": {\n${rendered.join(',\n')}\n    }'];
  }

  static List<ExportCoverage> _coverageOf(TranslationCatalog catalog) => [
    for (final locale in catalog.locales)
      ExportCoverage(
        localeTag: locale.tag,
        translated: catalog.entries
            .where((entry) => locale.messages.containsKey(entry.key))
            .length,
        total: catalog.entries.length,
      ),
  ];
}
