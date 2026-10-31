import '../diagnostic.dart';
import 'bundle.dart';
import 'catalog.dart';
import 'editor.dart';

/// What an import does to one message.
enum ImportChange {
  /// The locale had no text for this key, and now has.
  added,

  /// The locale had different text for this key.
  changed,
}

/// One message an import would touch.
final class ImportedMessage {
  /// Creates a record.
  const ImportedMessage({
    required this.change,
    required this.key,
    required this.file,
    required this.after,
    this.before,
  });

  /// Whether the message is new to this locale or merely different.
  final ImportChange change;

  /// Full dotted key.
  final String key;

  /// Path of the translation file, relative to the project root.
  final String file;

  /// The text the import writes.
  final String after;

  /// The text that was there, for [ImportChange.changed].
  final String? before;
}

/// What an import does to one locale.
final class ImportedLocale {
  /// Creates a per locale plan.
  ImportedLocale({
    required this.localeTag,
    required this.messages,
    required this.unchanged,
  });

  /// The locale, as a file tag.
  final String localeTag;

  /// Every message that would change, in interchange file order.
  final List<ImportedMessage> messages;

  /// Messages whose text the file already matched.
  ///
  /// Counted and reported, because "nothing changed" and "nothing was read"
  /// look identical otherwise, and only one of them is good news.
  final int unchanged;

  /// How many messages are new to this locale.
  int get added => messages.where((m) => m.change == ImportChange.added).length;

  /// How many messages have different text.
  int get changed =>
      messages.where((m) => m.change == ImportChange.changed).length;
}

/// A translation file an import would rewrite.
final class PendingWrite {
  /// Creates a pending write.
  const PendingWrite({
    required this.path,
    required this.relativePath,
    required this.contents,
  });

  /// Absolute path on disk.
  final String path;

  /// Path relative to the project root, which is what the report prints.
  final String relativePath;

  /// The whole new contents of the file.
  final String contents;
}

/// What one `import` would do, or did.
final class ImportResult {
  /// Creates a result.
  const ImportResult({
    required this.diagnostics,
    required this.locales,
    required this.writes,
  });

  /// Everything reported along the way.
  final List<Diagnostic> diagnostics;

  /// Per locale plans, in the order the interchange file named the locales.
  final List<ImportedLocale> locales;

  /// The files to write. Empty when nothing would change.
  final List<PendingWrite> writes;

  /// Whether any error was reported.
  bool get hasErrors => diagnostics.any((d) => d.severity == Severity.error);

  /// Whether anything at all would change.
  bool get isEmpty => writes.isEmpty;
}

