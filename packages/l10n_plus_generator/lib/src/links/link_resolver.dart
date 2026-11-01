import '../diagnostic.dart';
import '../model/argument.dart';
import '../nearest_key.dart';

/// What one locale's links contribute to its signatures, once checked.
final class LinkResolution {
  /// Creates a resolution.
  const LinkResolution(this.arguments);

  /// Extra arguments per message path, contributed by what it links to.
  ///
  /// Transitive: a message that links to a message that links to a plural
  /// takes the plural's count, because at run time it is the one that has to
  /// supply it.
  final Map<String, List<ArgumentSpec>> arguments;
}

/// Checks `@:other.key` links and works out what they add to a signature.
///
/// A link is the one construct in a message whose correctness is a property of
/// the *project* rather than of the string: the target has to exist, it has to
/// be text rather than spans, the path must not lead back here, and whatever
/// parameters the target needs become parameters of the message that links to
/// it. None of that can be decided while parsing one string, and all of it can
/// be decided before anything is generated — which is the whole argument of
/// this library applied to the one feature the field implements at run time.
///
/// For comparison, in the two packages that have the feature: `slang` throws a
/// bare string for a target that does not exist and guards cycles only in the
/// pass that gathers parameters, so two messages linking to each other emit
/// code that calls itself; `easy_localization` resolves links at run time, one
/// level deep, and its own source carries the comment
/// `// TODO: add recursion detection and a resolve stack.`
abstract final class LinkResolver {
  /// Validates the links in [signatures] and returns what they contribute.
  ///
  /// [richPaths] are the keys of rich messages, which exist but cannot be
  /// linked to. [reported] is carried across locales: a link mistake copied
  /// into twelve translation files is one mistake, and this is the same rule
  /// the importer follows when a key is deleted from the base locale. Pass the
  /// base locale first, so the one diagnostic points at the file the project
  /// is maintained in.
  static LinkResolution resolve({
    required Map<String, MessageSignature> signatures,
    required Set<String> richPaths,
    required DiagnosticCollector diagnostics,
    required Set<String> reported,
  }) {
    final edges = <String, List<String>>{};
    final known = {...signatures.keys, ...richPaths};

    for (final entry in signatures.entries) {
      final from = entry.key;
      for (final link in entry.value.links) {
        if (richPaths.contains(link.path)) {
          if (reported.add('link_to_rich|$from|${link.path}')) {
            diagnostics.add(
              Diagnostic.error(
                code: 'link_to_rich',
                message:
                    '"${link.path}" is a rich message, so its text cannot be '
                    'put into another message.',
                span: link.span,
                translationKey: from,
                details:
                    'A rich message is a list of spans: its tags are '
                    'structure, and the builders that render them are '
                    'parameters of the call. There is no string to splice in '
                    'here.\n'
                    'Link to a plain message, or make this message rich too '
                    'and compose the spans in Dart.',
              ),
            );
          }
          continue;
        }
        if (!known.contains(link.path)) {
          if (reported.add('unknown_link_target|$from|${link.path}')) {
            final nearest = NearestKey.of(link.path, known);
            diagnostics.add(
              Diagnostic.error(
                code: 'unknown_link_target',
                message: 'No message is keyed "${link.path}".',
                span: link.span,
                translationKey: from,
                details:
                    '${nearest == null ? '' : 'Did you mean "$nearest"?\n'}'
                    'A link names a whole dotted key, the way the rest of '
                    'this project names one. A group is not a message, so '
                    '"auth.login" cannot be linked to when the message is '
                    '"auth.login.title".',
              ),
            );
          }
          continue;
        }
        (edges[from] ??= []).add(link.path);
      }
    }

    final order = _topological(
      edges: edges,
      signatures: signatures,
      diagnostics: diagnostics,
      reported: reported,
    );

    // Targets before the messages that link to them, so a chain is already
    // resolved by the time anything reads it and the transitive case needs no
    // second pass.
    final contributed = <String, List<ArgumentSpec>>{};
    for (final path in order) {
      final own = signatures[path];
      if (own == null) continue;
      final merged = <String, ArgumentSpec>{};
      // What the message declares itself goes in first, so a conflict is
      // reported against the link that disagreed with it rather than the
      // other way round: the caret belongs on the line a reader can change,
      // and the advice belongs to the message that did the linking.
      for (final spec in own.arguments.values) {
        MessageSignature.record(
          merged,
          spec,
          translationKey: path,
          diagnostics: diagnostics,
        );
      }
      for (final target in edges[path] ?? const <String>[]) {
        final link = signatures[path]!.links.firstWhere(
          (candidate) => candidate.path == target,
        );
        for (final spec in [
          ...signatures[target]!.arguments.values,
          ...?contributed[target],
        ]) {
          // The link's span, not the target's: the conflict a project has to
          // fix is here, in the message that asked for the other one, and a
          // caret in another file is a caret in the wrong file.
          MessageSignature.record(
            merged,
            ArgumentSpec(
              name: spec.name,
              kind: spec.kind,
              span: link.span,
              selectOptions: spec.selectOptions,
              format: spec.format,
              pluralType: spec.pluralType,
            ),
            translationKey: path,
            diagnostics: diagnostics,
            via: target,
          );
        }
      }
      final extra = [
        for (final spec in merged.values)
          if (!own.arguments.containsKey(spec.name)) spec,
      ];
      if (extra.isNotEmpty) contributed[path] = extra;
    }

    return LinkResolution(contributed);
  }

