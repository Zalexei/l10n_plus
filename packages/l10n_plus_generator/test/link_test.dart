@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `@:other.key`: what a link resolves to, and what it is refused for.
///
/// A link is the one construct in a message whose correctness is a property of
/// the project rather than of the string, so most of this file is about what
/// the build says no to. What the resolved code *does* is asserted by
/// `links_runtime_test.dart`, which executes the golden rather than reading
/// it; here the question is what the emitter wrote and what the resolver
/// reported.
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

const String _withOverrides = '${_config}runtime_overrides: true\n';

/// The generated library of a one locale project with [messages].
String _generated(String messages, {String config = _config}) {
  final result = runGenerator({'en.json': messages}, configYaml: config);
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
  return result.files.map((file) => file.contents).join('\n');
}

/// Diagnostics of a project that is expected to have a problem.
List<Diagnostic> _problems(
  Map<String, String> translations, {
  String config = _config,
}) => runGenerator(translations, configYaml: config).diagnostics;

/// The one problem of [messages].
Diagnostic _only(String messages, {String config = _config}) {
  final reports = _problems({'en.json': messages}, config: config);
  expect(reports, hasLength(1), reason: reports.join('\n'));
  return reports.single;
}

void main() {
  group('what a link resolves to', () {
    test('a link to literal text is written in place', () {
      // The whole performance argument of this library is that reading a
      // translation is reading a `const`. A link that compiled to a call
      // would be the first place that stopped being true, so the common case
      // — the product name, the word a dozen messages share — is resolved
      // while generating and costs nothing at all.
      final source = _generated(
        '{"brand": "Acme", "welcome": "Welcome to @:brand"}',
      );
      expect(source, contains("String get welcome => 'Welcome to Acme';"));
      expect(source, isNot(contains('().brand')));
    });

    test('and the message stays a getter, because it gained no parameter', () {
      expect(
        _generated('{"brand": "Acme", "welcome": "Welcome to @:brand"}'),
        contains('String get welcome;'),
      );
    });

    test('a chain of links is followed all the way down', () {
      expect(
        _generated('{"a": "Acme", "b": "@:a Cloud", "c": "Welcome to @:b"}'),
        contains("String get c => 'Welcome to Acme Cloud';"),
      );
    });

    test('linking and writing the words out compile to the same code', () {
      // The two forms are interchangeable, which is what makes a link a way
      // of saying something once rather than a different kind of message. The
      // one difference is deliberate, and it is the doc comment: that shows
      // the message as the translation file writes it.
      String withoutDocs(String source) => source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n');

      expect(
        withoutDocs(
          _generated('{"brand": "Acme", "welcome": "Welcome to @:brand"}'),
        ),
        withoutDocs(
          _generated('{"brand": "Acme", "welcome": "Welcome to Acme"}'),
        ),
      );
    });

    test('a target with a parameter becomes a call, and lends it', () {
      final source = _generated(
        '{"greet": "Hello {name}", "hello": "@:greet!"}',
      );
      expect(source, contains('String hello({required String name});'));
      expect(
        source,
        contains(r"'${const AppLocalizationsEn().greet(name: name)}!';"),
      );
    });

    test('a link to a plural lends the count it selects on', () {
      final source = _generated(
        '{"items": "{n, plural, one{# item} other{# items}}", '
        '"cart": "Cart: @:items"}',
      );
      expect(source, contains('String cart({required num n});'));
      expect(source, contains(r'const AppLocalizationsEn().items(n: n)'));
    });

    test('the parameter is lent transitively', () {
      final source = _generated(
        '{"greet": "Hello {name}", "a": "@:greet.", "b": "Oh — @:a"}',
      );
      expect(source, contains('String b({required String name});'));
    });

    test('a link in a nested namespace names that namespace class', () {
      expect(
        _generated(
          '{"brand": {"name": "Acme"}, "greet": {"hi": "Hi from @:brand.name"}}',
        ),
        contains("String get hi => 'Hi from Acme';"),
      );
    });

    test('the braced form exists for a key the sentence runs into', () {
      expect(
        _generated('{"brand": "Acme", "a": "@:{brand}s everywhere"}'),
        contains("String get a => 'Acmes everywhere';"),
      );
    });

    test('a link stands inside a plural branch like any other content', () {
      final source = _generated(
        '{"brand": "Acme", '
        '"r": "{n, plural, one{One @:brand charge} other{# @:brand charges}}"}',
      );
      expect(source, contains("return 'One Acme charge';"));
      expect(source, contains(r"return '$n Acme charges';"));
    });

    test('the doc comment shows the link rather than the text', () {
      // The generated member documents the message as the translation file
      // writes it; what it resolved to is in the body three lines below.
      expect(
        _generated('{"brand": "Acme", "welcome": "Welcome to @:brand"}'),
        contains('/// `en`: Welcome to @:brand'),
      );
    });

    test('what is linked is reported, so nothing calls it dead', () {
      // A message reached only by a link is used. Reporting it would be the
      // one direction the unused scan must not err in: advice to delete a key
      // the build depends on.
      final result = runGenerator({
        'en.json': '{"brand": "Acme", "welcome": "Welcome to @:brand"}',
      }, configYaml: _config);
      expect(result.linkedKeys, {'brand'});
    });
  });

  group('an at sign that is not a link', () {
    test('an address is left alone', () {
      expect(
        _generated('{"a": "support@acme.example"}'),
        contains("'support@acme.example'"),
      );
    });

    test('a quoted at sign is the two characters', () {
      // The apostrophe that already quotes `{`, `}` and `#`, extended to `@`
      // rather than inventing a second escape for one rare message.
      expect(
        _generated(r'''{"a": "write to x'@':y"}'''),
        contains("'write to x@:y'"),
      );
    });

    test('an at sign before something that cannot start a key is text', () {
      expect(_generated('{"a": "cost @ 5"}'), contains("'cost @ 5'"));
    });
  });

  group('what a link is refused for', () {
    test('a key nothing defines, with the near miss offered', () {
      final report = _only('{"nope": {"there": "x"}, "a": "see @:nope.here"}');
      expect(report.code, 'unknown_link_target');
      expect(report.message, contains('nope.here'));
      expect(report.details, contains('Did you mean "nope.there"?'));
    });

    test('a group, which is not a message', () {
      final report = _only('{"g": {"a": "A"}, "b": "see @:g"}');
      expect(report.code, 'unknown_link_target');
      expect(report.details, contains('A group is not a message'));
    });

    test('a message that links to itself', () {
      final report = _only('{"a": "see @:a"}');
      expect(report.code, 'link_cycle');
      expect(report.message, contains('links to itself'));
    });

    test('a ring of two, named in the order it is followed', () {
      final report = _only('{"a": "see @:b", "b": "and @:a"}');
      expect(report.code, 'link_cycle');
      expect(report.message, contains('a -> b -> a'));
    });

    test('a ring of three', () {
      final report = _only('{"a": "@:b", "b": "@:c", "c": "@:a"}');
      expect(report.code, 'link_cycle');
      expect(report.message, contains('a -> b -> c -> a'));
    });

    test('a ring is one finding, not one per message in it', () {
      // Found from two directions it is still one loop, and the fix is one
      // edit. The same rule the importer follows for a deleted key.
      final reports = _problems({
        'en.json': '{"a": "@:b", "b": "@:a", "c": "@:a and @:b"}',
      });
      expect(reports.map((d) => d.code), ['link_cycle']);
    });

    test('a ring copied into a second locale is still one finding', () {
      final reports = _problems({
        'en.json': '{"a": "@:b", "b": "@:a"}',
        'ru.json': '{"a": "@:b", "b": "@:a"}',
      });
      expect(reports.map((d) => d.code), ['link_cycle']);
      // Reported against the base locale, which is the file the project is
      // maintained in.
      expect(reports.single.span?.sourceUrl?.path, endsWith('en.json'));
    });

    test('a rich message, whose spans are structure rather than text', () {
      final report = _only(
        '{"terms(rich)": "Read the <link>terms</link>", "a": "Please @:terms"}',
      );
      expect(report.code, 'link_to_rich');
      expect(report.details, contains('list of spans'));
    });

    test('a link inside a rich message', () {
      final report = _only(
        '{"brand": "Acme", "a(rich)": "The <b>@:brand</b> plan"}',
      );
      expect(report.code, 'rich_unsupported_link');
    });

    test('a relative link, with the rule stated', () {
      // `slang` spells a sibling `@:.key`. Reading it as a malformed path
      // says so, rather than leaving the characters on a screen.
      final report = _only('{"g": {"a": "A", "b": "see @:.a"}}');
      expect(report.code, 'invalid_link');
      expect(report.message, contains('absolute'));
      expect(report.details, contains('Relative links are not supported'));
    });

    test('a braced link with no closing brace', () {
      final report = _only('{"a": "A", "b": "see @:{a"}');
      expect(report.code, 'invalid_link');
      expect(report.message, contains('close'));
    });

    test('a target that wants another Dart type for the same name', () {
      // The existing conflict machinery, reached through a link: the caret is
      // on the link, and the details name the message the other kind came
      // from — the fix is in one of the two files, not in this line.
      final report = _only(
        '{"n": "{n, plural, one{# x} other{# xs}}", '
        '"b": "{n, date, yMd} and @:n"}',
      );
      expect(report.code, 'argument_kind_conflict');
      expect(report.details, contains('comes from "n"'));
      expect(report.details, contains('which this message links to'));
    });

    test('a locale that drops a parameter a link lent it', () {
      // The link is how `hello` came to take `name`, and the existing cross
      // locale check is what notices Russian not taking it.
      final reports = _problems({
        'en.json': '{"greet": "Hello {name}", "hello": "@:greet!"}',
        'ru.json': '{"greet": "Привет, {name}", "hello": "Привет!"}',
      });
      expect(reports.map((d) => d.code), contains('missing_placeholder'));
    });

    test('a link in an override bundle', () {
      // Nothing at run time resolves a link: by the time a bundle is
      // installed the target's text is already compiled in.
      final result = runGenerator({
        'en.json': '{"brand": "Acme", "a": "Welcome to @:brand"}',
      }, configYaml: _withOverrides);
      expect(errorsOf(result), isEmpty);

      final diagnostics = DiagnosticCollector();
      final bundle = OverrideBundle.read(
        content: '{"@@locale": "en", "a": "Hello from @:brand"}',
        uri: Uri.file('/tmp/overrides_en.json'),
        path: 'overrides_en.json',
        diagnostics: diagnostics,
      )!;
      OverrideChecker.check(
        bundle: bundle,
        catalog: result.overrides,
        diagnostics: diagnostics,
        requireFingerprint: false,
      );
      expect(diagnostics.diagnostics.map((d) => d.code), [
        'override_contains_link',
      ]);
    });

    test('every code it reports is a registered diagnostic code', () {
      for (final code in [
        'invalid_link',
        'unknown_link_target',
        'link_cycle',
        'link_to_rich',
        'rich_unsupported_link',
        'override_contains_link',
      ]) {
        expect(DiagnosticCodes.alwaysErrors, contains(code), reason: code);
      }
    });
  });

  group('how a link meets runtime overrides', () {
    test(
      'with overrides on, a link is a call so the target can be replaced',
      () {
        // The decision the two features forced. Inlined text could not change
        // when the target is overridden, and a brand rename that reached one
        // message out of twelve would be worse than no feature.
        final source = _generated(
          '{"brand": "Acme", "welcome": "Welcome to @:brand"}',
          config: _withOverrides,
        );
        expect(
          source,
          contains(r"'Welcome to ${const AppLocalizationsEn().brand}'"),
        );
        expect(source, isNot(contains("'Welcome to Acme'")));
      },
    );

    test('with overrides off, the same project inlines and never calls', () {
      final source = _generated(
        '{"brand": "Acme", "welcome": "Welcome to @:brand"}',
      );
      expect(source, contains("'Welcome to Acme'"));
      expect(source, isNot(contains('AppLocalizationsEn().brand')));
    });

    test('a lent parameter is still a token a bundle can place', () {
      // What a link brings is not overridable — it is resolved before there
      // are words. What it *lends* is: `cart` never writes `{n}` and an
      // override of it can still put the count where it wants.
      final source = _generated(
        '{"items": "{n, plural, one{# item} other{# items}}", '
        '"cart": "Cart: @:items"}',
        config: _withOverrides,
      );
      expect(
        source,
        contains(r"L10nOverrides.fill($override, {'n': n.toString()})"),
      );
    });
  });
}
