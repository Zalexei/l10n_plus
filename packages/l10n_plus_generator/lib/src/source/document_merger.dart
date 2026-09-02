import 'package:l10n_plus/l10n_plus.dart';

import '../ast/translation_tree.dart';
import '../diagnostic.dart';

/// Combines the several files a locale may be spread over into one document.
///
/// The rule is **groups merge, leaves collide**. Two files both contributing to
/// `wallet` is the reason the feature exists; two files both defining
/// `wallet.balance` is a mistake that would otherwise be decided by whichever
/// happened to be read last, which is the class of silent behaviour this
/// library exists to remove.
///
/// A file name contributes nothing to the tree: every file writes its keys in
/// full, so merging is a plain union and no path is rewritten.
abstract final class DocumentMerger {
  /// Merges [documents], which must all be the same locale.
  ///
  /// [documents] are merged in the order given, which the caller sorts by path
  /// so that the generated output never depends on the file system.
  static TranslationDocument merge(
    List<TranslationDocument> documents, {
    required DiagnosticCollector diagnostics,
  }) {
    if (documents.length == 1) return documents.single;

    final first = documents.first;
    // Remembers which file defined each path, so a collision can name both.
    final origins = <String, Uri>{};
    final children = <TranslationNode>[];

    for (final document in documents) {
      _mergeInto(
        into: children,
        from: document.root.children,
        origin: document.uri,
        origins: origins,
        locale: document.locale,
        diagnostics: diagnostics,
      );
    }

    return TranslationDocument(
      locale: first.locale,
      uri: first.uri,
      root: TranslationGroup(
        key: first.root.key,
        path: first.root.path,
        keySpan: first.root.keySpan,
        children: children,
      ),
    );
  }

  static void _mergeInto({
    required List<TranslationNode> into,
    required List<TranslationNode> from,
    required Uri origin,
    required Map<String, Uri> origins,
    required L10nLocale locale,
    required DiagnosticCollector diagnostics,
  }) {
    for (final node in from) {
      final index = into.indexWhere((existing) => existing.key == node.key);
      if (index < 0) {
        into.add(node);
        _remember(node, origin, origins);
        continue;
      }

      final existing = into[index];
      switch ((existing, node)) {
        case (final TranslationGroup a, final TranslationGroup b):
          final children = a.children.toList();
          _mergeInto(
            into: children,
            from: b.children,
            origin: origin,
            origins: origins,
            locale: locale,
            diagnostics: diagnostics,
          );
          into[index] = TranslationGroup(
            key: a.key,
            path: a.path,
            keySpan: a.keySpan,
            children: children,
          );

        case (TranslationLeaf(), TranslationLeaf()):
          diagnostics.add(
            Diagnostic.error(
              code: 'duplicate_key',
              message:
                  'Key "${node.path}" is defined twice for locale '
                  '"${locale.toFileTag()}".',
              span: node.keySpan,
              translationKey: node.path,
              details:
                  'Also defined in ${_show(origins[node.path])}.\n'
                  'Files of one locale are merged, so a key may appear in '
                  'only one of them.',
            ),
          );

        default:
          final groupFirst = existing is TranslationGroup;
          diagnostics.add(
            Diagnostic.error(
              code: 'conflicting_key_kind',
              message:
                  'Key "${node.path}" is a group in one file and a message in '
                  'another.',
              span: node.keySpan,
              translationKey: node.path,
              details:
                  '${_show(origins[node.path])}: '
                  '${groupFirst ? 'a group' : 'a message'}\n'
                  '${_show(origin)}: '
                  '${groupFirst ? 'a message' : 'a group'}\n'
                  'One key cannot be both a namespace and a translation.',
            ),
          );
      }
    }
  }

  /// Records where [node] and everything under it was first defined.
  static void _remember(
    TranslationNode node,
    Uri origin,
    Map<String, Uri> origins,
  ) {
    origins[node.path] = origin;
    if (node is TranslationGroup) {
      for (final child in node.children) {
        _remember(child, origin, origins);
      }
    }
  }

  static String _show(Uri? uri) {
    if (uri == null) return 'another file';
    final segments = uri.pathSegments;
    return segments.isEmpty ? uri.toString() : segments.last;
  }
}
