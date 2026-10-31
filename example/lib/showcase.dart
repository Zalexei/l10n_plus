import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

import 'generated/app_localizations.g.dart';
import 'generated/app_localizations_flutter.g.dart';

/// A one screen coffee shop, in every language the app has.
///
/// Run it with `flutter run -t lib/showcase.dart`. Nothing below mentions a
/// language, a plural rule or a currency: those live in `translations/`, and
/// the compiler is what keeps the two in step.
Future<void> main() async {
  await initializeAppLocalizationsFormatting();
  runApp(ShowcaseApp(controller: createAppLocalizationsController()));
}

/// Plain application state. No localization anywhere near it.
class Order {
  /// Creates an order.
  const Order({
    required this.code,
    required this.items,
    required this.total,
    required this.readyAt,
    required this.placedOn,
    required this.queuePosition,
  });

  /// Human facing order code, printed on the cup.
  final String code;

  /// How many things are in the cup holder.
  final int items;

  /// What it costs, in the currency of whoever is reading.
  final double total;

  /// When the barista expects to be done.
  final DateTime readyAt;

  /// When the order was placed.
  final DateTime placedOn;

  /// Where the customer stands in the queue.
  final int queuePosition;
}

/// The showcase application.
class ShowcaseApp extends StatelessWidget {
  /// Creates the showcase.
  const ShowcaseApp({required this.controller, super.key});

  /// Drives the active locale.
  final AppLocalizationsController controller;

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      controller: controller,
      child: Builder(
        builder: (context) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: context.l10nController.locale.flutterLocale,
          supportedLocales: appLocalizationsSupportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF6F4E37),
            useMaterial3: true,
          ),
          home: ShowcasePage(
            order: Order(
              code: '1042',
              items: 2,
              total: 12.4,
              readyAt: DateTime(2026, 3, 14, 9, 35),
              placedOn: DateTime(2026, 3, 14),
              queuePosition: 3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The only screen.
class ShowcasePage extends StatelessWidget {
  /// Creates the screen.
  const ShowcasePage({required this.order, super.key});

  /// The order on display.
  final Order order;

  @override
  Widget build(BuildContext context) {
    // One lookup for the whole screen. `t` is a const object graph, so this
    // allocates nothing and costs a field read per message.
    final t = context.l10n.showcase;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              t.greeting(
                name: 'Alex',
                daypart: ShowcaseGreetingDaypart.morning,
              ),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(t.reward(count: 3)),
            const SizedBox(height: 24),
            _OrderCard(order: order),
            const SizedBox(height: 24),
            const _LocaleSwitcher(),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    // A namespace is an object, so a widget can hold on to just its own
    // corner of the translations.
    final t = context.l10n.showcase.order;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.title(code: order.code),
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  t.total(amount: order.total),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.items(count: order.items),
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: 28),
            _Row(
              icon: Icons.schedule,
              text: t.ready(at: order.readyAt),
            ),
            _Row(
              icon: Icons.groups,
              text: t.queue(place: order.queuePosition),
            ),
            _Row(
              icon: Icons.receipt_long,
              text: t.placed(on: order.placedOn),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _LocaleSwitcher extends StatelessWidget {
  const _LocaleSwitcher();

  @override
  Widget build(BuildContext context) {
    final controller = context.l10nController;

    return SegmentedButton<AppLocale>(
      segments: [
        for (final locale in AppLocalizations.supportedLocales)
          ButtonSegment(
            value: locale,
            label: Text(locale.l10nLocale.toLanguageTag()),
          ),
      ],
      selected: {controller.locale},
      // Every widget that read `context.l10n` above rebuilds. Nothing else does.
      onSelectionChanged: (selection) => controller.setLocale(selection.first),
    );
  }
}
