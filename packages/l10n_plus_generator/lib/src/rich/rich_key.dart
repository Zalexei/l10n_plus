/// The key suffix that opts a message into rich text.
///
/// A message is rich because its *key* says so — `"terms(rich)"` — and never
/// because of what its value contains. That is the whole reason the suffix
/// exists: a project with `"tip": "Use <Ctrl> to select"` has been shipping
/// that string for years, and a library that started reading tags out of
/// every message would silently eat it. Opting in one key at a time keeps
/// every other message exactly as it was.
///
/// The suffix is part of the key, not a decoration on it. So it is written in
/// every locale's file, and the existing cross locale key check is what says
/// so: a Russian bundle spelling the key `terms` while English spells it
/// `terms(rich)` is a missing key and an extra key, reported by name. That is
/// also why richness cannot disagree between locales — it is not a property
/// one locale could declare differently, it is the key.
///
/// The spelling is `slang`'s, deliberately. A team arriving from the main
/// competitor should be able to paste its translation files in.
abstract final class RichKey {
  /// The suffix, including the parentheses.
  static const String suffix = '(rich)';

  /// Whether [key] opts into rich text.
  static bool isRich(String key) => key.endsWith(suffix);

  /// [key] without the suffix, which is what becomes the Dart identifier.
  static String baseName(String key) =>
      isRich(key) ? key.substring(0, key.length - suffix.length) : key;
}
