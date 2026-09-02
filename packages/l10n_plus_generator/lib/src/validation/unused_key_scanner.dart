import 'package:source_span/source_span.dart';

import '../diagnostic.dart';

/// One message of the base locale, as a tool sees it.
///
/// Enough to say what was generated and where it came from, without exposing
/// the whole model.
final class TranslationKey {
  /// Creates a key reference.
  const TranslationKey({
    required this.path,
    required this.dartName,
    required this.keySpan,
  });

  /// Dotted translation key, e.g. `auth.login.title`.
  final String path;

  /// The generated member name, e.g. `title`.
  final String dartName;

  /// Where the key is in the base locale file.
  final SourceSpan keySpan;
}

/// One Dart file to search for uses of the generated API.
final class DartSource {
  /// Creates a source file.
  const DartSource({required this.path, required this.content});

  /// Path, used only in diagnostics.
  final String path;

  /// The file's text.
  final String content;
}

/// Finds translations that no Dart source refers to.
///
/// The generated API is a chain of getters, so a message is used exactly when
/// its member name appears after a dot somewhere. That is what this looks for:
/// every `.name` and `..name` in every source, as text.
///
/// **It over-approximates use, on purpose.** Two keys ending in `title` are
/// indistinguishable to it, so if one is used both count as used. The error it
/// refuses to make is the expensive one — calling a live translation dead and
/// having someone delete it. Everything it does report is a key whose name
/// appears nowhere in the scanned code.
///
/// The alternative is resolving the project with `package:analyzer`, which
/// would be exact. It would also make a dev dependency of every consumer out
/// of the heaviest package in the ecosystem, to answer a question that is
/// advisory by nature. A text scan that errs toward "used" is the right size
/// for the job, and the limitation is written down rather than hidden.
abstract final class UnusedKeyScanner {
  /// Member names referenced anywhere in [sources].
  static Set<String> referencedNames(Iterable<DartSource> sources) {
    final names = <String>{};
    for (final source in sources) {
      for (final match in _memberAccess.allMatches(source.content)) {
        names.add(match.group(1)!);
      }
    }
    return names;
  }

  /// `.name`, `?.name` and the `..name` of a cascade.
  ///
  /// Comments and string literals are searched too. That is deliberate: a
  /// match there is a false "used", which is the harmless direction.
  static final RegExp _memberAccess = RegExp(
    r'\.\.?\s*([a-zA-Z_$][a-zA-Z0-9_$]*)',
  );

  /// Diagnostics for every key of [keys] whose name is used nowhere.
  static List<Diagnostic> scan({
    required Iterable<TranslationKey> keys,
    required Iterable<DartSource> sources,
  }) {
    final used = referencedNames(sources);
    final scanned = sources.length;
    return [
      for (final key in keys)
        if (!used.contains(key.dartName))
          Diagnostic.warning(
            code: 'unused_key',
            message: 'Nothing refers to "${key.path}".',
            span: key.keySpan,
            translationKey: key.path,
            details:
                'No Dart file uses ".${key.dartName}" '
                '($scanned file(s) searched).\n'
                'Names are matched as text, so a key is only reported when '
                'its member name appears nowhere at all. Delete the key, or '
                'add the file that uses it to the search.',
          ),
    ];
  }
}
