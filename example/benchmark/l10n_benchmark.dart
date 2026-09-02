// Measures the claims `docs/architecture.md` makes about generated code.
//
// Run with:
//
//     dart run benchmark/l10n_benchmark.dart
//
// Each generated call is measured against the runtime map lookup the design
// rejected, so the recorded trade-off is a number rather than an assertion.
// The map baseline is deliberately favourable: one flat `Map<String, String>`
// per locale, no nesting to walk and no argument checking, which is the best
// case for the approach rather than a straw man.
// This is a command line script; printing is the output.
// ignore_for_file: avoid_print
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';

/// Somewhere for results to go, so nothing measured can be optimized away.
int _sink = 0;

/// The best case a runtime map could offer: flat, pre-joined, no nesting.
const Map<String, String> _map = {
  'auth.login.title': 'Log in',
  'auth.login.subtitle': 'Welcome back, {name}',
  'wallet.transactions.one': '1 transaction',
  'wallet.transactions.other': '{count} transactions',
};

abstract class _Case extends BenchmarkBase {
  _Case(super.name);

  static final AppLocalizations t = AppLocalizations.forLocale(AppLocale.en);

  /// Inputs are cycled rather than constant on purpose.
  ///
  /// A pure call with a constant argument can be hoisted out of the loop, and
  /// then the number measures the hoist rather than the call.
  static const List<String> names = ['Alex', 'Sam', 'Kim', 'Lee'];
  static const List<double> amounts = [1234.5, 42, 1000000.25, 0.5];

  int step = 0;

  void consume(String value) => _sink += value.length;
}

class _GetterAccess extends _Case {
  _GetterAccess() : super('getter, three namespaces deep');

  @override
  void run() {
    // Even a field read is cycled through the locales, so the receiver is not
    // a compile time constant the whole loop can be folded against.
    step = (step + 1) % AppLocale.values.length;
    consume(AppLocale.values[step].translations.auth.login.title);
  }
}

class _MapGetterAccess extends _Case {
  _MapGetterAccess() : super('  map lookup, same string');

  @override
  void run() {
    step = (step + 1) % _Case.names.length;
    consume(_map[step.isEven ? 'auth.login.title' : 'auth.login.subtitle']!);
  }
}

class _Interpolation extends _Case {
  _Interpolation() : super('interpolation, one argument');

  @override
  void run() {
    step = (step + 1) % _Case.names.length;
    consume(_Case.t.auth.login.subtitle(name: _Case.names[step]));
  }
}

class _MapInterpolation extends _Case {
  _MapInterpolation() : super('  map lookup and replace');

  @override
  void run() {
    step = (step + 1) % _Case.names.length;
    consume(
      _map['auth.login.subtitle']!.replaceAll('{name}', _Case.names[step]),
    );
  }
}

class _Plural extends _Case {
  _Plural() : super('plural, CLDR branch');

  @override
  void run() {
    // Vary the input so one branch is not the only one ever taken.
    step = (step + 1) % 25;
    consume(_Case.t.wallet.transactions(count: step));
  }
}

class _MapPlural extends _Case {
  _MapPlural() : super('  map lookup and English plural');

  @override
  void run() {
    step = (step + 1) % 25;
    final key = step == 1
        ? 'wallet.transactions.one'
        : 'wallet.transactions.other';
    consume(_map[key]!.replaceAll('{count}', '$step'));
  }
}

class _Select extends _Case {
  _Select() : super('select, generated enum');

  @override
  void run() {
    step = (step + 1) % ProfileGreetingGender.values.length;
    consume(
      _Case.t.profile.greeting(
        gender: ProfileGreetingGender.values[step],
        name: 'Alex',
      ),
    );
  }
}

class _NumberFormat extends _Case {
  _NumberFormat() : super('number, shared NumberFormat');

  @override
  void run() {
    step = (step + 1) % _Case.amounts.length;
    consume(_Case.t.wallet.total(amount: _Case.amounts[step]));
  }
}

class _LocaleResolve extends _Case {
  _LocaleResolve() : super('locale fallback resolution');

  static const List<String> tags = ['ru_RU', 'en_GB', 'de', 'ru'];

  @override
  void run() {
    step = (step + 1) % tags.length;
    consume(AppLocalizations.of(L10nLocale.parse(tags[step])).auth.login.title);
  }
}

/// Every case, in report order.
///
/// Exposed so a test can run each once. Timings are not asserted anywhere —
/// they depend on the machine — but a benchmark that no longer compiles or
/// throws is a benchmark nobody will notice has rotted.
List<BenchmarkBase> benchmarkCases() => [
  _GetterAccess(),
  _MapGetterAccess(),
  _Interpolation(),
  _MapInterpolation(),
  _Plural(),
  _MapPlural(),
  _Select(),
  _NumberFormat(),
  _LocaleResolve(),
];

void main() {
  // Every namespace object is `const`, so the whole tree is canonicalized at
  // compile time. Stated as an assertion rather than a measurement: there is
  // nothing to time, and identity is the stronger claim.
  final t = _Case.t;
  final allocatesNothing =
      identical(t.auth, t.auth) && identical(t.auth.login, t.auth.login);
  print('namespace access allocates nothing: $allocatesNothing');
  print('');

  for (final benchmark in benchmarkCases()) {
    // `BenchmarkBase.measure` returns microseconds for 10 runs of `run()`.
    final nanosecondsPerCall = benchmark.measure() * 1000 / 10;
    print(
      '${benchmark.name.padRight(32)} '
      '${nanosecondsPerCall.toStringAsFixed(1).padLeft(9)} ns',
    );
  }

  // Keeps the sink observably live.
  if (_sink < 0) print(_sink);
}
