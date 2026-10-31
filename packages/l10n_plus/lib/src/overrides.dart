import 'locale.dart';

/// Text installed at run time, replacing what the generator compiled in.
///
/// The feature this exists for is fixing a typo or rewording a sentence
/// without shipping a release. Everything that makes the generated code worth
/// having stays where it is: the plural category is still chosen by the CLDR
/// rules the generator compiled to Dart, and every argument is still formatted
/// through `package:intl` in the generated file. An override therefore supplies
/// **the text of one branch**, never a message with ICU in it — which is also
/// why this package still has no dependencies and no parser.
///
/// An override is looked up by the message's dotted key and, for a message
/// that branches, by the branch the compiled `if` chain already picked:
///
/// ```dart
/// L10nOverrides.install(const L10nLocale('en'), {
///   'auth.login.title': 'Sign in',
///   'wallet.transactions': {
///     '=0': 'Nothing here yet',
///     'one': '# transaction',
///     'other': '# transactions',
///   },
/// });
/// ```
///
/// What an override cannot do is change the API: no new key, no new or removed
/// placeholder, no new branch. Those are a release. Validate a bundle against
/// the project before shipping it:
///
/// ```sh
/// dart run l10n_plus_generator check-overrides --from=overrides_en.json --stamp
/// ```
///
/// `--stamp` writes the checked surface into the bundle as `@@fingerprint`,
/// and the generated `AppLocale.en.installOverrides(bundle)` passes this
/// build's own, so a bundle checked against another build is refused rather
/// than quietly applied to messages that have moved. See [install].
///
/// ## Why global mutable state is acceptable here
///
/// This project is wary of it, and says so: an ambient `current` accessor is
/// deferred in the roadmap over exactly this. The objection there is that a
/// widget reading an ambient value creates no dependency, so it renders
/// correctly once and then keeps the old language after a switch — silently,
/// on one screen out of forty.
///
/// That footgun does not apply to this store, because installing *notifies*:
/// [addListener] is what `L10nController.installOverrides` subscribes to, so
/// every `context.l10n` reader repaints and nothing goes silently stale. The
/// value is also the same for every reader by construction — overrides are a
/// property of the application, not of a widget subtree — so there is no
/// second copy for an ambient accessor to disagree with.
///
/// The real hazard is the ordinary one: a store installed by one test is still
/// installed in the next, and a suite that passes in order fails when a single
/// test is run alone. [clear] is the answer, in a `tearDown`:
///
/// ```dart
/// tearDown(L10nOverrides.clear);
/// ```
abstract final class L10nOverrides {
  /// Installed messages per locale.
  ///
  /// A `Map` keyed by [L10nLocale], which is a value type with `==` and
  /// `hashCode`, so `en` installed twice replaces rather than accumulates.
  static final Map<L10nLocale, Map<String, Object>> _byLocale = {};

  static final List<void Function()> _listeners = [];

