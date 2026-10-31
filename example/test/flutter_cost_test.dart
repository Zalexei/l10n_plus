// What `context.l10n` and a locale switch cost, and how much of that is this
// library rather than Flutter.
//
// Not a rigorous benchmark: `flutter test` has no vsync, runs the JIT, and
// shares a machine with whatever else is on it. The numbers are printed, and
// nothing here asserts a timing — a threshold that fails on a slow CI box
// teaches people to ignore the suite. What is asserted is the shape of the
// answer: that a scope read is a constant time inherited lookup, and that a
// locale switch rebuilds only what read the locale.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';
import 'package:l10n_plus_example/generated/app_localizations_flutter.g.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

/// Somewhere for results to go, so nothing measured is optimized away.
int _sink = 0;

/// Microseconds per operation, over enough iterations to mean something.
double _measure(String label, int iterations, void Function() body) {
  for (var i = 0; i < iterations ~/ 10; i++) {
    body(); // warm up
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  watch.stop();
  final perOp = watch.elapsedMicroseconds / iterations;
  print('  ${label.padRight(38)} ${perOp.toStringAsFixed(3)} µs');
  return perOp;
}

/// Counts how many times it rebuilt, so a locale switch can be measured in
/// rebuilds rather than only in milliseconds.
class _Counter extends StatelessWidget {
  const _Counter({required this.reads, required this.builds});

  final bool reads;
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds[0]++;
    // Half the tree reads translations; the other half does not, which is
    // what shows whether the scope rebuilds everything or only its readers.
    return Text(
      reads ? context.l10n.auth.login.title : 'static',
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  testWidgets('what a scope read costs', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      L10nScope(
        controller: createAppLocalizationsController(),
        child: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );

    print('\nlookup, 200000 iterations each:');
    final scope = _measure('context.l10n', 200000, () {
      _sink += ctx.l10n.auth.login.title.length;
    });
    final direct = _measure('AppLocalizations.forLocale', 200000, () {
      _sink += AppLocalizations.forLocale(AppLocale.en).auth.login.title.length;
    });
    final resolve = _measure('AppLocalizations.of(parse(tag))', 200000, () {
      _sink += AppLocalizations.of(
        L10nLocale.parse('en_GB'),
      ).auth.login.title.length;
    });
    print(
      '  context.l10n is ${(scope / direct).toStringAsFixed(1)}x the direct '
      'call; the difference is Flutter\'s inherited widget lookup.',
    );

    // Shape, not speed: a `BuildContext` read must not be doing more work
    // than resolving a locale tag from scratch, which parses a string.
    expect(scope, lessThan(resolve));
    expect(_sink, greaterThan(0));
  });

  testWidgets('what a locale switch costs', (tester) async {
    final readerBuilds = [0];
    final staticBuilds = [0];
    final controller = createAppLocalizationsController();

    await tester.pumpWidget(
      L10nScope(
        controller: controller,
        child: Directionality(
          textDirection: TextDirection.ltr,
          // Scrolling gives the column an unbounded main axis, so all two
          // hundred children are built rather than clipped.
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 100; i++)
                  _Counter(reads: true, builds: readerBuilds),
                for (var i = 0; i < 100; i++)
                  _Counter(reads: false, builds: staticBuilds),
              ],
            ),
          ),
        ),
      ),
    );

    expect(readerBuilds[0], 100);
    expect(staticBuilds[0], 100);
    expect(find.text('Log in'), findsNWidgets(100));

    // The first switch compiles the Russian path, so timing that measures the
    // JIT. Measure the steady state too, and report the median of it.
    final samples = <int>[];
    for (var i = 0; i < 9; i++) {
      final watch = Stopwatch()..start();
      controller.setLocale(i.isEven ? AppLocale.ru : AppLocale.en);
      await tester.pump();
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    final sorted = [...samples]..sort();

    print('\nlocale switch, 200 widgets, 100 of them reading:');
    print('  first switch, includes JIT             ${samples.first} µs');
    print('  median of nine                         ${sorted[4]} µs');
    print(
      '  per reading widget                     '
      '${(sorted[4] / 100).toStringAsFixed(2)} µs',
    );
    print(
      '  rebuilt per switch                     '
      '${(readerBuilds[0] - 100) ~/ 9} readers, '
      '${(staticBuilds[0] - 100) ~/ 9} others',
    );

    // The claim worth guarding: switching rebuilds the widgets that read the
    // locale and leaves the rest alone, every time and not just the first.
    expect(
      readerBuilds[0],
      100 + 9 * 100,
      reason: 'every reader should rebuild on every switch',
    );
    expect(staticBuilds[0], 100, reason: 'non readers must never rebuild');
    // Nine switches, alternating and starting at ru, end on ru.
    expect(find.text('Войти'), findsNWidgets(100));
  });
}
