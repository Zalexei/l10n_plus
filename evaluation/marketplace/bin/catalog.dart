import 'package:marketplace/l10n/catalog.g.dart';

Future<void> main() async {
  await initializeCatalogFormatting();
  final when = DateTime(2026, 3, 14, 15, 9);

  for (final locale in CatalogLocale.values) {
    final t = Catalog.forLocale(locale);
    print('===== ${locale.name} =====');
    for (final n in [0, 1, 2, 3, 10, 11, 21, 99, 100, 101, 102, 103, 1500]) {
      print('  reviews($n) = ${t.search.reviews(count: n)}');
    }
    print('  fraction 1.5 -> ${t.search.reviews(count: 1.5)}');
    print('  compact       ${t.search.viewers(count: 12345)}');
    print('  compactLong   ${t.search.sold(count: 2400000)}');
    print('  cart 0        ${t.cart.summary(count: 0, total: 0)}');
    print('  cart 3        ${t.cart.summary(count: 3, total: 74.9)}');
    print(
      '  shipping      ${t.cart.shipping(kind: CartShippingKind.express, days: 1)}',
    );
    print(
      '  promo         ${t.cart.promo(applied: CartPromoApplied.yes, amount: 12.5)}',
    );
    print('  placed        ${t.order.placed(when: when)}');
    print('  rank 3        ${t.order.rank(n: 3)}');
    print('  items 1       ${t.order.items(count: 1, first: 'Widget')}');
    print('  items 4       ${t.order.items(count: 4, first: 'Widget')}');
    print('  rating        ${t.seller.rating(stars: 4.7, count: 128)}');
    print('  badge         ${t.seller.badge(tier: SellerBadgeTier.gold)}');
    print('');
  }
}
