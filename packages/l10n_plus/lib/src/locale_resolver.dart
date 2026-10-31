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
  ///    `pt_BR` prefers `pt_BR`, then `pt`. The lineage always ends at the
  ///    bare language, so **a supported locale with no region always beats a
  ///    region-carrying sibling**: `en_NZ` against `en_AU, en_GB, en` resolves
  ///    to `en`, whatever order those three are listed in;
  /// 2. failing that, a region-carrying sibling of the same language, chosen
  ///    by [_compareSiblings] — a total order over the locales themselves, so
  ///    the answer never depends on the order of [supported] (and therefore
  ///    never on how the translation files happen to be named);
  /// 3. [fallback].
  ///
  /// Step 2 claims no regional affinity. Real affinity — that a New Zealander
  /// wants `en_GB` spelling — is a table CLDR publishes and this library does
  /// not carry, and guessing it in code would be wrong in ways nobody could
  /// predict from the source. So the tie-break is alphabetical by the locale's
  /// own tag: `en_NZ` against `en_AU, en_GB` resolves to `en_AU` because
  /// `en-AU` sorts first, and for no other reason. The difference from
  /// sorting by accident is that this holds for every caller, is stated here,
  /// and is covered by a test. A project that cares states the preference
  /// rather than hoping: add the region it wants, or a plain `en`, and step 1
  /// finds it.
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
    // Same language, different region. Scan for the minimum under a total
    // order on the locales, not for the first one offered, so reordering
    // `supported` cannot change the answer.
    L? best;
    for (final locale in supported) {
      if (locale.l10nLocale.language != requested.language) continue;
      if (best == null ||
          _compareSiblings(locale.l10nLocale, best.l10nLocale, requested) < 0) {
        best = locale;
      }
    }
    return best ?? fallback;
  }

  /// Orders two same-language siblings by how well each suits [requested].
  ///
  /// Negative when [a] is the better match. The order is total over distinct
  /// locales — distinct locales have distinct tags — so the minimum is unique
  /// and independent of iteration order.
  static int _compareSiblings(
    L10nLocale a,
    L10nLocale b,
    L10nLocale requested,
  ) {
    final byScript = _scriptRank(
      a,
      requested,
    ).compareTo(_scriptRank(b, requested));
    if (byScript != 0) return byScript;
    // Arbitrary, but a rule rather than an accident: see [resolve].
    return a.toLanguageTag().compareTo(b.toLanguageTag());
  }

  /// How a candidate's script relates to the requested one. Lower is better.
  ///
  /// Script is the one piece of real information available without CLDR's
  /// affinity table: `zh_Hant_HK` is readable as `zh_Hant_TW` and not as
  /// `zh_Hans_CN`, and that is orthography, not guesswork. An unmarked script
  /// ranks between the two because it conflicts with nothing.
  static int _scriptRank(L10nLocale candidate, L10nLocale requested) {
    if (candidate.script == requested.script) return 0;
    if (candidate.script == null) return 1;
    return 2;
  }
}
