import 'dart:ui' show Locale, TextDirection;

import 'package:l10n_plus/l10n_plus.dart';

/// Conversions between [L10nLocale] and Flutter's [Locale].
extension L10nLocaleFlutter on L10nLocale {
  /// This locale as a Flutter [Locale].
  Locale toFlutterLocale() => Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: country,
  );

  /// This locale's writing direction, as Flutter's [TextDirection].
  ///
  /// The translation of [L10nLocale.isRightToLeft] lives here rather than in
  /// the runtime, because [TextDirection] is `dart:ui` and the runtime has no
  /// dependencies at all. It is what a `Directionality` widget wants, so
  /// an app does not have to re-derive the direction from the language code —
  /// which is how an app ends up with its own, shorter and wronger, list.
  TextDirection get textDirection =>
      isRightToLeft ? TextDirection.rtl : TextDirection.ltr;
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