/// Puts translations back into the project's own files.
///
/// Nothing here writes: the plan is produced in full and the CLI decides
/// whether to apply it. That is what makes the dry run the default rather than
/// an afterthought — there is no code path that writes without having first
/// computed exactly what it would write.
abstract final class TranslationImporter {
  /// Plans [bundle] against [catalog].
  static ImportResult plan({
    required TranslationCatalog catalog,
    required InterchangeBundle bundle,
    required DiagnosticCollector diagnostics,
  }) {
    final baseKeys = {for (final entry in catalog.entries) entry.key};
    final reportedKeys = <String>{};
    final reportedLocales = <String>{};

    // Edits, and additions awaiting a neighbour, per file.
    final edits = <String, List<TextEdit>>{};
    final additions =
        <
          String,
          Map<
            String,
            (InsertionPoint, List<({List<String> segments, String value})>)
          >
        >{};
    final touched = <String, CatalogFile>{};

    final locales = <ImportedLocale>[];
    final plansByLocale = <String, List<ImportedMessage>>{};
    final unchangedByLocale = <String, int>{};
    for (final tag in bundle.localeTags) {
      plansByLocale[tag] = [];
      unchangedByLocale[tag] = 0;
    }

    for (final entry in bundle.entries) {
      // A key the base locale does not define is not a message: the base
      // locale is the generated API, so nothing could ever call it. Reported
      // once per key rather than once per locale, because one deleted key
      // would otherwise fill the report with a line per language.
      if (!baseKeys.contains(entry.key)) {
        if (reportedKeys.add(entry.key)) {
          diagnostics.add(
            Diagnostic.warning(
              code: 'unknown_interchange_key',
              message:
                  'Ignoring "${entry.key}": the base locale '
                  '"${catalog.base.tag}" does not define it.',
              span: bundle.keySpans[entry.key] ?? entry.span,
              translationKey: entry.key,
              details:
                  'The base locale decides which messages exist. Add the key '
                  'there first, or drop the row.',
            ),
          );
        }
        continue;
      }

      final locale = catalog.localeFor(entry.localeTag);
      if (locale == null) {
        // A locale the project has no files for. Creating them would mean
        // inventing a file name and a format, which is exactly the kind of
        // decision a tool should not make about someone's repository.
        if (reportedLocales.add(entry.localeTag)) {
          diagnostics.add(
            Diagnostic.warning(
              code: 'unknown_interchange_locale',
              message:
                  'Ignoring locale "${entry.localeTag}": this project has no '
                  'translation files for it.',
              span: entry.span,
              details:
                  'Add one translation file for "${entry.localeTag}" — even an '
                  'empty one with a single key — and import again.',
            ),
          );
        }
        continue;
      }

      final existing = locale.messages[entry.key];
      if (existing != null) {
        if (existing.raw == entry.text) {
          unchangedByLocale[entry.localeTag] =
              (unchangedByLocale[entry.localeTag] ?? 0) + 1;
          continue;
        }
        final file = existing.file;
        touched[file.path] = file;
        (edits[file.path] ??= []).add(
          TranslationEditor.replace(
            format: file.format,
            leaf: existing.leaf,
            value: entry.text,
          ),
        );
        (plansByLocale[entry.localeTag] ??= []).add(
          ImportedMessage(
            change: ImportChange.changed,
            key: entry.key,
            file: file.relativePath,
            before: existing.raw,
            after: entry.text,
          ),
        );
        continue;
      }

      final placement = _place(locale: locale, key: entry.key);
      if (placement == null) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'unplaceable_key',
            message:
                'Could not add "${entry.key}" to "${locale.tag}": no file of '
                'that locale says where it would go.',
            span: entry.span,
            translationKey: entry.key,
            details:
                'The layout is "${catalog.config.pathPattern}". Add the key to '
                'one of the locale\'s files by hand once, and every later '
                'import will update it in place.',
          ),
        );
        continue;
      }

      final (file, point) = placement;
      touched[file.path] = file;
      final byAnchor = additions[file.path] ??= {};
      final group = byAnchor[point.anchorPath] ??= (point, []);
      group.$2.add((segments: point.remaining, value: entry.text));
      (plansByLocale[entry.localeTag] ??= []).add(
        ImportedMessage(
          change: ImportChange.added,
          key: entry.key,
          file: file.relativePath,
          after: entry.text,
        ),
      );
    }

    for (final tag in bundle.localeTags) {
      locales.add(
        ImportedLocale(
          localeTag: tag,
          messages: plansByLocale[tag] ?? const [],
          unchanged: unchangedByLocale[tag] ?? 0,
        ),
      );
    }

    final writes = <PendingWrite>[];
    final paths = touched.keys.toList()..sort();
    for (final path in paths) {
      final file = touched[path]!;
      final all = [
        ...?edits[path],
        for (final group in (additions[path] ?? const {}).values)
          TranslationEditor.insert(
            format: file.format,
            point: group.$1,
            additions: group.$2,
          ),
      ];
      if (all.isEmpty) continue;
      writes.add(
        PendingWrite(
          path: file.path,
          relativePath: file.relativePath,
          contents: TranslationEditor.apply(file.content, all),
        ),
      );
    }

    return ImportResult(
      diagnostics: diagnostics.diagnostics,
      locales: locales,
      writes: writes,
    );
  }

  /// Which file of [locale] a new [key] goes in, and where inside it.
  ///
  /// Every file of the locale is a candidate, and the best one wins: the
  /// longest `{namespace}` the key actually starts with, then the file that
  /// already holds the most of the key's path. A project with one file per
  /// locale has one candidate and the question does not arise; a project split
  /// by namespace has exactly one file that could possibly be right.
  static (CatalogFile, InsertionPoint)? _place({
    required LocaleCatalog locale,
    required String key,
  }) {
    final segments = key.split('.');
    (CatalogFile, InsertionPoint)? best;
    var bestScore = (-1, -1);

    for (final file in locale.files) {
      final namespace = file.namespaceSegments;
      if (namespace.isNotEmpty) {
        if (namespace.length >= segments.length) continue;
        var matches = true;
        for (var index = 0; index < namespace.length; index++) {
          if (namespace[index] != segments[index]) matches = false;
        }
        if (!matches) continue;
      }
      final local = segments.sublist(namespace.length);
      final point = TranslationEditor.locate(file: file, segments: local);
      if (point == null) continue;
      // How much of the key the file already has, which is how much of the
      // structure the insertion does not have to invent.
      final existing = local.length - point.remaining.length;
      final score = (namespace.length, existing);
      if (score.$1 > bestScore.$1 ||
          (score.$1 == bestScore.$1 && score.$2 > bestScore.$2)) {
        bestScore = score;
        best = (file, point);
      }
    }
    return best;
  }
}
