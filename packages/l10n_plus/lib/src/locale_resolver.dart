import 'locale.dart';
import 'translations.dart';

/// Picks the best supported locale for a requested one.
///
/// Resolution walks the requested locale's [L10nLocale.lineage] (most specific
/// first), then any supported locale sharing its language, then the fallback.
/// The fallback is a chain, not a single value, so `pt_BR -> pt -> en` works.
final class L10nLocaleResolver {
  const L10nLocaleResolver._();

  /// Returns the entry of [supported] that best matches [requested].
  ///
  /// Falls back to [fallback] and finally to the first supported locale.
  static L resolve<L extends AppLocaleBase>({
    required L10nLocale? requested,
    required List<L> supported,
    required L fallback,
  }) {
    if (supported.isEmpty) {
      throw ArgumentError.value(supported, 'supported', 'must not be empty');
    }
    if (requested == null) return fallback;

    for (final candidate in requested.lineage) {
      for (final locale in supported) {
        if (locale.l10nLocale == candidate) return locale;
      }
    }
    // Same language, different region: `en_AU` -> `en_GB` if `en` is absent.
    for (final locale in supported) {
      if (locale.l10nLocale.language == requested.language) return locale;
    }
    return fallback;
  }
}
