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
  /// Resolution is three steps, in order:
  ///
  /// 1. the requested locale's [L10nLocale.lineage], most specific first, so
  ///    `pt_BR` prefers `pt_BR` and then `pt`;
  /// 2. **the first supported locale sharing its language**, in the order
  ///    [supported] is given — which for generated code is the locale enum,
  ///    which is sorted by tag. So `en_NZ` against `en_AU, en_GB` resolves to
  ///    `en_AU`, because `AU` sorts before `GB` and for no other reason;
  /// 3. [fallback].
  ///
  /// Step 2 is a deliberate simplification. Real regional affinity — that a
  /// New Zealander wants `en_GB` spelling — is a table CLDR publishes and
  /// this library does not carry, and guessing it in code would be wrong in
  /// ways nobody could predict from the source. Picking the first match is
  /// arbitrary but stable, and a project that cares states the preference by
  /// adding the region it wants, or a plain `en`, to its translations.
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
    // Same language, different region: the first one offered wins. See the
    // ordering note on this method — it is arbitrary, stable, and documented
    // rather than dressed up as a preference.
    for (final locale in supported) {
      if (locale.l10nLocale.language == requested.language) return locale;
    }
    return fallback;
  }
}
