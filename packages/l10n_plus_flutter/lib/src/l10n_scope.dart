import 'package:flutter/widgets.dart';
import 'package:l10n_plus/l10n_plus.dart';

import 'flutter_locale.dart';
import 'l10n_controller.dart';

/// Publishes an [L10nController] to the widget tree and rebuilds dependents
/// when the locale changes.
///
/// Place it above `MaterialApp`, `CupertinoApp` or `WidgetsApp`.
class L10nScope<L extends AppLocaleBase, T extends BaseTranslations>
    extends StatefulWidget {
  /// Creates a scope for [controller].
  const L10nScope({required this.controller, required this.child, super.key});

  /// The controller to publish.
  final L10nController<L, T> controller;

  /// The subtree that can read the translations.
  final Widget child;

  /// The controller of the nearest enclosing scope.
  ///
  /// Throws a [FlutterError] when there is no scope above [context].
  static L10nController<L, T> controllerOf<
    L extends AppLocaleBase,
    T extends BaseTranslations
  >(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_L10nInherited<L, T>>();
    if (scope == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No L10nScope<$L, $T> found above this widget.'),
        ErrorDescription(
          'Translations are read from the nearest L10nScope, so one must be '
          'installed above the widget that reads them.',
        ),
        ErrorHint(
          'Wrap your app with L10nScope(controller: ..., child: MyApp()).',
        ),
      ]);
    }
    return scope.controller;
  }

  /// The translations of the nearest enclosing scope.
  static T of<L extends AppLocaleBase, T extends BaseTranslations>(
    BuildContext context,
  ) => controllerOf<L, T>(context).translations;

  @override
  State<L10nScope<L, T>> createState() => _L10nScopeState<L, T>();
}

class _L10nScopeState<L extends AppLocaleBase, T extends BaseTranslations>
    extends State<L10nScope<L, T>>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    widget.controller.handleSystemLocalesChanged([
      for (final locale in locales ?? const <Locale>[]) locale.toL10nLocale(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return _L10nInherited<L, T>(
      controller: widget.controller,
      child: widget.child,
    );
  }
}

class _L10nInherited<L extends AppLocaleBase, T extends BaseTranslations>
    extends InheritedNotifier<L10nController<L, T>> {
  const _L10nInherited({required this.controller, required super.child})
    : super(notifier: controller);

  final L10nController<L, T> controller;
}
