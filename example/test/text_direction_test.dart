import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

/// The demo app ships English and Russian, which are both left to right, so
/// the direction is exercised against a locale set of this test's own. It is
/// the same `L10nController` and the same `L10nScope` the generated code
/// builds; only the locale enum is local.
enum _Locale implements AppLocaleBase {
  en(L10nLocale('en')),
  ar(L10nLocale('ar')),
  // A right-to-left language written in Latin: the script subtag has to win
  // over the language, here as in the runtime.
  urLatn(L10nLocale('ur', script: 'Latn'));

  const _Locale(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

final class _Translations implements BaseTranslations {
  const _Translations(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

L10nController<_Locale, _Translations> _controller(_Locale locale) {
  final controller = L10nController<_Locale, _Translations>(
    supportedLocales: _Locale.values,
    fallbackLocale: _Locale.en,
    translationsOf: (locale) => _Translations(locale.l10nLocale),
    initialLocale: locale,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// A subtree that takes its direction from the scope above it, as an app
/// would: one `Directionality` at the top and nothing below it that knows
/// about locales at all.
Widget _app(L10nController<_Locale, _Translations> controller) {
  return L10nScope<_Locale, _Translations>(
    controller: controller,
    child: Builder(
      builder: (context) => Directionality(
        textDirection: L10nScope.controllerOf<_Locale, _Translations>(
          context,
        ).textDirection,
        child: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: 100, height: 100, child: Text('x')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('switching to a right-to-left locale flips the layout', (
    tester,
  ) async {
    final controller = _controller(_Locale.en);
    await tester.pumpWidget(_app(controller));

    final box = find.byType(SizedBox);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    // `centerStart` is the left edge while the locale reads left to right.
    expect(tester.getTopLeft(box).dx, 0);

    controller.setLocale(_Locale.ar);
    await tester.pump();

    // The scope rebuilt its dependents, the `Directionality` above the
    // subtree changed, and `start` is now the other edge. Nothing below the
    // scope was told about the locale.
    expect(controller.textDirection, TextDirection.rtl);
    expect(tester.getTopLeft(box).dx, width - 100);
  });

  testWidgets('the direction notifies the same listeners as the locale', (
    tester,
  ) async {
    final controller = _controller(_Locale.en);
    final seen = <TextDirection>[];
    controller.addListener(() => seen.add(controller.textDirection));

    controller.setLocale(_Locale.ar);
    controller.setLocale(_Locale.en);

    expect(seen, [TextDirection.rtl, TextDirection.ltr]);
  });

  test('the controller reports the direction of its active locale', () {
    expect(_controller(_Locale.en).textDirection, TextDirection.ltr);
    expect(_controller(_Locale.ar).textDirection, TextDirection.rtl);
    // Romanized Urdu: right-to-left language, left-to-right script.
    expect(_controller(_Locale.urLatn).textDirection, TextDirection.ltr);
  });

  test('a locale converts to a direction without a controller', () {
    expect(const L10nLocale('he').textDirection, TextDirection.rtl);
    expect(L10nLocale.parse('fa_IR').textDirection, TextDirection.rtl);
    expect(L10nLocale.parse('en_US').textDirection, TextDirection.ltr);
  });

  test('the demo app is left to right in both of its locales', () {
    for (final locale in AppLocale.values) {
      expect(locale.l10nLocale.textDirection, TextDirection.ltr);
    }
  });
}
