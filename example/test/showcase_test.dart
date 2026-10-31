import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';

void main() {
  setUpAll(initializeDateFormatting);

  test('the same call renders correctly in both languages', () {
    final en = AppLocalizations.forLocale(AppLocale.en).showcase;
    final ru = AppLocalizations.forLocale(AppLocale.ru).showcase;

    expect(
      en.greeting(name: 'Alex', daypart: ShowcaseGreetingDaypart.morning),
      'Good morning, Alex',
    );
    expect(
      ru.greeting(name: 'Алексей', daypart: ShowcaseGreetingDaypart.morning),
      'Доброе утро, Алексей',
    );

    // English has two plural categories here; Russian has four, and the
    // call site is identical.
    expect(en.reward(count: 0), 'Your next coffee is on us');
    expect(en.reward(count: 1), '1 drink until your next free coffee');
    expect(en.reward(count: 3), '3 drinks until your next free coffee');

    expect(ru.reward(count: 0), 'Следующий кофе за наш счёт');
    expect(ru.reward(count: 1), 'Ещё 1 напиток до бесплатного кофе');
    expect(ru.reward(count: 3), 'Ещё 3 напитка до бесплатного кофе');
    expect(ru.reward(count: 5), 'Ещё 5 напитков до бесплатного кофе');
    expect(ru.reward(count: 21), 'Ещё 21 напиток до бесплатного кофе');
  });

  test('money, dates and ordinals follow the reader', () {
    final en = AppLocalizations.forLocale(AppLocale.en).showcase.order;
    final ru = AppLocalizations.forLocale(AppLocale.ru).showcase.order;
    final readyAt = DateTime(2026, 3, 14, 9, 35);
    final placedOn = DateTime(2026, 3, 14);

    expect(en.total(amount: 12.4), r'$12.40');
    // `intl` separates the amount from the symbol with a no-break space.
    expect(ru.total(amount: 12.4), '12,40\u00A0₽');

    expect(en.ready(at: readyAt), 'Ready at 9:35\u202FAM');
    expect(ru.ready(at: readyAt), 'Готов в 09:35');

    expect(en.placed(on: placedOn), 'Placed on Mar 14, 2026');
    expect(ru.placed(on: placedOn), 'Оформлен 14 мар. 2026\u202Fг.');

    expect(en.queue(place: 3), 'You are 3rd in line');
    expect(ru.queue(place: 3), 'Вы 3-й в очереди');
  });
}