  /// Replaces every override of [locale] with [messages].
  ///
  /// A key of [messages] is a dotted translation key. Its value is either:
  ///
  /// * a `String`, for a message with one form; or
  /// * a `Map<String, String>` of branch name to text, for a message the
  ///   generated code branches on — `'=0'`, a plural category such as `'one'`,
  ///   or a select case name. The branch names are the ones the generated code
  ///   consults, which `check-overrides` prints when a bundle gets one wrong.
  ///
  /// The text carries `{name}` tokens for the message's arguments and `#` for a
  /// plural count; [fill] substitutes the values the generated code has already
  /// formatted. It must not carry ICU: `{count, plural, …}` would need a parser
  /// and plural rules at run time, which is the one thing this package refuses
  /// to grow.
  ///
  /// Replaces rather than merges, so installing a bundle is the whole state for
  /// that locale and a key dropped from the bundle goes back to the compiled
  /// text. Other locales are untouched. Notifies [addListener] listeners.
  ///
  /// The outer map is copied, so the caller may keep mutating theirs. Each
  /// branch map is not: it is read on every lookup, so changing one afterwards
  /// changes what renders. A key beginning with `@` is metadata rather than a
  /// message — [fingerprintKey] and ARB's `@@locale` — and is not stored.
  ///
  /// [fingerprint] is the overridable surface this build compiled, which the
  /// generated `installOverrides` passes from a constant in the generated
  /// file. When it is given and the bundle states one of its own under
  /// [fingerprintKey], the two must be equal or nothing is installed and
  /// [L10nOverrideMismatch] is thrown: a bundle checked against a different
  /// build can silently mean something else, which is the one way an override
  /// can be wrong without being wrong in the bundle.
  ///
  /// Nothing is checked when either side is absent. A bundle that states no
  /// fingerprint is a bundle nothing checked, and refusing it here would be a
  /// second enforcement point for a rule this project enforces at build time:
  /// `check-overrides` reports a bundle with no fingerprint and `--stamp`
  /// writes one. Omitting [fingerprint] is the caller saying so — a test
  /// installing three strings has no build to speak of.
  static void install(
    L10nLocale locale,
    Map<String, Object> messages, {
    String? fingerprint,
  }) {
    final declared = messages[fingerprintKey];
    if (fingerprint != null && declared is String && declared != fingerprint) {
      throw L10nOverrideMismatch(
        locale: locale,
        declared: declared,
        expected: fingerprint,
      );
    }
    _byLocale[locale] = {
      for (final entry in messages.entries)
        if (!entry.key.startsWith('@')) entry.key: entry.value,
    };
    _notify();
  }

  /// The key a bundle states its [install] fingerprint under.
  ///
  /// `@@fingerprint`, beside ARB's `@@locale`: both say what the file is for
  /// rather than what it says, and a tool that round trips the file keeps them
  /// without being taught either one.
  static const String fingerprintKey = '@@fingerprint';

  /// Removes the overrides of [locale], or of every locale when it is omitted.
  ///
  /// Call it from a test `tearDown`: this is global state, and a store left
  /// behind by one test is the reason the next one fails. Notifies.
  static void clear([L10nLocale? locale]) {
    if (locale == null) {
      if (_byLocale.isEmpty) return;
      _byLocale.clear();
    } else if (_byLocale.remove(locale) == null) {
      return;
    }
    _notify();
  }

  /// Whether nothing is installed for any locale.
  ///
  /// The generated code does not read this — [text] has the same fast path —
  /// but a test asserting that a `tearDown` did its job does.
  static bool get isEmpty => _byLocale.isEmpty;

  /// The locales something is installed for.
  static Iterable<L10nLocale> get locales => _byLocale.keys;

  /// The override text for [key] in [locale], or `null` when there is none.
  ///
  /// [branch] names the branch the generated code has already selected, and is
  /// omitted for a message with one form. The two shapes never substitute for
  /// one another: a `String` installed for a message that branches is not
  /// spread across its branches, because that would silently drop the
  /// pluralization the message exists for. `check-overrides` reports it before
  /// the app ever runs.
  ///
  /// Called on every read of every overridable message, so the no-overrides
  /// case — the normal one — is a single `isEmpty` check on a static map.
  static String? text(L10nLocale locale, String key, [String? branch]) {
    if (_byLocale.isEmpty) return null;
    final messages = _byLocale[locale];
    if (messages == null) return null;
    final entry = messages[key];
    if (branch == null) return entry is String ? entry : null;
    if (entry is Map) {
      final value = entry[branch];
      return value is String ? value : null;
    }
    return null;
  }

