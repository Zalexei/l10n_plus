/// A locale identifier: language, optional script, optional region.
///
/// This is deliberately a tiny value type instead of `dart:ui`'s `Locale`, so
/// that the runtime stays usable from pure Dart (servers, CLIs, unit tests).
final class L10nLocale {
  /// Creates a locale from already-canonical parts.
  ///
  /// [language] must be lowercase, [script] title case and [country] uppercase.
  /// Use [L10nLocale.parse] for untrusted input.
  const L10nLocale(this.language, {this.script, this.country});

  /// Lowercase ISO-639 language code, e.g. `en`, `ru`, `pt`.
  final String language;

  /// Title case ISO-15924 script code, e.g. `Hant`. Usually `null`.
  final String? script;

  /// Uppercase ISO-3166 region code, e.g. `BR`. `null` for language-only.
  final String? country;

  /// Parses `en`, `en_US`, `en-US`, `zh-Hant-TW` into a canonical locale.
  ///
  /// The language subtag must be two or three letters, as in ISO-639. Longer
  /// registered subtags are not accepted, so that ordinary words such as
  /// `readme` are not mistaken for locales.
  ///
  /// Returns `null` when [tag] is not a recognizable locale identifier.
  static L10nLocale? tryParse(String tag) {
    final parts = tag
        .split(RegExp('[_-]'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.length > 3) return null;

    final language = parts.first.toLowerCase();
    if (language.length < 2 || language.length > 3) return null;
    if (!_isAlpha(language)) return null;

    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && _isAlpha(part) && script == null) {
        script = part[0].toUpperCase() + part.substring(1).toLowerCase();
      } else if ((part.length == 2 && _isAlpha(part)) ||
          (part.length == 3 && _isDigits(part))) {
        if (country != null) return null;
        country = part.toUpperCase();
      } else {
        return null;
      }
    }
    return L10nLocale(language, script: script, country: country);
  }

  /// Like [tryParse] but throws [FormatException] on invalid input.
  static L10nLocale parse(String tag) {
    final locale = tryParse(tag);
    if (locale == null) {
      throw FormatException('Not a valid locale identifier', tag);
    }
    return locale;
  }

  /// BCP-47 style tag, e.g. `pt-BR`.
  String toLanguageTag() => _join('-');

  /// Underscore separated tag, e.g. `pt_BR`. Used for file names.
  String toFileTag() => _join('_');

  /// Progressively less specific locales, most specific first.
  ///
  /// `zh_Hant_TW` yields `zh_Hant_TW`, `zh_Hant`, `zh`.
  List<L10nLocale> get lineage {
    return [
      this,
      if (script != null && country != null)
        L10nLocale(language, script: script),
      if (script != null || country != null) L10nLocale(language),
    ];
  }

  String _join(String separator) {
    final buffer = StringBuffer(language);
    if (script != null) {
      buffer
        ..write(separator)
        ..write(script);
    }
    if (country != null) {
      buffer
        ..write(separator)
        ..write(country);
    }
    return buffer.toString();
  }

  static bool _isAlpha(String value) => RegExp(r'^[A-Za-z]+$').hasMatch(value);

  static bool _isDigits(String value) => RegExp(r'^[0-9]+$').hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is L10nLocale &&
      other.language == language &&
      other.script == script &&
      other.country == country;

  @override
  int get hashCode => Object.hash(language, script, country);

  @override
  String toString() => toLanguageTag();
}
