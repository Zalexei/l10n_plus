import 'dart:convert';

import 'override_schema.dart';

/// Identifies the overridable surface of one locale in one build.
///
/// An override bundle is validated against a build: `check-overrides` reads
/// the lookups the emitter wrote and answers every question about the bundle
/// from them. The answers stop being true the moment the build changes, and
/// one way they stop being true is silent.
///
/// A nested choice is numbered by position — `0/one` is the `one` branch of a
/// message's first nested choice, and `{#0}` is that choice's rendering in the
/// text around it. Insert a plural ahead of it and the numbers shift: every
/// name in yesterday's bundle still exists, so every check still passes, and
/// the text of one choice is now the text of another. Nothing in the bundle
/// can say which build it meant, so the build says it instead.
///
/// The fingerprint is that statement: a bundle carries the surface it was
/// checked against, the generated code carries the surface it compiled, and
/// `L10nOverrides.install` refuses a bundle whose surface is not this one.
///
/// ## What it covers, and what it deliberately does not
///
/// Only what can make an existing bundle entry *mean something else*: the
/// keys, each message's slots, the tokens each slot substitutes, and what each
/// choice selects on. Not the compiled text — a reword is the release an
/// override exists to avoid waiting for, and invalidating every bundle over
/// one would defeat the feature. Not the plural categories CLDR gives the
/// language either, though `check-overrides` consults them: a CLDR upgrade
/// that leaves the emitted branches alone leaves every bundle correct, and
/// refusing them would be a false alarm whose cost is the application quietly
/// reverting to its compiled text.
///
/// Nothing in it depends on order. Messages are sorted by key and slots by
/// branch name, so moving a message or reordering a plural's branches does not
/// invalidate a bundle. The one order that *is* captured is the numbering of
/// nested choices, which lives inside the branch names and the `#n` tokens —
/// which is the case this exists for.
///
/// It is coarse on purpose: one value per locale, so adding a message
/// invalidates the bundles of that locale even though their entries are all
/// still valid. Per-message fingerprints would be exact and would put a hash
/// beside every string in a file a translator's tooling has to carry. The
/// coarse version costs one `--stamp` in the release that changed the surface,
/// and that release had to re-check its bundles anyway.
///
/// ## It identifies, it does not authenticate
///
/// FNV-1a over a canonical rendering, 64 bits, printed as 16 hex digits. The
/// threat it answers is drift between a bundle and a build, not forgery:
/// anybody who can replace the bundle your application downloads can replace
/// the fingerprint inside it, and the integrity of that download is TLS's job.
/// A cryptographic digest truncated to the same 16 digits would say exactly as
/// much, and cost this package a dependency.
abstract final class OverrideFingerprint {
  /// Prefix of the canonical rendering, bumped when that rendering changes.
  ///
  /// Here so a future change to what the fingerprint covers is a deliberate
  /// invalidation of every bundle rather than an accidental one.
  static const String version = 'l10n_plus/1';

  /// The fingerprint of [schema], as 16 lowercase hex digits.
  static String of(OverrideSchema schema) => _hash(canonical(schema));

  /// The exact bytes [of] hashes.
  ///
  /// Public because a test that asserts two surfaces differ should be able to
  /// say *how*, and because a hash nobody can print is a hash nobody can
  /// debug.
  static String canonical(OverrideSchema schema) {
    final buffer = StringBuffer()
      ..writeln(version)
      ..writeln(schema.localeTag);

    // The locale tag is in there so a bundle cannot be installed for a locale
    // it was not checked against even when two locales happen to have the
    // same messages — `en` and `en_GB` usually do.
    final keys = schema.messages.keys.toList(growable: false)..sort();
    for (final key in keys) {
      final message = schema.messages[key]!;
      // A rich message cannot be overridden at all, so it is not part of the
      // surface: adding one leaves every bundle valid, and a plain message
      // that becomes rich loses its slots, which shows up here as the key
      // losing them.
      if (message.isRich) continue;
      buffer.writeln('K$key');

      final prefixes = message.choices.keys.toList(growable: false)..sort();
      for (final prefix in prefixes) {
        buffer.writeln('C$prefix|${message.choices[prefix]}');
      }

      final slots = message.slots.toList(growable: false)
        ..sort((a, b) => (a.branch ?? '').compareTo(b.branch ?? ''));
      for (final slot in slots) {
        final tokens = slot.tokens.toList(growable: false)..sort();
        buffer.writeln('B${slot.branch ?? ''}|${tokens.join(',')}');
      }
    }
    return buffer.toString();
  }

  /// FNV-1a 64, as 16 lowercase hex digits.
  ///
  /// Dart's `int` is a wrapping 64 bit integer on every target this generator
  /// runs on — it is a command line tool, never compiled to JavaScript, where
  /// `int` is a double and this would silently lose the high bits.
  ///
  /// Printed as two unsigned halves, because the value is a bit pattern and
  /// `int` is signed: `toRadixString` on the whole of it writes a minus sign
  /// for every hash whose top bit is set, which is half of them.
  static String _hash(String canonical) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(canonical)) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    return _hex(hash >> 32) + _hex(hash);
  }

  /// The low 32 bits of [word] as 8 lowercase hex digits.
  static String _hex(int word) =>
      (word & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