  /// Substitutes [values] into the `{name}` tokens and `#` of [template].
  ///
  /// The values are already rendered: the generated code formats each argument
  /// through the same `package:intl` formatter the compiled literal uses, then
  /// hands the strings over. So `#` and `{amount}` print what the message would
  /// have printed, currency and all, and this function does no formatting of
  /// its own.
  ///
  /// A token nothing in [values] names is left exactly as it stands, rather
  /// than throwing or rendering as the empty string. A wrong override must not
  /// crash a running app — that is the whole reason `check-overrides` exists,
  /// and it catches the same mistake before the bundle ships. It also means
  /// text that merely looks like a token survives: `{literal brace}` is not an
  /// identifier, so no bundle has to learn ICU's quoting rules to write it.
  static String fill(String template, Map<String, String> values) {
    if (template.isEmpty || values.isEmpty) return template;
    final buffer = StringBuffer();
    var index = 0;
    var copiedFrom = 0;
    while (index < template.length) {
      final unit = template.codeUnitAt(index);
      if (unit == _hash) {
        final value = values['#'];
        if (value != null) {
          buffer
            ..write(template.substring(copiedFrom, index))
            ..write(value);
          copiedFrom = index + 1;
        }
        index++;
        continue;
      }
      if (unit == _openBrace) {
        final end = template.indexOf('}', index + 1);
        if (end > index) {
          final name = template.substring(index + 1, end);
          final value = _isToken(name) ? values[name] : null;
          if (value != null) {
            buffer
              ..write(template.substring(copiedFrom, index))
              ..write(value);
            copiedFrom = end + 1;
            index = end + 1;
            continue;
          }
        }
      }
      index++;
    }
    if (copiedFrom == 0) return template;
    buffer.write(template.substring(copiedFrom));
    return buffer.toString();
  }

  /// Registers [listener], called after every [install] and [clear].
  ///
  /// This is what keeps the store from being the footgun the roadmap worries
  /// about: `L10nController` subscribes, so installing a bundle repaints the
  /// screens reading it instead of leaving them on the text they were built
  /// with. A pure Dart application that renders once per request needs none of
  /// it and can ignore this.
  static void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a [listener] added by [addListener].
  static void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  /// Notifies over a copy, so a listener may remove itself while being called.
  static void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  static const int _hash = 0x23;
  static const int _openBrace = 0x7b;

  /// Whether `{name}` is a token [fill] would substitute.
  ///
  /// An argument name, or `#0` for a nested choice. Anything else — a space, a
  /// comma, punctuation — is text that happens to sit in braces, and is left
  /// alone, so no bundle has to learn ICU's quoting rules to write a brace.
  ///
  /// Public because the generator's `check-overrides` asks the same question
  /// at build time, and the two answers have to be the same one: a name the
  /// check validates and this does not substitute would ship as `{name}` on a
  /// screen.
  static bool isToken(String name) => _isToken(name);

  static bool _isToken(String name) {
    if (name.isEmpty) return false;
    final first = name.codeUnitAt(0);
    if (first == _hash) {
      if (name.length == 1) return false;
      for (var i = 1; i < name.length; i++) {
        final unit = name.codeUnitAt(i);
        if (unit < 0x30 || unit > 0x39) return false;
      }
      return true;
    }
    for (var i = 0; i < name.length; i++) {
      final unit = name.codeUnitAt(i);
      final isLetter =
          (unit >= 0x61 && unit <= 0x7a) || (unit >= 0x41 && unit <= 0x5a);
      final isDigit = unit >= 0x30 && unit <= 0x39;
      if (isLetter || unit == 0x5f) continue;
      if (isDigit && i > 0) continue;
      return false;
    }
    return true;
  }
}

/// Thrown by [L10nOverrides.install] for a bundle built against another build.
///
/// The bundle is not stale in the sense of being old text: it is text written
/// for a different set of messages. `check-overrides` validated it against the
/// placeholders, branches and nested choice numbers of the build it was
/// checked against, and those are positional — insert a plural into a message
/// and the `0/one` of yesterday's bundle addresses a different choice today.
/// Nothing in the text says so, which is why the build says so instead.
///
/// Nothing is installed when this is thrown, so the application keeps
/// rendering what it compiled — the correct text for the build that is
/// running. Catch it where the bundle is fetched, report it, and ship a bundle
/// re-checked against this build:
///
/// ```sh
/// dart run l10n_plus_generator check-overrides --from=overrides_ru.json --stamp
/// ```
final class L10nOverrideMismatch implements Exception {
  /// Creates a mismatch.
  const L10nOverrideMismatch({
    required this.locale,
    required this.declared,
    required this.expected,
  });

  /// The locale the bundle was being installed for.
  final L10nLocale locale;

  /// The fingerprint the bundle states.
  final String declared;

  /// The fingerprint this build compiled for [locale].
  final String expected;

  @override
  String toString() =>
      'L10nOverrideMismatch: the ${locale.toLanguageTag()} override bundle '
      'was checked against the overridable surface $declared, and this build '
      'compiled $expected. Nothing was installed.';
}
