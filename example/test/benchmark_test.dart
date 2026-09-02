@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../benchmark/l10n_benchmark.dart';

void main() {
  test('every benchmark case runs', () {
    // Guards the benchmark against rot. Timings are not asserted: they depend
    // on the machine, and a threshold that fails on a slow CI box teaches
    // people to ignore it.
    final cases = benchmarkCases();
    expect(cases, isNotEmpty);
    for (final benchmark in cases) {
      expect(benchmark.name, isNotEmpty);
      expect(
        () {
          benchmark.setup();
          for (var i = 0; i < 100; i++) {
            benchmark.run();
          }
          benchmark.teardown();
        },
        returnsNormally,
        reason: benchmark.name,
      );
    }
  });
}
