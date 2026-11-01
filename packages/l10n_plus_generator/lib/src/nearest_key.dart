/// Offers the key a misspelling was most likely meant to be.
///
/// One implementation rather than three. The configuration parser, the
/// override checker and the link resolver all answer the same question about
/// different sets of keys, and they had answered it with two copies of the
/// same Levenshtein routine between them.
abstract final class NearestKey {
  /// The key [written] is most likely a typo of, or `null`.
  ///
  /// Only a genuinely near miss counts: a third of the length, at most three
  /// edits. `file_per_local` gets an answer, `translations` does not — and a
  /// wrong guess is worse than the list of every candidate that follows it,
  /// which is what every caller prints instead.
  static String? of(String written, Iterable<String> known) {
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in known) {
      final distance = editDistance(written, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    final budget = (written.length / 3).floor().clamp(1, 3);
    return bestDistance <= budget ? best : null;
  }

  /// Levenshtein distance, two rows at a time.
  static int editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = substitution < deletion
            ? (substitution < insertion ? substitution : insertion)
            : (deletion < insertion ? deletion : insertion);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}
