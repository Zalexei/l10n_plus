import 'dart:ui' show Locale;

import 'package:l10n_plus/l10n_plus.dart';

/// Conversions between [L10nLocale] and Flutter's [Locale].
extension L10nLocaleFlutter on L10nLocale {
  /// This locale as a Flutter [Locale].
  Locale toFlutterLocale() => Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: country,
  );
}

/// Conversions from Flutter's [Locale] to [L10nLocale].
extension FlutterLocaleL10n on Locale {
  /// This locale as an [L10nLocale].
  L10nLocale toL10nLocale() => L10nLocale(
    languageCode.toLowerCase(),
    script: scriptCode,
    country: countryCode?.toUpperCase(),
  );
}
