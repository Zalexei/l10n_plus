import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('a diagnostic names the file, key, code and expectation', () {
    final result = runGenerator({
      'en.json':
          '{"wallet": {"transactions": '
          '"{count, plural, other{# transactions}}"}}',
      'ru.json': '{"wallet": {"transactions": "Транзакции"}}',
    });

    final diagnostic = result.diagnostics.singleWhere(
      (d) => d.severity == Severity.error,
    );
    final text = diagnostic.format(highlight: false);

    expect(text, contains('ru.json:'));
    expect(text, contains('wallet.transactions'));
    expect(text, contains('missing_placeholder'));
    expect(text, contains('argument: count'));
    expect(text, contains('type: plural'));
    expect(text, contains('argument is missing'));
  });

  test('spans point inside the message, not just at the file', () {
    final result = runGenerator({
      'en.json': '{\n  "a": "ok",\n  "b": "{count, plural, one{x}}"\n}',
    });
    final diagnostic = result.diagnostics.first;
    expect(diagnostic.code, 'icu_missing_other_branch');
    // Zero based; `Diagnostic.format` prints them one based.
    expect(diagnostic.span!.start.line, 2);
    expect(diagnostic.span!.start.column, 8);
  });

  test('a non file source url is printed, not crashed on', () {
    const diagnostic = Diagnostic.error(code: 'x', message: 'y');
    expect(diagnostic.format(), contains('error[x]'));

    final file = SourceFile.fromString(
      'abc',
      url: Uri.parse('asset:demo/translations/en.json'),
    );
    final withAsset = Diagnostic.error(
      code: 'x',
      message: 'y',
      span: file.span(0, 1),
    );
    expect(
      withAsset.format(highlight: false),
      contains('asset:demo/translations/en.json:1:1'),
    );
  });

  test('warnings do not stop generation', () {
    final result = runGenerator({
      'en.json': '{"a": "A"}',
    }, configYaml: 'base_locale: en\nunknown: 1\nflutter:\n  enabled: false');
    expect(result.hasErrors, isFalse);
    expect(result.files, isNotEmpty);
  });
}
