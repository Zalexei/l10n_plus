import 'translations.dart';

/// The locale that `AppLocalizations.current` reads, generated with
/// `global_translations: true`.
///
/// A cell rather than a static on the generated class, so that the Flutter
/// controller — which is generic and has never heard of `AppLocalizations` —
/// can be handed one and write it. The controller is then the one source of
/// truth: `current` and `context.l10n` cannot disagree, because the first is
/// written by the thing the second reads.
///
/// It holds a locale rather than translations. The translations of a deferred
/// locale that has not loaded yet are the fallback's, and an object captured at
/// that moment would keep reading as the fallback after the chunk arrived.
///
/// ## One owner at a time
///
/// A controller installs with itself as `owner` and releases on dispose. A
/// second live owner is a mistake with no other symptom than "current shows
/// the wrong language" — two controllers in a test suite that forgot a
/// `dispose`, usually — so it fails an assert in debug builds. Installing
/// with no owner, which is what the generated `setCurrentLocale` does for pure
/// Dart and tests, is always allowed.
final class L10nCurrent<L extends AppLocaleBase> {
  /// Creates an empty cell.
  L10nCurrent();

  L? _locale;
  Object? _owner;

  /// The installed locale, or `null` when nothing is installed.
  L? get locale => _locale;

  /// Installs [locale], on behalf of [owner] when given.
  void install(L locale, {Object? owner}) {
    assert(
      owner == null || _owner == null || identical(_owner, owner),
      'Two owners for one L10nCurrent: a second controller was created while '
      'the first is alive, so AppLocalizations.current would follow whichever '
      'changed last. Dispose the first controller, or call resetCurrent() '
      'between tests.',
    );
    _owner = owner;
    _locale = locale;
  }

  /// Empties the cell if [owner] is the one that installed it.
  ///
  /// A no-op otherwise, so a controller disposed after someone else took the
  /// cell over does not clear what they installed.
  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    reset();
  }

  /// Empties the cell, whoever installed it.
  void reset() {
    _owner = null;
    _locale = null;
  }
}
