import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/codegen/intl_formatters.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the expected file.
bool get _updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

final String _packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

const String _config = '''
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

/// Every formatter the generator can emit, as one ARB bundle.
///
/// The message list is derived from [IntlFormatters] rather than written out,
/// so adding a style to an allowlist extends the surface automatically and the
/// golden diff says so.
///
/// [locale] gets a second, identical bundle when it is not the base, plus the
/// declarations that only a non base locale can make.
String _surfaceBundle({String locale = 'en'}) {
  final entries = <String, String>{};

  for (final style in IntlFormatters.numberStyles.keys) {
    final key = 'number_${style ?? 'default'}';
    entries[key] = style == null ? '{n, number}' : '{n, number, $style}';
  }
  for (final style in IntlFormatters.currencyStyles) {
    entries['code_$style'] = '{n, number, $style:USD}';
  }

  final dateStyles = [
    ...IntlFormatters.dateStyles.keys,
    ...IntlFormatters.dateSkeletons,
    ...IntlFormatters.timeSkeletons,
  ]..sort();
  for (var i = 0; i < dateStyles.length; i++) {
    // Indexed keys: the skeleton set contains both `M` and `m`, which would
    // normalize onto the same Dart identifier.
    entries['date_${i.toString().padLeft(2, '0')}'] =
        '{d, date, ${dateStyles[i]}}';
  }
  final timeStyles = [
    ...IntlFormatters.timeStyles.keys,
    ...IntlFormatters.timeSkeletons,
  ]..sort();
  for (var i = 0; i < timeStyles.length; i++) {
    entries['time_${i.toString().padLeft(2, '0')}'] =
        '{t, time, ${timeStyles[i]}}';
  }

  final buffer = StringBuffer('{\n  "@@locale": "$locale"');
  entries.forEach((key, message) {
    buffer.write(',\n  "$key": ${_json(message)}');
  });

  // The combinations only ARB can express.
  const declared = {
    'opt_symbol': '{"symbol": "US\$"}',
    'opt_digits': '{"decimalDigits": 0}',
    'opt_all': '{"name": "BTC", "symbol": "B", "decimalDigits": 8}',
    'opt_simple': '{"name": "JPY", "decimalDigits": 0}',
  };
  declared.forEach((key, options) {
    final style = key == 'opt_simple' ? 'simpleCurrency' : 'currency';
    buffer.write(',\n  "$key": "{n}"');
    if (locale != 'en') return;
    buffer.write(
      ',\n  "@$key": {"placeholders": {"n": '
      '{"type": "double", "format": "$style", '
      '"optionalParameters": $options}}}',
    );
  });

  // What only a non base locale can say: restyle what the base declared,
  // keeping its currency, its digits and the shared Dart type.
  if (locale != 'en') {
    buffer.write(
      ',\n  "@opt_digits": {"placeholders": '
      '{"n": {"format": "simpleCurrency"}}}',
    );
  }

  return (buffer..write('\n}\n')).toString();
}

String _json(String value) => '"${value.replaceAll(r'\', r'\\')}"';

void main() {
  test('every emittable formatter is a real intl call', () {
    final result = runGenerator({
      'app_en.arb': _surfaceBundle(),
      'app_ru.arb': _surfaceBundle(locale: 'ru'),
    }, configYaml: _config);

    expect(
      errorsOf(result),
      isEmpty,
      reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
    );

    final golden = File(
      p.join(_packageRoot, 'test/goldens/formats/app_localizations.g.dart'),
    );
    final generated = result.files.single.contents;
    if (_updateGoldens) {
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(generated);
      return;
    }

    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing golden ${golden.path}. Run UPDATE_GOLDENS=1.',
    );
    expect(
      generated,
      golden.readAsStringSync(),
      reason:
          'The set of emittable formatters changed. Run UPDATE_GOLDENS=1, '
          'then `dart analyze` — the golden is analyzed against the real '
          '`package:intl`, which is what proves the calls compile.',
    );
  });

  test('the golden is analyzed, which is the point of it', () {
    // `dart analyze` resolves this file against `package:intl`, so a named
    // parameter that does not exist is an analysis error rather than a
    // surprise in someone's app. Guard the setting that makes that true.
    final options = File(
      p.join(_packageRoot, 'analysis_options.yaml'),
    ).readAsStringSync();
    expect(
      options,
      isNot(contains('test/goldens')),
      reason: 'Excluding the goldens would silence the compile check.',
    );
  });

  group('bindingFor stays inside intl', () {
    test('simpleCurrency never receives a symbol', () {
      const format = ArgumentFormat(
        ArgumentFormatKind.number,
        'simpleCurrency',
        CurrencyOptions(code: 'USD', symbol: r'US$', decimalDigits: 2),
      );
      final binding = IntlFormatters.bindingFor(
        format: format,
        localeTag: 'en',
        localeDartName: 'en',
      )!;
      // `NumberFormat.simpleCurrency` has no `symbol:` parameter. The model
      // builder rejects this bundle; the emitter must not depend on that.
      expect(binding.initializer, isNot(contains('symbol:')));
      expect(binding.initializer, contains("name: 'USD'"));
      expect(binding.initializer, contains('decimalDigits: 2'));
    });

    test('every number style produces a binding', () {
      for (final style in IntlFormatters.numberStyles.keys) {
        final binding = IntlFormatters.bindingFor(
          format: ArgumentFormat(ArgumentFormatKind.number, style),
          localeTag: 'en',
          localeDartName: 'en',
        );
        expect(binding, isNotNull, reason: 'style $style');
        expect(binding!.dartType, 'NumberFormat');
        expect(binding.initializer, startsWith('NumberFormat.'));
      }
    });

    test('a shared field name always means an identical construction', () {
      final formats = <ArgumentFormat>[
        for (final style in IntlFormatters.numberStyles.keys)
          ArgumentFormat(ArgumentFormatKind.number, style),
        for (final style in IntlFormatters.currencyStyles) ...[
          ArgumentFormat(
            ArgumentFormatKind.number,
            style,
            const CurrencyOptions(code: 'USD'),
          ),
          ArgumentFormat(
            ArgumentFormatKind.number,
            style,
            const CurrencyOptions(code: 'EUR'),
          ),
          ArgumentFormat(
            ArgumentFormatKind.number,
            style,
            const CurrencyOptions(code: 'USD', decimalDigits: 0),
          ),
        ],
      ];

      // Two formats may legitimately share a formatter — `{n, number}` and
      // `{n, number, decimal}` are the same call. What must never happen is
      // two *different* calls landing on one field, because then whichever is
      // emitted last silently wins for both.
      final byName = <String, String>{};
      for (final format in formats) {
        final binding = IntlFormatters.bindingFor(
          format: format,
          localeTag: 'en',
          localeDartName: 'en',
        )!;
        final existing = byName[binding.fieldName];
        if (existing != null) {
          expect(
            binding.initializer,
            existing,
            reason: '$format shares ${binding.fieldName} with a different call',
          );
        }
        byName[binding.fieldName] = binding.initializer;
      }

      // And the currency options really do separate them.
      expect(byName.keys, contains('_enNumberCurrencyUsd'));
      expect(byName.keys, contains('_enNumberCurrencyEur'));
      expect(byName.keys, contains('_enNumberCurrencyUsdDigits0'));
    });
  });
}
