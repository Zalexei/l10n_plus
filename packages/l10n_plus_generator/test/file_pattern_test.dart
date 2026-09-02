import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_generator/src/source/file_pattern.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

String _config(String? pattern) =>
    '''
base_locale: en
fallback_locale: en
${pattern == null ? '' : 'file_pattern: "$pattern"'}
flutter:
  enabled: false
''';

String? _tag(String pattern, String path) =>
    FilePattern.parse(pattern)!.match(path)?.locale.toFileTag();

String? _namespace(String pattern, String path) =>
    FilePattern.parse(pattern)!.match(path)?.namespace;

void main() {
  group('pattern matching', () {
    test('the default is the bare locale tag', () {
      expect(_tag('{locale}', 'en'), 'en');
      expect(_tag('{locale}', 'pt_BR'), 'pt_BR');
      expect(_tag('{locale}', 'wallet/en'), isNull);
    });

    test('a literal prefix resolves the app_en ambiguity', () {
      // Without the pattern this parses as the locale `app_EN`.
      expect(_tag('app_{locale}', 'app_en'), 'en');
      expect(_tag('app_{locale}', 'en'), isNull);
    });

    test('* matches one segment and contributes nothing', () {
      expect(_tag('*/{locale}', 'wallet/en'), 'en');
      expect(_tag('{locale}/*', 'en/wallet'), 'en');
      expect(_tag('*_{locale}', 'wallet_en'), 'en');
      expect(_tag('*/{locale}', 'wallet/settings/en'), isNull);
    });

    test('** crosses directories', () {
      expect(_tag('**/{locale}', 'wallet/settings/en'), 'en');
      expect(_tag('**/{locale}', 'wallet/en'), 'en');
    });

    test('a capture that is not a locale does not match', () {
      expect(_tag('{locale}', 'readme'), isNull);
      expect(_tag('{locale}', ''), isNull);
    });

    test('matching is anchored at both ends', () {
      expect(_tag('{locale}', 'x/en'), isNull);
      expect(_tag('app_{locale}', 'my_app_en'), isNull);
    });
  });

  group('pattern validation', () {
    String? reason(String pattern) {
      String? captured;
      final parsed = FilePattern.parse(
        pattern,
        problem: (message) => captured = message,
      );
      expect(parsed, isNull, reason: 'expected $pattern to be rejected');
      return captured;
    }

    test('{locale} is required', () {
      expect(reason('*'), contains('must contain "{locale}"'));
    });

    test('{locale} may appear only once', () {
      expect(reason('{locale}/{locale}'), contains('only once'));
    });

    test('an unknown placeholder is named', () {
      expect(
        reason('{feature}/{locale}'),
        allOf(contains('{feature}'), contains('"*"')),
      );
    });

    test('{namespace} may appear only once', () {
      expect(
        reason('{namespace}/{namespace}_{locale}'),
        contains('"{namespace}" only once'),
      );
    });

    test('a pattern is relative to the input directory', () {
      expect(reason('/{locale}'), contains('relative'));
      expect(reason('../{locale}'), contains('relative'));
    });

    test('a bad pattern is a configuration error, with examples', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
      }, configYaml: _config('{feature}/{locale}'));

      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'invalid_config');
      expect(diagnostic.details, contains('*/{locale}'));
    });
  });

  group('several files per locale', () {
    test('a directory per locale merges into one API', () {
      final result = runGenerator({
        'en/auth.json': '{"auth": {"title": "Log in"}}',
        'en/wallet.json': '{"wallet": {"balance": "Balance"}}',
        'ru/auth.json': '{"auth": {"title": "Войти"}}',
        'ru/wallet.json': '{"wallet": {"balance": "Баланс"}}',
      }, configYaml: _config('{locale}/*'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains(r'$Auth get auth'));
      expect(source, contains(r'$Wallet get wallet'));
      expect(source, contains("String get title => 'Log in';"));
      expect(source, contains("String get balance => 'Баланс';"));
    });

    test('a directory per feature works from the same mechanism', () {
      final result = runGenerator({
        'auth/en.json': '{"auth": {"title": "Log in"}}',
        'auth/ru.json': '{"auth": {"title": "Войти"}}',
        'wallet/en.json': '{"wallet": {"balance": "Balance"}}',
        'wallet/ru.json': '{"wallet": {"balance": "Баланс"}}',
      }, configYaml: _config('*/{locale}'));

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains(r'$Wallet get wallet'));
    });

    test('groups merge across files', () {
      final result = runGenerator({
        'en/one.json': '{"wallet": {"a": "A"}}',
        'en/two.json': '{"wallet": {"b": "B"}}',
      }, configYaml: _config('{locale}/*'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("String get a => 'A';"));
      expect(source, contains("String get b => 'B';"));
      // One namespace, not two.
      expect(source.split(r'abstract interface class $Wallet').length - 1, 1);
    });

    test('a leaf defined twice is an error naming both files', () {
      final result = runGenerator({
        'en/one.json': '{"wallet": {"a": "A"}}',
        'en/two.json': '{"wallet": {"a": "Also A"}}',
      }, configYaml: _config('{locale}/*'));

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'duplicate_key');
      expect(diagnostic.translationKey, 'wallet.a');
      expect(diagnostic.details, contains('one.json'));
      expect(diagnostic.details, contains('merged'));
    });

    test('a key that is a group in one file and a message in another', () {
      final result = runGenerator({
        'en/one.json': '{"wallet": {"a": "A"}}',
        'en/two.json': '{"wallet": "Wallet"}',
      }, configYaml: _config('{locale}/*'));

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'conflicting_key_kind');
      expect(diagnostic.translationKey, 'wallet');
      expect(diagnostic.details, contains('a group'));
      expect(diagnostic.details, contains('a message'));
    });

    test('a locale missing a file is missing its keys, not silent', () {
      final result = runGenerator({
        'en/auth.json': '{"auth": {"title": "Log in"}}',
        'en/wallet.json': '{"wallet": {"balance": "Balance"}}',
        'ru/auth.json': '{"auth": {"title": "Войти"}}',
      }, configYaml: _config('{locale}/*'));

      expect(errorsOf(result), contains('missing_key'));
    });

    test('output does not depend on the order files are found in', () {
      Map<String, String> files() => {
        'en/z.json': '{"z": "Z"}',
        'en/a.json': '{"a": "A"}',
        'en/m.json': '{"m": "M"}',
      };
      final first = runGenerator(files(), configYaml: _config('{locale}/*'));
      final second = runGenerator(files(), configYaml: _config('{locale}/*'));
      expect(first.files.single.contents, second.files.single.contents);

      // Sorted by path, so `a` precedes `m` precedes `z` whatever the file
      // system reported.
      final source = first.files.single.contents;
      expect(
        source.indexOf('String get a'),
        lessThan(source.indexOf('String get m')),
      );
      expect(
        source.indexOf('String get m'),
        lessThan(source.indexOf('String get z')),
      );
    });
  });

  group('{namespace} from the file name', () {
    test('the captured text becomes the namespace', () {
      expect(_namespace('{namespace}_{locale}', 'auth_en'), 'auth');
      expect(_namespace('{namespace}/{locale}', 'wallet/en'), 'wallet');
      expect(_namespace('{locale}/{namespace}', 'en/wallet'), 'wallet');
      expect(_tag('{namespace}_{locale}', 'auth_en'), 'en');
    });

    test('a pattern without it captures no namespace', () {
      expect(_namespace('*_{locale}', 'auth_en'), isNull);
      expect(_namespace('{locale}', 'en'), isNull);
    });

    test('the file writes its keys without repeating the prefix', () {
      final result = runGenerator({
        'auth_en.json': '{"login": {"title": "Log in"}}',
        'wallet_en.json': '{"balance": "Balance"}',
        'auth_ru.json': '{"login": {"title": "Войти"}}',
        'wallet_ru.json': '{"balance": "Баланс"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains(r'$Auth get auth'));
      expect(source, contains(r'$AuthLogin get login'));
      expect(source, contains(r'$Wallet get wallet'));
      expect(source, contains("String get title => 'Log in';"));
      expect(source, contains("String get balance => 'Баланс';"));
    });

    test('it produces exactly what writing the prefix inside produces', () {
      // The two layouts are the same project said two ways, so the generated
      // API must not be able to tell them apart.
      final fromName = runGenerator({
        'auth_en.json': '{"login": {"title": "Log in"}}',
        'wallet_en.json': '{"balance": "Balance: {amount, number}"}',
      }, configYaml: _config('{namespace}_{locale}'));

      final fromInside = runGenerator({
        'auth_en.json': '{"auth": {"login": {"title": "Log in"}}}',
        'wallet_en.json':
            '{"wallet": {"balance": "Balance: {amount, number}"}}',
      }, configYaml: _config('*_{locale}'));

      expect(errorsOf(fromName), isEmpty);
      expect(errorsOf(fromInside), isEmpty);
      expect(fromName.files.single.contents, fromInside.files.single.contents);
    });

    test('dots in the name nest', () {
      final result = runGenerator({
        'wallet.settings_en.json': '{"title": "Settings"}',
        'wallet.settings_ru.json': '{"title": "Настройки"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains(r'$Wallet get wallet'));
      expect(source, contains(r'$WalletSettings get settings'));
      expect(source, contains("String get title => 'Settings';"));
    });

    test('two files sharing a namespace merge under it', () {
      final result = runGenerator({
        'wallet_en.json': '{"a": "A"}',
        'wallet.cards_en.json': '{"b": "B"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("String get a => 'A';"));
      expect(source, contains(r'$WalletCards get cards'));
      expect(source.split(r'abstract interface class $Wallet ').length - 1, 1);
    });

    test('the same key in two files of one namespace still collides', () {
      final result = runGenerator({
        'wallet_en.json': '{"a": "A"}',
        'wallet.x_en.json': '{"a": "A"}',
      }, configYaml: _config('{namespace}_{locale}'));

      // Different namespaces, so no collision.
      expect(errorsOf(result), isEmpty);
    });

    test('a namespace is normalized like any other key', () {
      final result = runGenerator({
        'wallet-cards_en.json': '{"a": "A"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), isEmpty);
      expect(
        result.files.single.contents,
        contains(r'$WalletCards get walletCards'),
      );
    });

    test('a namespace that cannot become a Dart name is reported', () {
      final result = runGenerator({
        '!!!_en.json': '{"a": "A"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), contains('invalid_key'));
    });

    test('paths still decide the locale, so a file may be missing', () {
      final result = runGenerator({
        'auth_en.json': '{"a": "A"}',
        'wallet_en.json': '{"b": "B"}',
        'auth_ru.json': '{"a": "А"}',
      }, configYaml: _config('{namespace}_{locale}'));

      expect(errorsOf(result), contains('missing_key'));
    });

    test('ARB keeps working the other way, with *', () {
      // A TMS export already has fully qualified keys; prefixing them would
      // produce `auth.auth.login.title`.
      final result = runGenerator({
        'auth_en.arb': '{"@@locale": "en", "auth.login.title": "Log in"}',
        'wallet_en.arb': '{"@@locale": "en", "wallet.balance": "Balance"}',
      }, configYaml: _config('*_{locale}'));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains(r'$AuthLogin get login'));
      expect(source, isNot(contains(r'$AuthAuth')));
    });
  });

  group('locale disagreements', () {
    test('a configured pattern that disagrees with @@locale is reported', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'de.arb': '{"@@locale": "fr", "a": "A"}',
      }, configYaml: _config('{locale}'));

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'locale_pattern_mismatch',
      );
      expect(diagnostic.message, contains('fr'));
      expect(diagnostic.message, contains('de'));
    });

    test('the default pattern claims nothing, so app_en.arb stays quiet', () {
      // Under `{locale}` the path parses as the locale `app_EN`; `@@locale`
      // corrects it, and that is how a gen_l10n bundle is meant to work.
      final result = runGenerator({
        'app_en.arb': '{"@@locale": "en", "a": "A"}',
      }, configYaml: _config(null));

      expect(codesOf(result), isEmpty);
      expect(result.files.single.contents, contains("String get a => 'A';"));
    });

    test('a file matching nothing is skipped with the pattern named', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'notes.json': '{"a": "A"}',
      }, configYaml: _config('{locale}'));

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'unrecognized_file_name',
      );
      expect(diagnostic.message, contains('notes.json'));
      expect(diagnostic.details, contains('{locale}'));
    });
  });

  group('when nothing matched the base locale', () {
    test('the files are named, with what each parsed as', () {
      final result = runGenerator({
        'app_en.json': '{"a": "A"}',
      }, configYaml: _config(null));

      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_base_locale',
      );
      expect(diagnostic.details, contains('app_en.json -> app_EN'));
    });

    test('it works out the pattern that would have matched', () {
      // The trap the whole feature exists for: `app_en` is itself a valid
      // tag, so the file silently becomes the locale `app_EN`.
      final result = runGenerator({
        'app_en.json': '{"a": "A"}',
      }, configYaml: _config(null));

      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_base_locale',
      );
      expect(diagnostic.details, contains('file_pattern: "app_{locale}"'));
    });

    test('a name that is no locale at all is skipped, not misread', () {
      // `app_en` parses as a locale and so reaches missing_base_locale;
      // `en_strings` does not parse at all and is skipped before that, with
      // the pattern in force named.
      final result = runGenerator({
        'en_strings.json': '{"a": "A"}',
      }, configYaml: _config(null));

      final skipped = result.diagnostics.firstWhere(
        (d) => d.code == 'unrecognized_file_name',
      );
      expect(skipped.message, contains('en_strings.json'));
      expect(skipped.details, contains('file_pattern'));
    });

    test('with nothing to suggest it still says what to do', () {
      final result = runGenerator({
        'de.json': '{"a": "A"}',
      }, configYaml: _config(null));

      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_base_locale',
      );
      expect(diagnostic.details, contains('de.json -> de'));
      expect(diagnostic.details, contains('file_pattern'));
      expect(diagnostic.details, isNot(contains('is the locale')));
    });
  });

  test('the parsed pattern round trips its source', () {
    expect(FilePattern.parse('*/{locale}')!.toString(), '*/{locale}');
    expect(FilePattern.fallback.toString(), FilePattern.defaultSource);
    expect(FilePattern.fallback.match('en')!.locale, const L10nLocale('en'));
    expect(FilePattern.fallback.match('en')!.namespace, isNull);
  });
}
