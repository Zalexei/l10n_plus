@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// The `runtime_overrides` fixture, generated and compared against its
/// goldens.
///
/// The translations are the `json` fixture's, plus one formatted message, and
/// the configuration differs by one line. So the two goldens are a diff of
/// what the option costs, and `codegen_golden_test.dart` keeping the `json`
/// golden unchanged is the other half of the claim: off, not a byte moves.
///
/// The goldens are analyzed like every other one, and executed by
/// `overrides_runtime_test.dart` — reading the source proves the lookup was
/// written, running it proves the right branch is consulted.
///
/// Set `UPDATE_GOLDENS=1` to rewrite the expected files.
bool get _updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

final String _packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

GenerationResult _run() {
  final root = p.join(_packageRoot, 'test/fixtures/overrides');
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

String _file(GenerationResult result, String name) =>
    result.files.firstWhere((file) => p.basename(file.path) == name).contents;

void main() {
  test('matches its goldens', () {
    final result = _run();
    final goldenDir = p.join(_packageRoot, 'test/goldens/overrides');

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
      _run().files.map((f) => f.contents),
      _run().files.map((f) => f.contents),
    );
  });

  group('the generated lookups', () {
    late String core;

    /// The same source with every run of whitespace collapsed.
    ///
    /// `dart_style` decides where a line breaks, and it breaks a lookup with
    /// three arguments differently from one with two. Asserting on the shape
    /// rather than on the wrapping keeps these tests about the emitter.
    late String flat;

    setUpAll(() {
      core = _file(_run(), 'app_localizations.g.dart');
      flat = core.replaceAll(RegExp(r'\s+'), ' ');
    });

    test('a message with one form is keyed by its key alone', () {
      expect(
        flat,
        contains(
          r"final $override = L10nOverrides.text(_$locale, "
          r"'auth.login.title'); if ($override != null) return $override; "
          r"return 'Log in';",
        ),
      );
    });

    test('an argument reaches the override already rendered', () {
      // The literal interpolates `$name`; the override is handed the same
      // value, under the name the translation file writes it with.
      expect(
        flat,
        contains(r"return L10nOverrides.fill($override, {'name': name});"),
      );
    });

    test('formatting stays compiled: the formatter renders the token', () {
      // `{amount, number, currency:USD}` is a `NumberFormat` in this file, and
      // the override is handed what it produced — not the number.
      expect(
        flat,
        contains(
          r"L10nOverrides.fill($override, "
          r"{ 'amount': _enNumberCurrencyUsd.format(amount), })",
        ),
      );
      expect(
        flat,
        contains(r"{ 'amount': _ruNumberCurrencyUsd.format(amount), })"),
      );
    });

    test('a plural is consulted per branch, by the branch it chose', () {
      for (final branch in ['=0', 'one', 'other']) {
        expect(
          flat,
          contains(
            "L10nOverrides.text( _\$locale, 'wallet.transactions', "
            "'$branch', )",
          ),
          reason: branch,
        );
      }
      // Russian has two more categories, and only Russian.
      expect(flat, contains("'wallet.transactions', 'few',"));
      expect(
        flat.split("'wallet.transactions', 'many',").length - 1,
        1,
        reason: 'many is a Russian category; English must not get a slot',
      );
    });

    test('rule selection stays compiled: the condition still decides', () {
      // The override sits *inside* the branch the compiled condition picked,
      // so no rule and no parser reached the runtime.
      expect(core, contains(r'final $operands = PluralOperands(count);'));
      expect(core, contains(r'$operands.i % 100 >= 11'));
      // No ICU is carried into the file: the only `plural,` left is the doc
      // comment that shows the author what they wrote.
      for (final line in core.split('\n')) {
        if (line.trimLeft().startsWith('///')) continue;
        expect(line, isNot(contains('plural,')));
        expect(line, isNot(contains('select,')));
      }
    });

    test('a select branches with a statement, still exhaustively', () {
      expect(core, contains('switch (gender) {'));
      expect(core, contains('case ProfileGreetingGender.male:'));
      expect(
        flat,
        contains(
          "L10nOverrides.text( _\$locale, 'profile.greeting', 'male', )",
        ),
      );
      // No `default:` and no trailing return: the enum is covered, so the
      // method provably returns.
      expect(core, isNot(contains('default:')));
    });

    test('a nested choice is numbered, and numbers its own branches', () {
      // `wallet.summary` is "You have {plural} linked": the plural's branches
      // live under `0/…`, and its rendering is the `{#0}` token of the text
      // around it, so both halves of the sentence can be reworded.
      expect(
        flat,
        contains(
          r"L10nOverrides.fill($override, "
          r"{ 'count': count.toString(), '#0': _summary$0(count: count), })",
        ),
      );
      for (final branch in ['0/one', '0/other']) {
        expect(
          flat,
          contains(
            "L10nOverrides.text(_\$locale, 'wallet.summary', '$branch')",
          ),
          reason: branch,
        );
      }
    });

    test('a number sign is a token wherever a count is in scope', () {
      // `wallet.likes` has `offset:1`, so `#` is the adjusted value in the
      // literal and has to be the same value here.
      expect(flat, contains(r"'#': $countOffset.toString(),"));
    });

    test('a select argument is not a token', () {
      // Its value is a generated enum, so `{gender}` would render
      // `ProfileGreetingGender.male`. The fill map carries `name` only.
      expect(core, isNot(contains("'gender': gender")));
      expect(core, isNot(contains("'sort':")));
    });

    test('a message of plain words needs no map at all', () {
      expect(
        flat,
        contains(
          "L10nOverrides.text( _\$locale, 'profile.sorting', 'values', ); "
          r"if ($override != null) return $override;",
        ),
      );
    });

    test('the locale is a constant per class, and classes stay const', () {
      expect(
        core,
        contains(r"static const L10nLocale _$locale = L10nLocale('en');"),
      );
      expect(core, contains(r'const $AuthLoginEn();'));
      expect(core, contains(r'$AuthLogin get login => const $AuthLoginEn();'));
    });

    test('the store is re-exported, so installing needs no second import', () {
      expect(
        core,
        contains(
          "export 'package:l10n_plus/l10n_plus.dart'\n"
          '    show L10nLocale, L10nOverrideMismatch, L10nOverrides;',
        ),
      );
    });
  });

  test('file_per_locale puts each locale constant in its own part', () {
    // The two options are independent, and the only thing that could couple
    // them is where the locale constant is declared. It is a static on the
    // implementation class, so it travels with the class.
    final result = runGenerator(
      {'en.json': '{"title": "Log in"}', 'ru.json': '{"title": "Войти"}'},
      configYaml: '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
runtime_overrides: true
file_per_locale: true
flutter:
  enabled: false
''',
    );
    expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));

    String part(String locale) => result.files
        .firstWhere((file) => file.path.endsWith('_$locale.g.dart'))
        .contents;
    expect(
      part('en'),
      contains(r"static const L10nLocale _$locale = L10nLocale('en');"),
    );
    expect(
      part('ru'),
      contains(r"static const L10nLocale _$locale = L10nLocale('ru');"),
    );
    expect(part('en'), isNot(contains("L10nLocale('ru')")));
    // And the schema is recorded for both locales, once each.
    expect(result.overrides.localeTags, ['en', 'ru']);
    for (final schema in result.overrides.locales) {
      expect(schema.messages.keys, ['title'], reason: schema.localeTag);
    }
  });

  test('no runtime key lookup came back in with the store', () {
    // The option adds a lookup *by the key the compiler wrote*, which is a
    // different thing from the string keyed map this library exists to avoid:
    // the member is still a method, its arguments are still typed, and a
    // misspelled key is still a compile error.
    //
    // `installOverrides` names a string keyed map once, as the parameter a
    // decoded bundle arrives in. That one is allowed and nothing else is: a
    // *stored* map of keys to text is the table a run time lookup would need,
    // and there is none.
    const parameter = 'void installOverrides(Map<String, Object> messages)';
    expect(_file(_run(), 'app_localizations.g.dart'), contains(parameter));
    for (final file in _run().files) {
      final rest = file.contents.replaceFirst(parameter, '');
      expect(rest, isNot(contains('Map<String')), reason: file.path);
      expect(file.contents, isNot(contains('jsonDecode')), reason: file.path);
      expect(file.contents, isNot(contains('dynamic ')), reason: file.path);
    }
  });

  test('a rich message has no slot, so nothing consults one', () {
    // The spans are structure rather than text, so there is nothing for an
    // override to be the text of. `override_rich_unsupported` is what a
    // bundle naming one gets; this fixture has no rich message at all, which
    // is what the absence of the span types says.
    expect(
      _file(_run(), 'app_localizations.g.dart'),
      isNot(contains('L10nSpan')),
    );
  });
}
