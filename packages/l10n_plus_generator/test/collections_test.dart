@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Lists and maps: what the accessors are, and what an element may not be.
///
/// A collection is a group of ordinary leaves with a flag on the group, which
/// is why most of this file is about the two things an element cannot be
/// rather than about parsing. Everything else — placeholders, formats, links,
/// the cross locale check — reads the elements as the messages they are.
///
/// With `runtime_overrides` on the shapes change, and that half is asserted by
/// `collections_golden_test.dart` and executed by
/// `collections_runtime_test.dart`.
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

String _generated(String messages) {
  final result = runGenerator({'en.json': messages}, configYaml: _config);
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
  return result.files.map((file) => file.contents).join('\n');
}

Diagnostic _only(String messages, {String name = 'en.json'}) {
  final reports = runGenerator({
    name: messages,
  }, configYaml: _config).diagnostics;
  expect(reports, hasLength(1), reason: reports.join('\n'));
  return reports.single;
}

void main() {
  group('what a list and a map generate', () {
    test('an array is one const list', () {
      // `const`, so reading it twice gives the identical object and allocates
      // nothing — the property every other accessor in this library has.
      expect(
        _generated('{"steps": ["One", "Two"]}'),
        contains("List<String> get steps => const ['One', 'Two'];"),
      );
    });

    test('a (map) key is one const map, without the suffix', () {
      final source = _generated('{"c(map)": {"fr": "France"}}');
      expect(
        source,
        contains("Map<String, String> get c => const {'fr': 'France'};"),
      );
      expect(source, isNot(contains('(map)')));
    });

    test('an empty list is an empty list', () {
      expect(
        _generated('{"steps": []}'),
        contains('List<String> get steps => const [];'),
      );
    });

    test('a list is not a namespace of indices', () {
      // What the shape used to have to be, written by hand, with the count
      // living in Dart instead of in the translation file.
      final source = _generated('{"steps": ["One"]}');
      expect(source, isNot(contains(r'String get $0')));
      expect(source, isNot(contains(r'class $Steps')));
    });

    test('elements are messages, so a link resolves inside one', () {
      // Nothing about collections had to know: an element is a leaf, parsed
      // and rendered by the same code every message goes through.
      expect(
        _generated('{"brand": "Acme", "steps": ["Welcome to @:brand"]}'),
        contains("List<String> get steps => const ['Welcome to Acme'];"),
      );
    });

    test('a project with neither generates what it always did', () {
      const messages = '{"a": "A", "b": {"c": "C"}}';
      expect(
        runGenerator({
          'en.json': messages,
        }, configYaml: _config).files.single.contents,
        contains('String get a;'),
      );
    });

    test('YAML says the same thing with a sequence', () {
      final result = runGenerator({
        'en.yaml': 'steps:\n  - One\n  - Two\nc(map):\n  fr: France\n',
      }, configYaml: _config);
      expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
      final source = result.files.single.contents;
      expect(
        source,
        contains("List<String> get steps => const ['One', 'Two']"),
      );
      expect(source, contains("Map<String, String> get c => const {'fr':"));
    });
  });

  group('what an element may not be', () {
    test('a message that takes arguments', () {
      // Every element would have to accept every element's arguments, and the
      // accessor could no longer be `const`.
      final report = _only('{"steps": ["Hi {name}", "Two"]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('Element 0 of "steps"'));
      expect(report.message, contains('takes 1 argument (name)'));
      expect(report.details, contains('no caller can read'));
    });

    test('and a map element is named by its key, not its position', () {
      final report = _only('{"c(map)": {"fr": "Bonjour {name}"}}');
      expect(report.message, contains('Element "fr" of "c"'));
    });

    test('an element that is itself a list', () {
      // An object element is a record, as of Milestone 37. A list element is
      // not: it would need an index that is a type.
      final report = _only('{"steps": [["a"]]}');
      expect(report.code, 'invalid_collection_entry');
      expect(
        report.message,
        contains('Element 0 of "steps" is not a message or a record'),
      );
      expect(report.details, contains('an index that is a type'));
    });

    test('messages and records in one collection', () {
      final report = _only('{"steps": ["A", {"title": "B"}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('mixes 1 message(s) with 1 record(s)'));
      expect(report.details, contains('one element type'));
    });

    test('a rich element', () {
      final report = _only('{"c(map)": {"a(rich)": "See <b>this</b>"}}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('is rich'));
      expect(report.details, contains('list of spans'));
    });

    test('a plural, because it needs a count', () {
      // Not a special case: a plural takes an argument, and an element takes
      // none.
      final report = _only(
        '{"steps": ["{n, plural, one{# item} other{# items}}"]}',
      );
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('takes 1 argument (n)'));
    });

    test('(map) on a message rather than a group', () {
      final report = _only('{"c(map)": "text"}');
      expect(report.code, 'invalid_key');
      expect(report.message, contains('cannot be marked "(map)"'));
    });

    test('every code it reports is a registered diagnostic code', () {
      expect(
        DiagnosticCodes.alwaysErrors,
        contains('invalid_collection_entry'),
      );
    });
  });

  group('a collection of records', () {
    test('one interface and one class per locale, not per element', () {
      final source = _generated(
        '{"s": [{"title": "A", "body": "B"}, {"title": "C", "body": "D"}]}',
      );
      expect(source, contains(r'abstract interface class $SItem {'));
      expect(source, contains('String get title;'));
      expect(
        source,
        contains(r'const $SItemEn({required this.title, required this.body});'),
      );
      expect(source, contains(r'List<$SItem> get s => const ['));
      // The values are known while generating, so they are fields rather than
      // getters over a switch, and the list is one canonicalized constant.
      expect(source, contains(r"$SItemEn(title: 'A', body: 'B')"));
    });

    test('named arguments, because a record of five is a line to read', () {
      expect(
        _generated('{"s": [{"a": "1", "b": "2", "c": "3"}]}'),
        contains(r"$SItemEn(a: '1', b: '2', c: '3')"),
      );
    });

    test('the first element declares the fields, in its own order', () {
      final source = _generated('{"s": [{"b": "1", "a": "2"}]}');
      expect(
        source,
        contains(r'const $SItemEn({required this.b, required this.a});'),
      );
    });

    test('a map of records is keyed by the map, typed by the element', () {
      final source = _generated(
        '{"p(map)": {"free": {"name": "Free"}, "pro": {"name": "Pro"}}}',
      );
      expect(source, contains(r'Map<String, $PItem> get p => const {'));
      expect(source, contains(r"'free': $PItemEn(name: 'Free')"));
    });

    test('a field may hold a link, which resolves like anywhere else', () {
      expect(
        _generated('{"brand": "Acme", "s": [{"note": "Try @:brand"}]}'),
        contains(r"$SItemEn(note: 'Try Acme')"),
      );
    });

    test('an element missing a field the first element has', () {
      // The check this feature exists to make. A package that built a map at
      // run time could only fail at the field that was missing, on the screen
      // that read it.
      final report = _only('{"s": [{"a": "1", "b": "2"}, {"a": "3"}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('Element 1 of "s" has no "b"'));
      expect(report.details, contains('"a", "b"'));
    });

    test('an element with a field the first element has not', () {
      final report = _only('{"s": [{"a": "1"}, {"a": "2", "b": "3"}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(
        report.message,
        contains('has a field "b" that Element 0 of "s" does not'),
      );
    });

    test('a field that is itself an object', () {
      // One level deep: a nested field would need a type of its own, and then
      // so would its fields.
      final report = _only('{"s": [{"a": {"b": "B"}}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('is a group'));
      expect(report.details, contains('one level deep'));
    });

    test('a field that takes an argument', () {
      final report = _only('{"s": [{"a": "Hi {name}"}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('"a" of Element 0 of "s" takes 1'));
      // And the fix names the link, which is how a value gets in.
      expect(report.details, contains('Interpolate with a link'));
    });

    test('a rich field', () {
      final report = _only('{"s": [{"a(rich)": "See <b>x</b>"}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('is rich'));
    });

    test('an element with no fields at all', () {
      final report = _only('{"s": [{}]}');
      expect(report.code, 'invalid_collection_entry');
      expect(report.message, contains('has no fields'));
    });

    test('two fields that become one Dart name', () {
      final report = _only('{"s": [{"sub_title": "A", "subTitle": "B"}]}');
      expect(report.code, 'identifier_collision');
      expect(report.message, contains('subTitle'));
    });

    test('one error per mistake, not a cascade', () {
      // A refused field used to also report "the element has no such field",
      // which is the same mistake said twice — and once said it about the
      // element that declares the fields, against itself.
      for (final messages in [
        '{"s": [{"a": "Hi {name}"}]}',
        '{"s": [{"a(rich)": "See <b>x</b>"}]}',
        '{"s": [{"a": {"b": "B"}}]}',
      ]) {
        final reports = runGenerator({
          'en.json': messages,
        }, configYaml: _config).diagnostics;
        expect(reports, hasLength(1), reason: '$messages\n${reports.join()}');
      }
    });

    test('a locale missing one field is the missing key', () {
      final reports = runGenerator({
        'en.json': '{"s": [{"a": "1", "b": "2"}]}',
        'ru.json': '{"s": [{"a": "1"}]}',
      }, configYaml: _config).diagnostics;
      expect(
        reports.firstWhere((d) => d.code == 'missing_key').message,
        contains('s.0.b'),
      );
    });

    test('every field is a message for coverage', () {
      final result = runGenerator({
        'en.json': '{"s": [{"a": "1", "b": "2"}]}',
      }, configYaml: _config);
      expect(errorsOf(result), isEmpty);
      expect(result.coverage.single.total, 2);
    });
  });

  group('how a collection meets the rest of the library', () {
    test('a length difference between locales is the missing key', () {
      // For free, and pointing at the right file: the elements are keyed by
      // index, so the cross locale check already knows how to say this.
      final reports = runGenerator({
        'en.json': '{"steps": ["One", "Two", "Three"]}',
        'ru.json': '{"steps": ["Один", "Два"]}',
      }, configYaml: _config).diagnostics;
      expect(reports.map((d) => d.code), contains('missing_key'));
      expect(
        reports.firstWhere((d) => d.code == 'missing_key').message,
        contains('steps.2'),
      );
    });

    test('a map key one locale does not have is the same finding', () {
      final reports = runGenerator({
        'en.json': '{"c(map)": {"fr": "France", "de": "Germany"}}',
        'ru.json': '{"c(map)": {"fr": "Франция"}}',
      }, configYaml: _config).diagnostics;
      expect(
        reports.firstWhere((d) => d.code == 'missing_key').message,
        contains('c(map).de'),
      );
    });

    test('one locale writing (map) and another not is a renamed key', () {
      // The suffix is part of the key, which is the argument `(rich)` makes:
      // mapness is not a property one locale could declare differently. What
      // says so is the rename detection, and it says it better than the
      // missing-and-extra pair would: `c(map)` became `c`, here is the line.
      final result = runGenerator({
        'en.json': '{"c(map)": {"fr": "France"}}',
        'ru.json': '{"c": {"fr": "Франция"}}',
      }, configYaml: _config);
      final renamed = result.diagnostics.firstWhere(
        (d) => d.code == 'renamed_key',
      );
      expect(renamed.message, contains('c(map)'));
      expect(renamed.severity, Severity.error);
    });

    test('a list nothing reads is one finding, not one per element', () {
      // The collection is reached by its own name, so that is the key the
      // scan looks for. Reporting three unused items for one unused list
      // would be three edits for one mistake.
      final result = runGenerator({
        'en.json': '{"steps": ["One", "Two"], "used": "U"}',
      }, configYaml: _config);
      expect(errorsOf(result), isEmpty);
      final unused = UnusedKeyScanner.scan(
        keys: result.keys,
        sources: const [
          DartSource(path: 'lib/main.dart', content: 'void f() { t.used; }'),
        ],
      );
      expect(unused.diagnostics, hasLength(1));
      expect(unused.diagnostics.single.message, contains('steps'));
      expect(unused.keyCount, 1);
    });

    test('elements count as messages for coverage', () {
      // A list of two is two messages to translate, which is what `analyze`
      // reports and what a translator is being asked for.
      final result = runGenerator({
        'en.json': '{"steps": ["One", "Two"]}',
        'ru.json': '{"steps": ["Один"]}',
      }, configYaml: 'fill_missing_from_base: true\n$_config');
      final ru = result.coverage.firstWhere((locale) => locale.locale == 'ru');
      expect(ru.total, 2);
      expect(ru.translated, 1);
      expect(ru.untranslated, 1);
    });
  });
}
