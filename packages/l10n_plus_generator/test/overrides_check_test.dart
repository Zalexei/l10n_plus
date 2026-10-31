@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `check-overrides`, one test per diagnostic it can report.
///
/// The feature's keystone: everything an override can get wrong is a wrong
/// string on a screen, which is precisely the class of failure this library
/// exists to move to build time. So each of these is a defect that would
/// otherwise ship, and the one worth reading twice is the branch — telling
/// `few` in Russian from `few` in English needs the CLDR tables the generator
/// compiles its conditions from, and nothing downstream of the build has them.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
runtime_overrides: true
flutter:
  enabled: false
''';

/// A project with one of everything an override can be checked against.
const Map<String, String> _project = {
  'en.json': '''
{
  "title": "Log in",
  "greeting": "Welcome back, {name}",
  "total": "Total: {amount, number, currency:USD}",
  "items": "{count, plural, =0{Nothing} one{# item} other{# items}}",
  "summary": "You have {count, plural, one{# card} other{# cards}} linked",
  "rank": "{place, selectordinal, one{#st} two{#nd} few{#rd} other{#th}} place",
  "tone": "{t, select, formal{Good day} other{Hi}}",
  "sparse": "{count, plural, other{# things}}",
  "terms(rich)": "Read the <link>terms</link>"
}
''',
  'ru.json': '''
{
  "title": "Войти",
  "greeting": "С возвращением, {name}",
  "total": "Итого: {amount, number, currency:USD}",
  "items": "{count, plural, =0{Ничего} one{# товар} few{# товара} many{# товаров} other{# товара}}",
  "summary": "У вас привязано {count, plural, one{# карта} few{# карты} many{# карт} other{# карты}}",
  "rank": "{place, selectordinal, other{#-й}} место",
  "tone": "{t, select, formal{Добрый день} other{Привет}}",
  "sparse": "{count, plural, other{# штук}}",
  "terms(rich)": "Прочитайте <link>условия</link>"
}
''',
};

/// The overridable surface of [locale] in [project].
String _fingerprint(String locale, {Map<String, String> project = _project}) {
  final result = runGenerator(project, configYaml: _config);
  return OverrideFingerprint.of(result.overrides.forLocale(locale)!);
}

/// Reports of checking [bundle] against [_project].
///
/// [requireFingerprint] is off here, so each test below reads as the one
/// mistake it is about. The fingerprint is a statement about the build rather
/// than about the bundle's contents, and it has a group of its own.
List<Diagnostic> _check(
  String bundle, {
  String path = 'overrides_en.json',
  Map<String, String> project = _project,
  bool requireFingerprint = false,
}) {
  final result = runGenerator(project, configYaml: _config);
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));

  final diagnostics = DiagnosticCollector();
  final read = OverrideBundle.read(
    content: bundle,
    uri: Uri.file('/tmp/$path'),
    path: path,
    diagnostics: diagnostics,
  );
  if (read != null) {
    OverrideChecker.check(
      bundle: read,
      catalog: result.overrides,
      diagnostics: diagnostics,
      requireFingerprint: requireFingerprint,
    );
  }
  return diagnostics.diagnostics;
}

List<String> _codes(String bundle, {String path = 'overrides_en.json'}) =>
    _check(bundle, path: path).map((d) => d.code).toList(growable: false);

Diagnostic _only(String bundle, {String path = 'overrides_en.json'}) {
  final reports = _check(bundle, path: path);
  expect(reports, hasLength(1), reason: reports.join('\n'));
  return reports.single;
}

void main() {
  test('a bundle that is right says nothing', () {
    expect(
      _codes('''
{
  "@@locale": "en",
  "title": "Sign in",
  "greeting": "Hello again, {name}",
  "total": "Charged {amount}",
  "items": {"=0": "Nothing yet", "one": "# thing", "other": "# things"},
  "summary": "You now have {#0}",
  "rank": {"0/one": "#st place", "0/two": "#nd place"},
  "tone": {"formal": "Good morning", "other": "Hey"}
}
'''),
      isEmpty,
    );
  });

  group('the locale', () {
    test('comes from the file name when the bundle does not say', () {
      expect(
        _codes('{"title": "Sign in"}', path: 'overrides_ru.json'),
        isEmpty,
      );
      expect(_codes('{"title": "Sign in"}', path: 'ru.json'), isEmpty);
    });

    test('unstateable is an error, not a default', () {
      // The locale decides which branches exist, so guessing it wrong would
      // make every other answer here wrong too.
      final diagnostic = _only('{"title": "Sign in"}', path: 'bundle.json');
      expect(diagnostic.code, 'unknown_override_locale');
      expect(diagnostic.details, contains('@@locale'));
      expect(diagnostic.details, contains('overrides_en.json'));
    });

    test(
      'a locale the project does not generate is named with the ones it does',
      () {
        final diagnostic = _only('{"@@locale": "fr", "title": "Se connecter"}');
        expect(diagnostic.code, 'unknown_override_locale');
        expect(diagnostic.message, contains('"fr"'));
        expect(diagnostic.details, contains('en'));
        expect(diagnostic.details, contains('ru'));
      },
    );

    test('something that is not a locale at all', () {
      expect(_only('{"@@locale": "english"}').code, 'unknown_override_locale');
      expect(_only('{"@@locale": 7}').code, 'unknown_override_locale');
    });
  });

  group('the bundle itself', () {
    test('unparseable JSON', () {
      final diagnostic = _only('{"title": ');
      expect(diagnostic.code, 'invalid_override');
      expect(diagnostic.span, isNotNull);
    });

    test('a root that is not an object, with the shape spelled out', () {
      final diagnostic = _only('["title"]');
      expect(diagnostic.code, 'invalid_override');
      expect(diagnostic.details, contains('"@@locale": "en"'));
    });

    test('a value that is neither text nor branches', () {
      final diagnostic = _only('{"@@locale": "en", "title": 42}');
      expect(diagnostic.code, 'invalid_override');
      expect(diagnostic.message, contains('string'));
      expect(diagnostic.details, contains('a number'));
    });

    test('a branch holding something other than its text', () {
      final diagnostic = _only(
        '{"@@locale": "en", "items": {"one": {"nested": "no"}}}',
      );
      expect(diagnostic.code, 'invalid_override');
      expect(diagnostic.translationKey, 'items');
    });

    test('ARB style metadata is carried without complaint', () {
      // A bundle that went through a tool may still have `@key` entries.
      expect(
        _codes('{"@@locale": "en", "title": "Sign in", "@title": {}}'),
        isEmpty,
      );
    });
  });

  group('the key', () {
    test('a key the project does not define, with the nearest one offered', () {
      final diagnostic = _only('{"@@locale": "en", "greting": "Hello"}');
      expect(diagnostic.code, 'unknown_override_key');
      expect(diagnostic.details, contains('Did you mean "greeting"?'));
    });

    test('a key nothing resembles gets the rule instead of a guess', () {
      final diagnostic = _only('{"@@locale": "en", "some.other.thing": "x"}');
      expect(diagnostic.code, 'unknown_override_key');
      expect(diagnostic.details, isNot(contains('Did you mean')));
      expect(diagnostic.details, contains('release'));
    });

    test('a rich message is refused, not silently ignored', () {
      // The tags are the signature: one builder per tag, checked by the
      // compiler. There is nothing here for a text to be the text of.
      // Either spelling lands on the same answer: the key carries `(rich)`
      // and a bundle naturally writes the member name without it.
      for (final key in ['terms', 'terms(rich)']) {
        final diagnostic = _only('{"@@locale": "en", "$key": "Read this"}');
        expect(diagnostic.code, 'override_rich_unsupported', reason: key);
        expect(diagnostic.details, contains('structure, not text'));
      }
    });
  });

  group('the shape', () {
    test('a message chosen per branch needs one text per branch', () {
      final diagnostic = _only('{"@@locale": "en", "items": "Some things"}');
      expect(diagnostic.code, 'override_needs_branches');
      expect(diagnostic.details, contains('=0'));
      expect(diagnostic.details, contains('one'));
      expect(diagnostic.details, contains('other'));
    });

    test('a message with one form takes no branches', () {
      final diagnostic = _only(
        '{"@@locale": "en", "title": {"one": "Sign in"}}',
      );
      expect(diagnostic.code, 'override_takes_no_branches');
      expect(diagnostic.details, contains('"title": "…"'));
    });

    test('a nested choice accepts either shape, because it is both', () {
      // "You have {plural} linked" is a text with a token, and the plural
      // inside it is a choice with branches.
      expect(_codes('{"@@locale": "en", "summary": "Now: {#0}"}'), isEmpty);
      expect(
        _codes('{"@@locale": "en", "summary": {"0/one": "# card"}}'),
        isEmpty,
      );
    });
  });

  group('the branch', () {
    test('a category this locale cannot produce, named as such', () {
      // The check nobody downstream of the build can make.
      final diagnostic = _only('{"@@locale": "en", "items": {"few": "x"}}');
      expect(diagnostic.code, 'unknown_override_branch');
      expect(
        diagnostic.details,
        contains('gives "en" the categories one, other here'),
      );
      expect(diagnostic.details, contains('=0'));
    });

    test('the same name is right in Russian', () {
      expect(
        _codes(
          '{"@@locale": "ru", "items": {"few": "# товара"}}',
          path: 'overrides_ru.json',
        ),
        isEmpty,
      );
    });

    test('cardinal and ordinal are different tables for one language', () {
      // English counts with one/other and ranks with one/two/few/other, so
      // `two` is a mistake in the first and correct in the second.
      expect(
        _only('{"@@locale": "en", "items": {"two": "x"}}').code,
        'unknown_override_branch',
      );
      expect(_codes('{"@@locale": "en", "rank": {"0/two": "#nd"}}'), isEmpty);
    });

    test('a category the locale has but the message left out', () {
      // `sparse` declares `other` alone, so `one` is a real Russian category
      // and still not a branch of this message. No CLDR sentence here: what
      // is missing is the branch, not the language — and the fix is a
      // release, because a branch is a new condition in compiled code.
      final diagnostic = _check(
        '{"@@locale": "ru", "sparse": {"one": "# штука"}}',
        path: 'overrides_ru.json',
      ).single;
      expect(diagnostic.code, 'unknown_override_branch');
      expect(diagnostic.details, isNot(contains('CLDR')));
      expect(diagnostic.details, contains('other'));
    });

    test('an ordinal table can be narrower than the cardinal one', () {
      // Russian ranks everything with `other`, and counts with four
      // categories. So `one` is right for `items` and wrong for `rank`, in
      // the same locale, and only the tables know it.
      expect(
        _codes(
          '{"@@locale": "ru", "items": {"one": "# товар"}}',
          path: 'overrides_ru.json',
        ),
        isEmpty,
      );
      final diagnostic = _check(
        '{"@@locale": "ru", "rank": {"0/one": "#-й"}}',
        path: 'overrides_ru.json',
      ).single;
      expect(diagnostic.code, 'unknown_override_branch');
      expect(
        diagnostic.details,
        contains('gives "ru" the categories other here'),
      );
    });

    test('a select case the message does not have', () {
      final diagnostic = _only('{"@@locale": "en", "tone": {"casual": "Yo"}}');
      expect(diagnostic.code, 'unknown_override_branch');
      expect(diagnostic.details, contains('formal'));
    });

    test('a nested branch written without its number', () {
      final diagnostic = _only('{"@@locale": "en", "summary": {"one": "#"}}');
      expect(diagnostic.code, 'unknown_override_branch');
      expect(diagnostic.details, contains('0/one'));
    });

    test('the wrong number for a nested branch explains the numbering', () {
      final diagnostic = _only('{"@@locale": "en", "summary": {"1/one": "#"}}');
      expect(diagnostic.code, 'unknown_override_branch');
      expect(diagnostic.details, contains('counted from zero'));
    });
  });

  group('the text', () {
    test('a placeholder the message does not take', () {
      final diagnostic = _only(
        '{"@@locale": "en", "greeting": "Hello, {nmae}"}',
      );
      expect(diagnostic.code, 'unknown_override_placeholder');
      expect(diagnostic.details, contains('"{name}"'));
      expect(diagnostic.details, contains('release'));
      // The caret lands on the token, not on the whole string.
      expect(diagnostic.span!.text, '{nmae}');
    });

    test('a select argument is not a placeholder', () {
      // Its value is a generated enum, so substituting it would print
      // `ToneT.formal`. The branch name is how a select is addressed.
      expect(
        _only('{"@@locale": "en", "tone": {"formal": "Day, {t}"}}').code,
        'unknown_override_placeholder',
      );
    });

    test('text that merely looks like a placeholder is text', () {
      expect(
        _codes('{"@@locale": "en", "title": "Log in {not a token}"}'),
        isEmpty,
      );
    });

    test('a number sign in a message with no count', () {
      final diagnostic = _only('{"@@locale": "en", "title": "# left"}');
      expect(diagnostic.code, 'override_unexpected_number_sign');
      expect(diagnostic.details, contains('print as a hash'));
      expect(diagnostic.span!.text, '#');
    });

    test('a number sign is reported once, however often it appears', () {
      expect(_codes('{"@@locale": "en", "title": "# of # of #"}'), [
        'override_unexpected_number_sign',
      ]);
    });

    test('a number sign is fine wherever a count is in scope', () {
      expect(_codes('{"@@locale": "en", "items": {"one": "just #"}}'), isEmpty);
      // Including the frame of a nested plural? No: the frame has no count.
      expect(_codes('{"@@locale": "en", "summary": "# linked"}'), [
        'override_unexpected_number_sign',
      ]);
    });

    test('ICU in an override is refused, with the reason', () {
      final diagnostic = _only(
        '{"@@locale": "en", "items": {"one": '
        '"{count, plural, one{# item} other{# items}}"}}',
      );
      expect(diagnostic.code, 'override_contains_icu');
      expect(diagnostic.details, contains('222 languages'));
      expect(diagnostic.details, contains('package:intl'));
    });

    test('a format written into an override is the same mistake', () {
      final diagnostic = _only(
        '{"@@locale": "en", "total": "Total: {amount, number, currency:USD}"}',
      );
      expect(diagnostic.code, 'override_contains_icu');
    });

    test('ICU is reported once rather than as a shower of unknown tokens', () {
      expect(
        _codes(
          '{"@@locale": "en", "greeting": '
          '"{gender, select, male{Mr {name}} other{{name}}}"}',
        ),
        ['override_contains_icu'],
      );
    });

    test('an already formatted token is exactly what the message takes', () {
      expect(
        _codes('{"@@locale": "en", "total": "Charged {amount}"}'),
        isEmpty,
      );
    });
  });

  test('every problem in a bundle is reported in one run', () {
    // A bundle comes back from one round trip; a report naming one of five
    // mistakes costs five round trips.
    expect(
      _codes('''
{
  "@@locale": "en",
  "greting": "Hello",
  "greeting": "Hello, {nmae}",
  "items": {"few": "x"},
  "title": "# left",
  "terms": "Read the terms"
}
'''),
      [
        'unknown_override_key',
        'unknown_override_placeholder',
        'unknown_override_branch',
        'override_unexpected_number_sign',
        'override_rich_unsupported',
      ],
    );
  });

  test('every code it reports is a registered diagnostic code', () {
    // `ignore_diagnostics` has to be able to tell a real code from a typo,
    // and an override problem is never a warning: it is a wrong string.
    for (final code in [
      'invalid_override',
      'unknown_override_locale',
      'unknown_override_key',
      'unknown_override_branch',
      'unknown_override_placeholder',
      'override_needs_branches',
      'override_takes_no_branches',
      'override_unexpected_number_sign',
      'override_contains_icu',
      'override_rich_unsupported',
    ]) {
      expect(DiagnosticCodes.alwaysErrors, contains(code), reason: code);
    }
  });

  group('the fingerprint', () {
    const plain = {
      'en.json': '{"m": "You have {a, plural, one{# card} other{# cards}}"}',
    };

    test('a bundle that states none is refused, with the one to write', () {
      final report = _check(
        '{"@@locale": "en", "title": "Sign in"}',
        requireFingerprint: true,
      );
      expect(report.map((d) => d.code), ['missing_override_fingerprint']);
      expect(report.single.details, contains(_fingerprint('en')));
    });

    test('a bundle that states this build passes', () {
      expect(
        _check(
          '{"@@fingerprint": "${_fingerprint('en')}", '
          '"@@locale": "en", "title": "Sign in"}',
          requireFingerprint: true,
        ),
        isEmpty,
      );
    });

    test('a bundle that states another build is refused', () {
      final report = _check(
        '{"@@fingerprint": "0123456789abcdef", '
        '"@@locale": "en", "title": "Sign in"}',
        requireFingerprint: true,
      );
      expect(report.map((d) => d.code), ['override_fingerprint_mismatch']);
      expect(report.single.details, contains('0123456789abcdef'));
      expect(report.single.details, contains(_fingerprint('en')));
    });

    test('an inserted choice renumbers the slots, and only this says so', () {
      // The defect the fingerprint exists for. A nested choice is addressed
      // by position, so inserting one ahead of it moves every name along —
      // and every name the old bundle uses still exists, so every other
      // check in this file still passes against the new build while the text
      // of one choice has become the text of another.
      const inserted = {
        'en.json':
            '{"m": "You have {b, plural, one{# bag} other{# bags}} and '
            '{a, plural, one{# card} other{# cards}}"}',
      };
      const bundle =
          '{"@@locale": "en", "m": {"0/one": "# thing", "0/other": "# things"}}';

      expect(_check(bundle, project: plain), isEmpty);
      expect(_check(bundle, project: inserted), isEmpty);
      expect(
        _fingerprint('en', project: plain),
        isNot(_fingerprint('en', project: inserted)),
      );
    });

    test('swapping two choices of the same shape changes it', () {
      // Nothing about the slots differs here: both messages have 0/one,
      // 0/other, 1/one and 1/other, and the same tokens around them. What
      // differs is which argument each choice selects on, which is why the
      // canonical form records it.
      const before = {
        'en.json':
            '{"m": "{a, plural, one{# x} other{# xs}} and '
            '{b, plural, one{# y} other{# ys}}"}',
      };
      const after = {
        'en.json':
            '{"m": "{b, plural, one{# y} other{# ys}} and '
            '{a, plural, one{# x} other{# xs}}"}',
      };
      expect(
        _fingerprint('en', project: before),
        isNot(_fingerprint('en', project: after)),
      );
    });

    test('a reword leaves it alone, which is the point of the feature', () {
      expect(
        _fingerprint('en', project: const {'en.json': '{"title": "Log in"}'}),
        _fingerprint('en', project: const {'en.json': '{"title": "Sign in"}'}),
      );
    });

    test('so does reordering the messages', () {
      expect(
        _fingerprint('en', project: const {'en.json': '{"a": "A", "b": "B"}'}),
        _fingerprint('en', project: const {'en.json': '{"b": "B", "a": "A"}'}),
      );
    });

    test('so does adding a rich message, which nothing can override', () {
      expect(
        _fingerprint('en', project: const {'en.json': '{"a": "A"}'}),
        _fingerprint(
          'en',
          project: const {'en.json': '{"a": "A", "t(rich)": "<b>x</b>"}'},
        ),
      );
    });

    test('adding a plain key changes it, coarsely and on purpose', () {
      // One value per locale, so a release that adds a message invalidates
      // that locale's bundles even though their entries are all still right.
      // The cost is one --stamp in a release that had to re-check its
      // bundles anyway; the alternative is a hash beside every string in a
      // file a translator's tooling carries.
      expect(
        _fingerprint('en', project: const {'en.json': '{"a": "A"}'}),
        isNot(
          _fingerprint(
            'en',
            project: const {'en.json': '{"a": "A", "b": "B"}'},
          ),
        ),
      );
    });

    test('two locales of the same shape still differ', () {
      // So a bundle cannot be installed for a locale it was not checked
      // against: en and en_GB usually do have the same messages.
      const two = {
        'en.json': '{"title": "Log in"}',
        'ru.json': '{"title": "Войти"}',
      };
      expect(
        _fingerprint('en', project: two),
        isNot(_fingerprint('ru', project: two)),
      );
    });

    test('the canonical form carries no text, so it can be read', () {
      // Printed by nothing in the pipeline, and public for the test that
      // needs to say *how* two surfaces differ rather than that they do.
      final result = runGenerator(plain, configYaml: _config);
      final canonical = OverrideFingerprint.canonical(
        result.overrides.forLocale('en')!,
      );
      expect(canonical, contains(OverrideFingerprint.version));
      expect(canonical, contains('Km'));
      expect(canonical, contains('C0|a:cardinal'));
      expect(canonical, isNot(contains('You have')));
    });

    test('both codes are errors, like every other override code', () {
      for (final code in [
        'missing_override_fingerprint',
        'override_fingerprint_mismatch',
      ]) {
        expect(DiagnosticCodes.alwaysErrors, contains(code), reason: code);
      }
    });
  });

  test('a project with the option off emits no slots to check against', () {
    final off = runGenerator(
      _project,
      configYaml: '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''',
    );
    expect(errorsOf(off), isEmpty);
    expect(off.overrides.isEmpty, isTrue);
  });
}
