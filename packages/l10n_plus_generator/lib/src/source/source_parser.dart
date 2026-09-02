import 'package:l10n_plus/l10n_plus.dart';

import '../ast/translation_tree.dart';
import '../diagnostic.dart';

/// Turns one translation file into a [TranslationDocument].
///
/// This is the only seam formats plug into. Everything after this stage is
/// format agnostic, so ARB and YAML support means adding an implementation
/// here and nothing else.
abstract interface class TranslationSourceParser {
  /// File extensions this parser claims, without the leading dot.
  Set<String> get extensions;

  /// Whether the format can name its own locale, as ARB does with `@@locale`.
  ///
  /// When it cannot, the path is the only source of the locale, so a file
  /// whose path does not match the configured pattern is skipped before this
  /// parser is asked to read it.
  bool get declaresLocale;

  /// Parses [content] into a document, reporting problems to [diagnostics].
  ///
  /// [localeHint] is the locale derived from the file name, or `null` when the
  /// name is not a locale tag. A format that declares its own locale, as ARB
  /// does with `@@locale`, may ignore the hint; a format that cannot must
  /// report a diagnostic and return `null` when the hint is missing.
  TranslationDocument? parse({
    required String content,
    required Uri uri,
    required L10nLocale? localeHint,
    required DiagnosticCollector diagnostics,
  });
}
