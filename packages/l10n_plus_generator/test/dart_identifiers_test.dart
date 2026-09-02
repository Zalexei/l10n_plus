import 'package:l10n_plus_generator/src/model/dart_identifiers.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes separators to lower camel case', () {
    expect(DartIdentifiers.lowerCamel('auth_login'), 'authLogin');
    expect(DartIdentifiers.lowerCamel('auth-login'), 'authLogin');
    expect(DartIdentifiers.lowerCamel('Auth Login'), 'authLogin');
    expect(DartIdentifiers.lowerCamel('authLogin'), 'authLogin');
  });

  test('escapes reserved words', () {
    expect(DartIdentifiers.lowerCamel('class'), r'class$');
    expect(DartIdentifiers.lowerCamel('is'), r'is$');
    expect(DartIdentifiers.lowerCamel('toString'), r'toString$');
  });

  test('escapes leading digits', () {
    expect(DartIdentifiers.lowerCamel('404'), r'$404');
  });

  test('builds upper camel case paths', () {
    expect(
      DartIdentifiers.upperCamelPath(['profile', 'greeting_text']),
      'ProfileGreetingText',
    );
  });

  test('returns an empty identifier for unusable keys', () {
    expect(DartIdentifiers.lowerCamel('***'), '');
  });

  group('enum constants', () {
    test('values and index cannot be enum constants, so they are escaped', () {
      // `enum E { values }` does not compile: `values` is the static list and
      // `index` the instance getter every enum has.
      expect(DartIdentifiers.enumConstant('values'), r'values$');
      expect(DartIdentifiers.enumConstant('index'), r'index$');
      expect(DartIdentifiers.enumConstant('Values'), r'values$');
    });

    test('what Object contributes is escaped here too', () {
      expect(DartIdentifiers.enumConstant('hashCode'), r'hashCode$');
      expect(DartIdentifiers.enumConstant('toString'), r'toString$');
    });

    test('ordinary branches are untouched', () {
      expect(DartIdentifiers.enumConstant('gold'), 'gold');
      expect(DartIdentifiers.enumConstant('in_progress'), 'inProgress');
      expect(DartIdentifiers.enumConstant('name'), 'name');
    });

    test('a member is not an enum constant, so index stays index', () {
      // Escaping every member called `index` would be noise: only enums
      // cannot have one.
      expect(DartIdentifiers.lowerCamel('index'), 'index');
      expect(DartIdentifiers.lowerCamel('values'), 'values');
    });
  });
}
