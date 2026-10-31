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

  /// Whether this locale's text runs right to left.
  ///
  /// Decided by the script the locale is written in, never by the region:
  /// `ar`, `ar_EG` and `fa_IR` are all right to left, while the two
  /// Azerbaijani locales disagree with each other — `az_Latn` runs left to
  /// right and `az_Arab` does not. An explicit [script] subtag therefore
  /// always wins; without one, the language's default script decides.
  ///
  /// Both lists behind this come from one source, Unicode CLDR 46. A script
  /// is right to left when `common/properties/scriptMetadata.txt` marks it
  /// `rtl = YES`; a language is right to left when
  /// `common/supplemental/likelySubtags.xml` maps it to such a script.
  ///
  /// What this deliberately does not try to answer:
  ///
  /// * How a particular *string* should be laid out. A right-to-left
  ///   paragraph normally contains left-to-right runs — a Latin brand name, a
  ///   URL, a phone number — and separating them is the Unicode
  ///   bidirectional algorithm's job, which needs the text and not the
  ///   locale. Isolating an interpolated value so that it cannot reorder the
  ///   sentence around it is that separate problem, and this does not solve
  ///   it.
  /// * Anything else about the locale. Direction is one layout fact, not a
  ///   summary: two locales of the same direction still differ in digits,
  ///   calendar and collation.
  ///
  /// A predicate rather than an enum, because the answer has exactly two
  /// values and both are stable — a `bool` carries all of it without adding a
  /// second type to the runtime's public surface.
  bool get isRightToLeft {
    final scriptCode = script;
    // A script subtag is the locale stating which script it is written in, so
    // it is taken at its word even when the language usually uses another.
    if (scriptCode != null) return _rightToLeftScripts.contains(scriptCode);
    return _rightToLeftLanguages.contains(language);
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

  /// Scripts CLDR marks as right to left.
  ///
  /// Every script with `rtl = YES` in CLDR 46's
  /// `common/properties/scriptMetadata.txt`, the historical ones included:
  /// they cost two words each, and a locale that carries `Phnx` or `Samr` as
  /// its script subtag means it.
  static const Set<String> _rightToLeftScripts = {
    'Adlm', 'Arab', 'Aran', 'Armi', 'Avst', 'Chrs', 'Cprt', 'Elym', //
    'Gara', 'Hatr', 'Hebr', 'Hung', 'Khar', 'Lydi', 'Mand', 'Mani', //
    'Mend', 'Merc', 'Mero', 'Narb', 'Nbat', 'Nkoo', 'Orkh', 'Ougr', //
    'Palm', 'Phli', 'Phlp', 'Phnx', 'Prti', 'Rohg', 'Samr', 'Sarb', //
    'Sogd', 'Sogo', 'Syrc', 'Syre', 'Syrj', 'Syrn', 'Thaa', 'Todr', //
    'Yezi',
  };

  /// Languages whose default script is one of [_rightToLeftScripts].
  ///
  /// Grouped by that script, so that a future entry can be checked against
  /// the same CLDR files rather than against intuition — which is unreliable
  /// here. `ku`, Kurmanji Kurdish, is written in Latin and is absent on
  /// purpose; Central Kurdish, `ckb`, is written in Arabic and is present.
  ///
  /// It covers the languages CLDR gives a subtag of their own. A language
  /// whose default script this misses is still answered correctly when the
  /// locale spells the script out, as `pa_Arab` and `kk_Arab` do.
  static const Set<String> _rightToLeftLanguages = {
    // Arabic script: the Arabic dialects CLDR separates out, plus the
    // Iranian, Turkic and Indo-Aryan languages written in the same script.
    'aeb', 'apc', 'ar', 'arq', 'ars', 'ary', 'arz', 'azb', 'bal', //
    'bgn', 'bqi', 'brh', 'cja', 'ckb', 'fa', 'gbz', 'glk', 'haz', //
    'khw', 'ks', 'lki', 'lrc', 'luz', 'mzn', 'pnb', 'prd', 'ps', //
    'sd', 'sdh', 'skr', 'ug', 'ur',
    // Hebrew script. `iw` and `ji` are the retired codes for `he` and `yi`;
    // they still turn up in older bundles and in file names.
    'he', 'iw', 'ji', 'jpr', 'jrb', 'yi',
    // Thaana, Syriac, N'Ko, Hanifi Rohingya, Mandaic, Samaritan.
    'dv', 'aii', 'syr', 'nqo', 'rhg', 'mid', 'sam',
  };

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
