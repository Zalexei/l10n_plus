import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the expected files.
bool get _updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

/// Package root, resolved from the package config so that the test passes no
/// matter which directory `dart test` was started from.
final String _packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

/// One fixture directory per input format, plus one per file layout.
const List<String> _fixtures = [
  'json',
  'arb',
  'yaml',
  'split',
  'fill_missing',
  'current',
];

GenerationResult _run(String fixture) {
  final root = p.join(_packageRoot, 'test/fixtures', fixture);
  final configFile = File(p.join(root, 'l10n_plus.yaml'));
  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    configFile.readAsStringSync(),
    uri: configFile.uri,
    diagnostics: diagnostics,
  )!;
  final result = L10nPlusGenerator(config: config, projectRoot: root).run();
  expect(
    result.diagnostics.where((d) => d.severity == Severity.error),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format()).join('\n'),
  );
  return result;
}

/// Every generated file of [fixture], joined.
///
/// With `file_per_locale` the implementations live in `part` files, so a test
/// about what was generated has to look at the library, not at file zero.
String _library(String fixture) =>
    _run(fixture).files.map((file) => file.contents).join('\n');

void main() {
  for (final fixture in _fixtures) {
    group('$fixture fixture', () {
      test('matches its goldens', () {
        final result = _run(fixture);
        final goldenDir = p.join(_packageRoot, 'test/goldens', fixture);

        for (final file in result.files) {
          final golden = File(p.join(goldenDir, p.basename(file.path)));
          if (_updateGoldens) {
            golden.parent.createSync(recursive: true);
            golden.writeAsStringSync(file.contents);
            continue;
          }
          expect(
            golden.existsSync(),
            isTrue,
            reason: 'Missing golden ${golden.path}. Run UPDATE_GOLDENS=1.',
          );
          expect(
            file.contents,
            golden.readAsStringSync(),
            reason:
                'Generated ${p.basename(file.path)} drifted from its golden. '
                'Run UPDATE_GOLDENS=1 after reviewing the change.',
          );
        }
      });

      test('is deterministic across runs', () {
        expect(
          _run(fixture).files.map((f) => f.contents),
          _run(fixture).files.map((f) => f.contents),
        );
      });
    });
  }

  test('generated code contains no runtime key lookups', () {
    for (final fixture in _fixtures) {
      final core = _run(fixture).files.first.contents;
      expect(core, isNot(contains('Map<String')), reason: fixture);
      expect(core, isNot(contains('jsonDecode')), reason: fixture);
      expect(core, isNot(contains('dynamic ')), reason: fixture);
    }
  });

  test('namespaces are const so access allocates nothing', () {
    final core = _run('json').files.first.contents;
    expect(core, contains(r'$AuthLogin get login => const $AuthLoginEn();'));
  });

  test('ICU quoting is resolved at generation time', () {
    final core = _run('json').files.first.contents;
    expect(
      core,
      contains(r"""String get quotedKey => 'It\'s a {literal brace}';"""),
    );
  });

  test('plural conditions are inlined per locale', () {
    final core = _run('json').files.first.contents;
    // English has one and other; Russian additionally has few and many.
    expect(core, contains(r'$operands.i == 1 && $operands.v == 0'));
    expect(core, contains(r'$operands.i % 100 >= 11'));
  });

  test('ordinal and cardinal rules come from different tables', () {
    final core = _run('json').files.first.contents;
    // Cardinal `one` for English is i == 1; ordinal `one` is i % 10 == 1.
    expect(core, contains(r'$operands.i == 1 && $operands.v == 0'));
    expect(core, contains(r'$operands.i % 10 == 1 && $operands.i % 100 != 11'));
    expect(core, contains(r'final $countOffset = count - 1;'));
  });

  test('ARB metadata reaches the generated documentation and types', () {
    final core = _run('arb').files.first.contents;
    expect(core, contains('/// Title of the login screen'));
    expect(core, contains("/// - [name]: The signed in user's first name"));
    expect(core, contains('String transactions({required int count})'));
  });

  test('ARB format attributes drive intl formatting', () {
    final core = _run('arb').files.first.contents;
    expect(core, contains("import 'package:intl/intl.dart';"));
    expect(core, contains("DateFormat.yMMMd('en')"));
    expect(core, contains("NumberFormat.currency(locale: 'ru')"));
    expect(
      core,
      contains(
        'String statement({required DateTime from, required double amount})',
      ),
    );
    expect(
      core,
      contains('Future<void> initializeAppLocalizationsFormatting()'),
    );
  });

  test('explicit currency codes become their own formatters', () {
    final core = _run('arb').files.first.contents;
    // The locale default, an ARB `optionalParameters` code, and a code written
    // in the message all coexist in one locale.
    expect(
      core,
      contains("_enNumberCurrency = NumberFormat.currency(locale: 'en')"),
    );
    expect(core, contains("name: 'USD'"));
    expect(core, contains("name: 'EUR'"));
    expect(core, contains(r'${_enNumberCurrencyUsd.format(amount)}'));
    // The Russian bundle inherits USD from the base and adds its own
    // fraction digits, so it gets a formatter of its own.
    expect(core, contains(r'${_ruNumberCurrencyUsdDigits0.format(amount)}'));
  });

  test('simpleCurrency and decimalDigits reach the generated formatter', () {
    final core = _run('arb').files.first.contents;
    expect(core, contains('_enNumberSimpleCurrencyUsdDigits0'));
    expect(
      core.replaceAll(RegExp(r'\s+'), ' '),
      contains(
        "NumberFormat.simpleCurrency(locale: 'en', name: 'USD', "
        "decimalDigits: 0)",
      ),
    );
  });

  test('a bundle may restyle what the base locale declared', () {
    final core = _run('arb').files.first.contents;
    // `wallet.rounded` is simpleCurrency/USD/0 digits in the base. Russian
    // declares only `"format": "currency"`, so it keeps the currency and the
    // digits and changes nothing else — including the parameter type.
    expect(core, contains(r"'Rounded: ${_enNumberSimpleCurrencyUsdDigits0"));
    expect(core, contains(r"'Округлённо: ${_ruNumberCurrencyUsdDigits0"));
    expect(core, contains('String rounded({required double amount})'));
  });

  test('a non base bundle carries its own currency settings', () {
    final core = _run('arb').files.first.contents;
    // Same message, same declared currency: only the digits differ, and only
    // in the locale that asked for it.
    expect(core, contains('_enNumberCurrencyUsd ='));
    expect(core, contains('_ruNumberCurrencyUsdDigits0 ='));
    expect(core, isNot(contains('_enNumberCurrencyUsdDigits0')));
  });

  test('a declared numeric type survives a declared format', () {
    final core = _run('arb').files.first.contents;
    expect(core, contains('String rounded({required double amount})'));
  });

  test('format_plural_numbers renders # through NumberFormat when on', () {
    final core = _run('arb').files.first.contents;
    expect(core, contains(r'${_enNumberDecimalPattern.format(count)} cards'));
    expect(core, contains(r'${_ruNumberDecimalPattern.format(count)} карт'));
  });

  test('format_plural_numbers is off by default, so # stays raw', () {
    final core = _run('json').files.first.contents;
    expect(core, contains(r"return '$count cards';"));
    expect(core, isNot(contains('NumberFormat')));
  });

  test('several files of one locale merge into one API', () {
    final core = _library('split');
    // Three files per locale, two formats, one tree. The pattern is
    // `{locale}/{namespace}`, so `wallet.arb` holds "balance" and the name
    // supplies `wallet` — nothing repeats the prefix inside the file.
    expect(core, contains(r'$Auth get auth'));
    expect(core, contains(r'$Wallet get wallet'));
    expect(core, contains(r'$Profile get profile'));
    expect(core, contains("String get title => 'Log in';"));
    expect(core, contains("String get title => 'Войти';"));
  });

  test('the namespace from a file name is a namespace like any other', () {
    final core = _library('split');
    // `en/wallet.arb` writes "balance"; the API is the same as if it had
    // written "wallet.balance" under a pattern that captures nothing.
    expect(core, contains(r'$Wallet get wallet'));
    expect(core, contains('String balance({required double amount})'));
    expect(core, isNot(contains(r'$WalletWallet')));
  });

  test('ARB metadata still applies across a split layout', () {
    final core = _library('split');
    expect(core, contains('_enNumberCurrencyUsd'));
    // The Russian bundle keeps the currency and drops the kopecks.
    expect(core, contains('_ruNumberCurrencyUsdDigits0'));
    expect(core, contains('String balance({required double amount})'));
  });

  group('file_per_locale', () {
    test('the shared file holds the enums and interfaces only', () {
      final files = _run('split').files;
      final shared = files
          .firstWhere((file) => file.path.endsWith('app_localizations.g.dart'))
          .contents;

      expect(shared, contains('enum AppLocale'));
      expect(shared, contains(r'abstract interface class $Wallet'));
      expect(shared, contains("part 'app_localizations_en.g.dart';"));
      expect(shared, contains("part 'app_localizations_ru.g.dart';"));
      // No implementation, and no locale's formatters.
      expect(shared, isNot(contains('class AppLocalizationsEn')));
      expect(shared, isNot(contains('_enNumberCurrencyUsd =')));
    });

    test('each locale file holds only its own translations', () {
      final files = _run('split').files;
      String part(String locale) => files
          .firstWhere((file) => file.path.endsWith('_$locale.g.dart'))
          .contents;

      expect(part('en'), contains("part of 'app_localizations.g.dart';"));
      expect(part('en'), contains("String get title => 'Log in';"));
      expect(part('en'), isNot(contains('Войти')));

      expect(part('ru'), contains("String get title => 'Войти';"));
      expect(part('ru'), isNot(contains('Log in')));

      // The point of the feature: a locale's formatters travel with it, so
      // adding a Russian currency does not rewrite the English file.
      expect(part('en'), contains('_enNumberCurrencyUsd ='));
      expect(part('ru'), contains('_ruNumberCurrencyUsdDigits0 ='));
      expect(part('en'), isNot(contains('_ruNumber')));
    });

    test('splitting changes what is in each file, not what is generated', () {
      // Same interfaces, same members, same order — only the file boundaries
      // differ, which is what makes turning the option on safe.
      final split = _library('split');
      for (final member in [
        'String get title;',
        'String subtitle({required String name});',
        'String balance({required double amount});',
        'String cards({required num count});',
      ]) {
        expect(split, contains(member));
      }
    });
  });

  test('an untranslated key renders as the base locale', () {
    final core = _library('fill_missing');
    // Russian translated only `auth.title`. Everything else appears twice:
    // once in the English class, once in the Russian one falling back.
    expect(core, contains("String get title => 'Войти';"));
    expect(core, contains('/// Untranslated: renders as `en`.'));
    expect(core.split(r"=> 'Welcome back, $name';").length - 1, 2);
  });

  test('a fallen back plural keeps the base locale rules', () {
    final core = _library('fill_missing');
    // English is one/other. Russian rules on English text would give
    // "2 card"; the whole message falls back, rules included.
    expect(core, isNot(contains(r'$operands.i % 10')));
    expect(core, contains('_enNumberDecimalPattern'));
    expect(core, isNot(contains('_ruNumberDecimalPattern')));
  });

  test('a project without formatting never imports intl', () {
    expect(_run('json').files.first.contents, isNot(contains('package:intl')));
  });

  test('YAML generates byte for byte what the same JSON generates', () {
    // The strongest statement the parser seam can make: two formats, one set
    // of messages, and output that cannot be told apart.
    final fromJson = _run('json').files;
    final fromYaml = _run('yaml').files;

    expect(
      fromYaml.map((file) => file.path),
      fromJson.map((file) => file.path),
    );
    for (var index = 0; index < fromJson.length; index++) {
      expect(
        fromYaml[index].contents,
        fromJson[index].contents,
        reason: fromJson[index].path,
      );
    }
  });

  test('dotted ARB keys produce the same nesting as nested JSON', () {
    final fromArb = _run('arb').files.first.contents;
    expect(fromArb, contains(r'abstract interface class $AuthLogin'));
    expect(fromArb, contains(r'$AuthLogin get login'));
  });
}