  /// Paths in dependency order, reporting every cycle it had to break.
  ///
  /// Iterative rather than recursive, because the thing being looked for is
  /// unbounded depth and a stack overflow in the checker would be a joke at
  /// its own expense.
  static List<String> _topological({
    required Map<String, List<String>> edges,
    required Map<String, MessageSignature> signatures,
    required DiagnosticCollector diagnostics,
    required Set<String> reported,
  }) {
    const white = 0, grey = 1, black = 2;
    final colour = <String, int>{};
    final order = <String>[];
    // Sorted, so the report of a project with two independent cycles is the
    // same report on every machine.
    final roots = edges.keys.toList(growable: false)..sort();

    for (final root in roots) {
      if ((colour[root] ?? white) != white) continue;
      final stack = <(String, int)>[(root, 0)];
      final path = <String>[root];
      colour[root] = grey;
      while (stack.isNotEmpty) {
        final (node, index) = stack.last;
        final children = edges[node] ?? const <String>[];
        if (index >= children.length) {
          stack.removeLast();
          path.removeLast();
          colour[node] = black;
          order.add(node);
          continue;
        }
        stack[stack.length - 1] = (node, index + 1);
        final child = children[index];
        final state = colour[child] ?? white;
        if (state == black) continue;
        if (state == grey) {
          _reportCycle(
            cycle: path.sublist(path.indexOf(child)),
            signatures: signatures,
            diagnostics: diagnostics,
            reported: reported,
          );
          continue;
        }
        colour[child] = grey;
        stack.add((child, 0));
        path.add(child);
      }
    }
    return order;
  }

  static void _reportCycle({
    required List<String> cycle,
    required Map<String, MessageSignature> signatures,
    required DiagnosticCollector diagnostics,
    required Set<String> reported,
  }) {
    // Keyed by the cycle's members rather than by where the walk entered it,
    // so the same loop found from two directions is still one finding.
    final identity = (cycle.toList(growable: false)..sort()).join('|');
    if (!reported.add('link_cycle|$identity')) return;

    // Reported against the first member, with the loop written out in the
    // order it is followed: the fix is to break it somewhere, and which link
    // to drop is a decision that needs the whole ring in front of you.
    final from = cycle.first;
    final link = signatures[from]!.links.firstWhere(
      (candidate) => candidate.path == cycle[cycle.length == 1 ? 0 : 1],
    );
    final ring = [...cycle, from].join(' -> ');
    diagnostics.add(
      Diagnostic.error(
        code: 'link_cycle',
        message: cycle.length == 1
            ? 'Message "$from" links to itself.'
            : 'These links form a cycle: $ring.',
        span: link.span,
        translationKey: from,
        details:
            'A link is resolved while generating, so a ring of them has no '
            'text to resolve to: every message in it is waiting for the next '
            'one. Nothing here can render, and nothing at run time would '
            'notice — a cycle of calls is a cycle of calls.\n'
            'Break it: write the shared words out in one of these messages, '
            'and let the others link to that one.',
      ),
    );
  }
}
