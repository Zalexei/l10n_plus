import 'package:l10n_plus/l10n_plus.dart';

/// Where the locale sits in a translation file's path.
///
/// A file name has to answer two questions: which locale is this, and — once a
/// locale may be spread over several files — which part of the name is not the
/// locale. A bare base name cannot: `app_en` is itself a valid locale tag, so
/// guessing which half is a prefix picks the wrong locale in silence.
///
/// The pattern says it instead. `{locale}` marks the locale, and the rest of
/// the name is one of two things:
///
/// * `{namespace}` — the captured text becomes a namespace the file's keys go
///   under, so `auth_en.json` holding `{"login": {...}}` generates
///   `t.auth.login`. Dots nest: `wallet.settings_en.json` gives
///   `t.wallet.settings`.
/// * `*` and `**` — matched and thrown away. The file writes its keys in full
///   and they merge. `**` crosses directories, `*` does not.
///
/// Both exist because the formats want different things. A hand written JSON
/// or YAML file should not have to repeat `auth` inside `auth_en.json`, while
/// an ARB bundle exported from a TMS already has `auth.login.title` in it and
/// prefixing would produce `auth.auth.login.title`.
///
/// ```
/// {locale}              en.json, pt_BR.json
/// app_{locale}          app_en.arb
/// {namespace}_{locale}  auth_en.json     → t.auth.*
/// {namespace}/{locale}  wallet/en.json   → t.wallet.*
/// {locale}/{namespace}  en/wallet.json   → t.wallet.*
/// *_{locale}            auth_en.arb      → merged, keys written in full
/// **/{locale}           wallet/settings/en.json
/// ```
final class FilePattern {
  const FilePattern._(this.source, this._regExp);

  /// The pattern as written, for diagnostics.
  final String source;

  final RegExp _regExp;

  /// The pattern used when a project does not configure one.
  static final FilePattern fallback = parse(defaultSource)!;

  /// What [fallback] is written as.
  static const String defaultSource = '{locale}';

  /// The placeholder every pattern must contain exactly once.
  static const String localePlaceholder = '{locale}';

  /// The optional placeholder naming where the file's keys go.
  static const String namespacePlaceholder = '{namespace}';

  /// Compiles [source], or returns `null` when it is not usable.
  ///
  /// [problem] receives a one line reason, so the caller can build a
  /// diagnostic with its own span.
  static FilePattern? parse(String source, {void Function(String)? problem}) {
    if (localePlaceholder.allMatches(source).length != 1) {
      problem?.call(
        source.contains(localePlaceholder)
            ? 'A pattern may contain "{locale}" only once.'
            : 'A pattern must contain "{locale}".',
      );
      return null;
    }

    if (namespacePlaceholder.allMatches(source).length > 1) {
      problem?.call('A pattern may contain "{namespace}" only once.');
      return null;
    }

    final unknown = RegExp(r'\{([^}]*)\}')
        .allMatches(source)
        .map((match) => match.group(0)!)
        .where(
          (placeholder) =>
              placeholder != localePlaceholder &&
              placeholder != namespacePlaceholder,
        )
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      problem?.call(
        'Unknown placeholder ${unknown.first}. The placeholders are '
        '"{locale}" and "{namespace}"; use "*" or "**" to match and discard.',
      );
      return null;
    }

    if (source.startsWith('/') || source.contains('..')) {
      problem?.call('A pattern is relative to the input directory.');
      return null;
    }

    final buffer = StringBuffer('^');
    for (var index = 0; index < source.length; index++) {
      if (source.startsWith(localePlaceholder, index)) {
        // Locale tags are letters, digits, `_` and `-`; `L10nLocale` decides
        // whether the capture is really one.
        buffer.write(r'(?<locale>[A-Za-z0-9_-]+)');
        index += localePlaceholder.length - 1;
        continue;
      }
      if (source.startsWith(namespacePlaceholder, index)) {
        buffer.write(r'(?<namespace>[^/]+)');
        index += namespacePlaceholder.length - 1;
        continue;
      }
      if (source.startsWith('**', index)) {
        buffer.write('.*');
        index++;
        continue;
      }
      final character = source[index];
      buffer.write(character == '*' ? '[^/]*' : RegExp.escape(character));
    }
    buffer.write(r'$');

    return FilePattern._(source, RegExp(buffer.toString()));
  }

  /// What [relativePath] says, or `null` when it does not match.
  ///
  /// [relativePath] is relative to the input directory, uses `/` separators,
  /// and has its extension removed.
  FileMatch? match(String relativePath) {
    final match = _regExp.firstMatch(relativePath);
    if (match == null) return null;
    final locale = L10nLocale.tryParse(match.namedGroup('locale')!);
    if (locale == null) return null;
    return FileMatch(
      locale: locale,
      namespace: _hasNamespace ? match.namedGroup('namespace') : null,
    );
  }

  bool get _hasNamespace => source.contains(namespacePlaceholder);

  @override
  String toString() => source;
}

/// What a [FilePattern] read out of one file's path.
final class FileMatch {
  /// Creates a match.
  const FileMatch({required this.locale, this.namespace});

  /// The locale the file provides.
  final L10nLocale locale;

  /// Dotted key path the file's translations go under, or `null` when the
  /// pattern has no `{namespace}` and the file writes its keys in full.
  final String? namespace;

  /// [namespace] split into the groups it nests through.
  List<String> get namespaceSegments =>
      namespace == null ? const [] : namespace!.split('.');
}
