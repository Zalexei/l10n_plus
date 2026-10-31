@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/fixture.dart';

/// Rich messages: `"terms(rich)"` generates spans instead of a string, and
/// the Flutter glue generates a wrapper that cannot be called without a
/// builder for every tag.
///
/// What is emitted is asserted here; `rich_golden_test.dart` pins the exact
/// file, `rich_runtime_test.dart` runs it, and the widget test in
/// `l10n_plus_flutter` runs the wrapper. Reading the source proves the call
/// is there, not that it works.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

const String _configWithGlue = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: true
  context_extension: t
''';

const String _pubspec = '''
name: demo
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  l10n_plus: any
  l10n_plus_flutter: any
''';

/// One English file, and a Russian one that says the same thing.
Map<String, String> _project(String en, [String? ru]) => {
  'en.json': '{"legal": {$en}}',
  'ru.json': '{"legal": {${ru ?? en}}}',
};

String _generate(
  Map<String, String> translations, {
  String configYaml = _config,
}) {
  final result = runGenerator(translations, configYaml: configYaml);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format()).join('\n'),
  );
  return result.files.map((file) => file.contents).join('\n');
}

/// The glue file of a project generated with Flutter on.
String _glue(Map<String, String> translations) {
  final result = runGenerator(
    translations,
    configYaml: _configWithGlue,
    pubspec: _pubspec,
  );
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format()).join('\n'),
  );
  return result.files
      .firstWhere((file) => file.path.endsWith('_flutter.g.dart'))
      .contents;
}

/// [source] with every run of whitespace collapsed to one space.
///
/// Where a span list wraps is `dart_style`'s decision rather than something
/// a test should pin down — the goldens cover the exact layout, and these
/// tests are about what is emitted.
String _flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('a rich message generates spans', () {
    test('the suffix leaves the API, and the tags become spans', () {
      final source = _generate(
        _project('"terms(rich)": "Read the <link>terms</link> now"'),
      );

      // The key is `terms(rich)`; the member is `terms`.
      expect(source, contains('List<L10nSpan> get terms;'));
      expect(source, isNot(contains('(rich)')));
      expect(
        _flat(source),
        contains(
          "List<L10nSpan> get terms => const [ L10nTextSpan('Read the '), "
          "L10nTagSpan('link', [L10nTextSpan('terms')]), "
          "L10nTextSpan(' now'), ];",
        ),
      );
    });

    test('a message with no placeholder is a const list', () {
      // The same guarantee the plain string API gives: reading a message
      // allocates nothing. A const list is canonicalized, which
      // `rich_runtime_test` proves by identity.
      final source = _generate(_project('"terms(rich)": "<b>Bold</b>"'));
      expect(
        _flat(source),
        contains(
          "List<L10nSpan> get terms => const [ L10nTagSpan('b', "
          "[L10nTextSpan('Bold')]), ];",
        ),
      );
    });

    test('tags nest, and a tag may wrap a placeholder', () {
      final source = _generate(
        _project(
          '"hello(rich)": "Hi <b><i>{name}</i></b>, '
          'read <b>{count} notes</b>"',
        ),
      );

      expect(
        _flat(source),
        contains(
          'List<L10nSpan> hello({required String name, '
          'required String count})',
        ),
      );
      // A tag wrapping a placeholder interpolates it, exactly as the string
      // emitter would, and consecutive plain nodes are one span.
      expect(
        _flat(source),
        contains(
          "L10nTagSpan('b', [ L10nTagSpan('i', [L10nTextSpan(name)]), ])",
        ),
      );
      expect(source, contains("L10nTextSpan('\$count notes')"));
      // With an argument there is nothing to canonicalize, so no `const`.
      expect(_flat(source), isNot(contains('}) => const [')));
    });

    test('a declared format still applies inside a tag', () {
      // The rich path reuses the plain expression emitter, so formatting
      // inside a tag is not a second implementation.
      final source = _generate(
        _project(
          '"price(rich)": "Pay <b>{amount, number, currency:USD}</b> today"',
        ),
      );
      expect(
        _flat(source),
        contains(
          "L10nTagSpan('b', "
          '[L10nTextSpan(_enNumberCurrencyUsd.format(amount))])',
        ),
      );
    });

    test('the span types are exported, but only where there is a rich '
        'message', () {
      expect(
        _flat(_generate(_project('"terms(rich)": "<b>Hi</b>"'))),
        contains(
          "export 'package:l10n_plus/l10n_plus.dart' "
          'show L10nLocale, L10nSpan, L10nTagSpan, L10nTextSpan;',
        ),
      );
      expect(
        _flat(_generate(_project('"terms": "Hi"'))),
        contains("export 'package:l10n_plus/l10n_plus.dart' show L10nLocale;"),
      );
    });

    test('a message containing "<" is untouched without the suffix', () {
      // The reason the feature is opt-in: a project that has been shipping
      // "<Ctrl>" for years must keep shipping it.
      final source = _generate(_project('"tip": "Use <Ctrl> to select"'));
      expect(source, contains("String get tip => 'Use <Ctrl> to select';"));
    });

    test('a locale may translate the text around the tags freely', () {
      final source = _generate(
        _project(
          '"terms(rich)": "Read the <link>terms</link> now"',
          '"terms(rich)": "Сейчас прочтите <link>условия</link>"',
        ),
      );
      expect(source, contains("L10nTextSpan('Сейчас прочтите ')"));
      expect(
        source,
        contains("L10nTagSpan('link', [L10nTextSpan('условия')])"),
      );
    });
  });

  group('the Flutter glue requires one builder per tag', () {
    test('the wrapper takes the message arguments and the tag builders', () {
      final glue = _glue(
        _project(
          '"terms(rich)": "Hi {name}, read the <link>terms</link> '
          'and <b>rules</b>"',
        ),
      );

      expect(glue, contains(r'extension $LegalRichText on $Legal {'));
      expect(
        _flat(glue),
        contains(
          'TextSpan termsRich({ required String name, '
          'required L10nSpanBuilder link, required L10nSpanBuilder b, '
          'TextStyle? style, }) => l10nTextSpan( terms(name: name), '
          "tags: {'link': link, 'b': b}, style: style, );",
        ),
      );
    });

    test('a getter message needs no arguments to be wrapped', () {
      final glue = _glue(_project('"terms(rich)": "The <link>terms</link>"'));
      expect(
        _flat(glue),
        contains(
          'TextSpan termsRich({required L10nSpanBuilder link, '
          "TextStyle? style}) => l10nTextSpan(terms, tags: {'link': link}, "
          'style: style);',
        ),
      );
    });

    test('a project with no rich message generates the glue it always did', () {
      final glue = _glue(_project('"terms": "The terms"'));
      expect(glue, isNot(contains('RichText')));
      expect(glue.trimRight(), endsWith('}'));
    });
  });

  group('every locale must use the same tags', () {
    test('a tag only one locale writes names both files and both tags', () {
      final result = runGenerator(
        _project(
          '"terms(rich)": "Read the <link>terms</link>"',
          '"terms(rich)": "Прочтите <bold>условия</bold>"',
        ),
      );

      final error = result.diagnostics.singleWhere(
        (d) => d.code == 'rich_tag_mismatch',
      );
      expect(error.message, contains('ru'));
      expect(error.translationKey, 'legal.terms(rich)');
      // Both files, both lines: a span can only point at one of them.
      expect(error.details, contains('Base locale en ('));
      expect(error.details, contains('en.json:'));
      expect(error.details, contains('ru.json:'));
      expect(error.details, contains('tags: <link>'));
      expect(error.details, contains('tags: <bold>'));
      expect(error.details, contains('missing: <link>'));
      expect(error.details, contains('unexpected: <bold>'));
      // The span is on the locale that differs, which is the file to open.
      expect(error.span!.start.sourceUrl!.path, endsWith('ru.json'));
    });

    test('an extra tag in one locale is reported too', () {
      final result = runGenerator(
        _project(
          '"terms(rich)": "Read the <link>terms</link>"',
          '"terms(rich)": "Прочтите <link><bold>условия</bold></link>"',
        ),
      );
      final error = result.diagnostics.singleWhere(
        (d) => d.code == 'rich_tag_mismatch',
      );
      expect(error.details, contains('unexpected: <bold>'));
      expect(error.details, isNot(contains('missing:')));
    });

    test('the same tags in a different order are not a mismatch', () {
      // Word order is what translation is; only the set of tags is the API.
      final source = _generate(
        _project(
          '"terms(rich)": "<a>Read</a> the <b>terms</b>"',
          '"terms(rich)": "<b>Условия</b> нужно <a>прочесть</a>"',
        ),
      );
      expect(source, contains("L10nTagSpan('b', [L10nTextSpan('Условия')])"));
    });

    test(
      'a locale spelling the key without the suffix is a key that moved',
      () {
        // Richness is the key, so it cannot disagree between locales: the key
        // checks that already exist are what say so. Here that is `renamed_key`
        // — one spelling gone, another appeared — and it names both.
        final result = runGenerator({
          'en.json': '{"legal": {"terms(rich)": "The <b>terms</b>"}}',
          'ru.json': '{"legal": {"terms": "Условия"}}',
        });
        final warning = result.diagnostics.singleWhere(
          (d) => d.code == 'renamed_key',
        );
        expect(warning.details, contains('terms(rich)'));
      },
    );
  });

  group('malformed markup is an error, not a surprise at run time', () {
    List<String> codesFor(String message) =>
        errorsOf(runGenerator(_project('"terms(rich)": "$message"')));

    ({String message, String details}) errorFor(String message) {
      final result = runGenerator(_project('"terms(rich)": "$message"'));
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'rich_invalid_markup',
      );
      return (message: error.message, details: error.details ?? '');
    }

    test('an unclosed tag', () {
      // Both locales write the same broken string, and both are reported:
      // every locale's markup is read, not only the base locale's.
      expect(codesFor('Read the <link>terms'), [
        'rich_invalid_markup',
        'rich_invalid_markup',
      ]);
      final error = errorFor('Read the <link>terms');
      expect(error.message, contains('never closed'));
      expect(error.details, contains('</link>'));
    });

    test('crossed tags name the tag that is open', () {
      final error = errorFor('<b><i>both</b></i>');
      expect(error.message, 'Tag "<i>" is closed by "</b>".');
      expect(error.details, contains('Write </i> first'));
    });

    test('a closing tag with nothing open', () {
      final error = errorFor('Read the terms</link>');
      expect(error.message, contains('has no opening tag'));
      expect(error.details, contains('<link>'));
    });

    test('a "<" that tries to be a tag and fails', () {
      final error = errorFor('Press <b to continue');
      expect(error.message, 'Malformed tag in a rich message.');
      expect(error.details, contains('without the "(rich)" suffix'));
    });

    test('a "<" that is plainly not a tag stays text', () {
      // `3 < 4` and `<3` are text, in a rich message as anywhere else.
      final source = _generate(_project('"math(rich)": "3 < 4 and <3"'));
      expect(source, contains("L10nTextSpan('3 < 4 and <3')"));
    });

    test('the span points inside the message, at the tag', () {
      final result = runGenerator(
        _project('"terms(rich)": "Read the <link>terms"'),
      );
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'rich_invalid_markup',
      );
      expect(error.span!.text, '<link>');
    });
  });

  group('what rich text does not do', () {
    test('a plural inside a rich message is refused, with the way out', () {
      // The decision lives in the parser; this is the promise it makes.
      final result = runGenerator(
        _project(
          '"items(rich)": '
          '"{count, plural, one{<b>1</b> item} other{<b>#</b> items}}"',
        ),
      );
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'rich_unsupported_choice',
      );
      expect(error.message, 'A rich message cannot contain a plural.');
      expect(error.details, contains('one rich message per branch'));
      expect(error.details, contains('drop the "(rich)" suffix'));
    });

    test('a select inside a rich message is refused the same way', () {
      final result = runGenerator(
        _project('"tone(rich)": "{t, select, a{<b>A</b>} other{<b>B</b>}}"'),
      );
      expect(
        result.diagnostics
            .firstWhere((d) => d.code == 'rich_unsupported_choice')
            .message,
        'A rich message cannot contain a select.',
      );
    });
  });

  group('names that would not compile are reported', () {
    test('a tag and an argument cannot be the same parameter', () {
      final result = runGenerator(
        _project('"terms(rich)": "Hi {link}, read the <link>terms</link>"'),
      );
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'argument_collision',
      );
      expect(error.message, contains('Tag "<link>"'));
      expect(error.message, contains('argument "link"'));
    });

    test('two tags that would be one parameter are reported', () {
      final result = runGenerator(
        _project('"terms(rich)": "<my_tag>a</my_tag> <myTag>b</myTag>"'),
      );
      expect(
        errorsOf(result).where((code) => code == 'argument_collision'),
        isNotEmpty,
      );
    });

    test('a sibling key cannot take the wrapper name', () {
      // `terms(rich)` generates `terms` and `termsRich`; a plain `termsRich`
      // beside it would shadow the wrapper in the glue.
      final result = runGenerator({
        'en.json': '{"legal": {"terms(rich)": "<b>a</b>", "terms_rich": "b"}}',
        'ru.json': '{"legal": {"terms(rich)": "<b>а</b>", "terms_rich": "б"}}',
      });
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'identifier_collision',
      );
      expect(error.message, contains('termsRich'));
    });

    test('a group cannot be marked rich', () {
      final result = runGenerator({
        'en.json': '{"legal(rich)": {"terms": "a"}}',
        'ru.json': '{"legal(rich)": {"terms": "а"}}',
      });
      final error = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_key',
      );
      expect(error.message, contains('cannot be marked "(rich)"'));
    });
  });

  test('an untranslated rich message falls back whole, markup included', () {
    // The rule the plain path already follows: a locale with no translation
    // renders exactly as the base locale does. For rich text that has to
    // include the tags, or the fallback would be a sentence with its link
    // missing.
    final result = runGenerator({
      'en.json': '{"legal": {"terms(rich)": "Read the <link>terms</link>"}}',
      'ru.json': '{"legal": {}}',
    }, configYaml: '$_config\nfill_missing_from_base: true');
    expect(errorsOf(result), isEmpty);
    final source = result.files.single.contents;

    expect(source, contains('/// Untranslated: renders as `en`.'));
    expect(
      RegExp(
        r"L10nTagSpan\('link', \[L10nTextSpan\('terms'\)\]\)",
      ).allMatches(source),
      hasLength(2),
      reason: 'once in English, once in Russian falling back',
    );
  });

  test('a rich message reached only through the wrapper is not unused', () {
    // The `unused` command matches member names as text, and a Flutter app
    // calls `termsRich`, never `terms`. Reporting it would call a live
    // translation dead, which is the direction that scan must never err in.
    final result = runGenerator(
      _project('"terms(rich)": "The <link>terms</link>"'),
    );
    final key = result.keys.single;
    expect(key.path, 'legal.terms(rich)');
    expect(key.leafNames, ['terms', 'termsRich']);
  });
}
