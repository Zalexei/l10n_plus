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
    required this.dartPath,
    required this.keySpan,
    this.leafAliases = const [],
  });

  /// Dotted translation key, e.g. `auth.login.title`.
  final String path;

  /// Every generated member name from the root, e.g. `[auth, login, title]`.
  ///
  /// The whole chain, not only the leaf: reaching a message means naming each
  /// namespace on the way to it, so a namespace nobody names is a message
  /// nobody can reach.
  final List<String> dartPath;

  /// Other member names that also reach this message.
  ///
  /// A rich message generates two members: the span accessor in the base file
  /// and the `TextSpan` wrapper in the Flutter glue, and an application
  /// normally calls only one of them. Matching the accessor alone would call
  /// every rich message in a Flutter app dead, which is the one direction
  /// this scan must not err in.
  final List<String> leafAliases;

  /// The generated member name, e.g. `title`.
  String get dartName => dartPath.last;

  /// Every name that reaches this message: the member and its aliases.
  List<String> get leafNames => [dartName, ...leafAliases];

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

/// What one `unused` run found.
///
/// Two numbers, because they answer different questions: the diagnostics are
/// what a person reads, and [keyCount] is what CI counts. A namespace nobody
/// enters is one diagnostic and thirty unused messages.
final class UnusedKeyReport {
  /// Creates a report.
  const UnusedKeyReport({required this.diagnostics, required this.keyCount});

  /// One per unreachable message, or per unreachable namespace.
  final List<Diagnostic> diagnostics;

  /// How many messages those diagnostics cover in total.
  final int keyCount;

  /// Whether anything was found.
  bool get isEmpty => diagnostics.isEmpty;
}

/// Finds translations that no Dart source refers to.
///
/// The generated API is a chain of getters, and there is no way to reach
/// `t.wallet.limits.title` without the text `.wallet`, `.limits` and `.title`
/// each appearing somewhere — in one expression, or spread across locals,
/// parameters and helpers. So a message counts as used only when **every**
/// name on its path appears, and a namespace nobody names takes everything
/// under it with it.
///
/// Matching the leaf alone was the first rule here, and it does not survive
/// contact with a real application: a project that calls its messages
/// `title`, `subtitle` and `action` under forty namespaces uses each of those
/// six words somewhere within the first screen, after which every key in the
/// project is "used" and the command reports nothing, forever. Requiring the
/// whole path costs nothing in safety, because each step still has to be
/// named to be taken.
///
/// **It still over-approximates use, on purpose.** Two keys called
/// `auth.title` and `auth.subtitle` are indistinguishable once `auth` and
/// both leaf names appear. The error it refuses to make is the expensive one
/// — calling a live translation dead and having someone delete it.
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

  /// Every message of [keys] that no name in [sources] can reach.
  static UnusedKeyReport scan({
    required Iterable<TranslationKey> keys,
    required Iterable<DartSource> sources,
  }) {
    final used = referencedNames(sources);
    final scanned = sources.length;

    // Group by the shallowest name nobody writes. Every message under an
    // unreachable namespace is unreachable for the same reason and is fixed
    // by the same edit, so they are one finding, not thirty.
    final blocked = <String, List<TranslationKey>>{};
    for (final key in keys) {
      final at = _firstUnreachable(key, used);
      if (at == -1) continue;
      final segments = key.path.split('.');
      blocked.putIfAbsent(segments.take(at + 1).join('.'), () => []).add(key);
    }

    return UnusedKeyReport(
      diagnostics: [
        for (final entry in blocked.entries)
          _report(entry.key, entry.value, used: used, scanned: scanned),
      ],
      keyCount: blocked.values.fold(0, (total, keys) => total + keys.length),
    );
  }

  /// Index of the first name on [key]'s path that no source writes, or `-1`.
  ///
  /// Every name on the way to a message has to be written to reach it, so the
  /// shallowest one nobody writes is where the chain breaks. The last step is
  /// the exception: a message is reached by any of its names, since a
  /// rich message is also reachable through the wrapper the Flutter glue
  /// generates for it.
  static int _firstUnreachable(TranslationKey key, Set<String> used) {
    for (var index = 0; index < key.dartPath.length; index++) {
      final names = index == key.dartPath.length - 1
          ? key.leafNames
          : [key.dartPath[index]];
      if (!names.any(used.contains)) return index;
    }
    return -1;
  }

  static Diagnostic _report(
    String path,
    List<TranslationKey> covered, {
    required Set<String> used,
    required int scanned,
  }) {
    final first = covered.first;
    final at = _firstUnreachable(first, used);
    final name = first.dartPath[at];
    final isNamespace = at != first.dartPath.length - 1;
    return Diagnostic.warning(
      code: 'unused_key',
      message: isNamespace
          ? 'Nothing refers to anything under "$path".'
          : 'Nothing refers to "$path".',
      span: first.keySpan,
      translationKey: path,
      details:
          'No Dart file uses ".$name" ($scanned file(s) searched).\n'
          '${isNamespace ? 'Nothing reaches into "$name", so the '
                    '${covered.length} message(s) under it are unreachable:\n'
                    '  ${_list(covered)}\n' : ''}'
          'Names are matched as text, so a key is reported only when a name '
          'on its path appears nowhere at all. Delete it, or add the file '
          'that uses it to the search.',
    );
  }

  /// The covered keys, truncated: naming three hundred of them helps nobody.
  static String _list(List<TranslationKey> covered) {
    const limit = 6;
    final shown = covered.take(limit).map((key) => key.path).join('\n  ');
    if (covered.length <= limit) return shown;
    return '$shown\n  … and ${covered.length - limit} more';
  }
}
