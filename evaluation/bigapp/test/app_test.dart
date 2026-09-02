import 'package:bigapp/l10n/app_l10n.g.dart';
import 'package:bigapp/l10n/app_l10n_flutter.g.dart';
import 'package:bigapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() => initializeAppL10nFormatting());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(BigApp(controller: createAppL10nController()));
    await tester.pumpAndSettle();
  }

  String textAt(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .data!;

  testWidgets('renders the base locale', (tester) async {
    await pumpApp(tester);
    expect(textAt(tester, 'plain'), 'Login action');
    expect(textAt(tester, 'plural'), '5 logins');
    expect(textAt(tester, 'currency'), 'Password subtitle: EUR1,234.50');
    expect(textAt(tester, 'interpolated'), 'Password hint, Alex');
    expect(textAt(tester, 'date'), 'Password empty on Mar 14, 2026');
    expect(textAt(tester, 'select'), 'History error on');
    expect(textAt(tester, 'nested'), '21 historys');
  });

  testWidgets('setLocale rebuilds everything that read context.l10n', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('locale-ru')));
    await tester.pumpAndSettle();

    expect(textAt(tester, 'plain'), 'Войти');
    // Russian plural: 5 -> many, 21 -> one.
    expect(textAt(tester, 'plural'), '5 login');
    expect(textAt(tester, 'nested'), '21 history');
    // Grouping and the currency position follow the locale.
    // Russian groups with a non breaking space, so compare against intl
    // rather than against a literal typed on a keyboard.
    expect(
      textAt(tester, 'currency'),
      endsWith(NumberFormat.currency(locale: 'ru', name: 'EUR').format(1234.5)),
    );
    expect(textAt(tester, 'date'), contains('2026'));

    await tester.tap(find.byKey(const Key('locale-de')));
    await tester.pumpAndSettle();
    expect(textAt(tester, 'plain'), 'Login action DE');
    expect(
      textAt(tester, 'currency'),
      endsWith(NumberFormat.currency(locale: 'de', name: 'EUR').format(1234.5)),
    );
  });

  testWidgets('the locale of the MaterialApp follows the controller', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    await tester.tap(find.byKey(const Key('locale-ru')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('ru'),
    );
  });

  testWidgets('a locale rolled out one key at a time still renders', (
    tester,
  ) async {
    // fr has exactly one translated message and fill_missing_from_base on.
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('locale-fr')));
    await tester.pumpAndSettle();
    // Translated: French text, and French plural rules.
    expect(textAt(tester, 'plural'), '5 logins');
    // Untranslated: the base locale's message, whole.
    expect(textAt(tester, 'plain'), 'Login action');
    expect(textAt(tester, 'interpolated'), 'Password hint, Alex');
    // And the numbers are formatted as en, not as fr: the whole message
    // falls back, formatter included. A French reader sees English grouping,
    // which is the point — it should look untranslated, not half translated.
    expect(
      textAt(tester, 'currency'),
      endsWith(NumberFormat.currency(locale: 'en', name: 'EUR').format(1234.5)),
    );
    expect(textAt(tester, 'date'), 'Password empty on Mar 14, 2026');
  });

  test('810 messages across nine features share one const graph', () {
    final t = AppL10n.forLocale(AppLocale.en);
    expect(identical(t.auth, t.auth), isTrue);
    expect(identical(t.auth.login, t.auth.login), isTrue);
    expect(identical(t.errors.validation, t.errors.validation), isTrue);
  });
}
