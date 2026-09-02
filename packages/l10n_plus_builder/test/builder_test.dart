import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:l10n_plus_builder/l10n_plus_builder.dart';
import 'package:test/test.dart';

const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

/// The slice of [BuildStep] the adapter uses, backed by a map.
///
/// `build_test` is deliberately not used: its published version calls into
/// `build` APIs that no longer exist, and this fake tests exactly the contract
/// the adapter relies on.
final class _FakeBuildStep implements BuildStep {
  _FakeBuildStep(this.assets);

  final Map<String, String> assets;
  final Map<String, String> written = {};
  final List<AssetId> read = [];

  @override
  AssetId get inputId => AssetId('demo', r'lib/$lib$');

  @override
  Future<bool> canRead(AssetId id) async => assets.containsKey(id.path);

  @override
  Future<String> readAsString(AssetId id, {Encoding? encoding}) async {
    read.add(id);
    final content = assets[id.path];
    if (content == null) throw AssetNotFoundException(id);
    return content;
  }

  @override
  Stream<AssetId> findAssets(Glob glob, {String? package}) =>
      Stream.fromIterable(
        assets.keys.where(glob.matches).map((path) => AssetId('demo', path)),
      );

  @override
  Future<void> writeAsString(
    AssetId id,
    FutureOr<String> contents, {
    Encoding encoding = utf8,
  }) async {
    written[id.path] = await contents;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Builder _builder({List<String>? outputs}) =>
    l10nPlusBuilder(BuilderOptions({if (outputs != null) 'outputs': outputs}));

const List<String> _coreOnly = ['lib/generated/app_localizations.g.dart'];

void main() {
  test('generates the library from translation assets', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': _config,
      'translations/en.json': '{"auth": {"title": "Log in"}}',
      'translations/ru.json': '{"auth": {"title": "Войти"}}',
    });

    await _builder(outputs: _coreOnly).build(step);

    final written = step.written['lib/generated/app_localizations.g.dart']!;
    expect(written, contains('abstract interface class AppLocalizations'));
    expect(written, contains("String get title => 'Log in';"));
    expect(written, contains("String get title => 'Войти';"));
  });

  test('reads every translation file, so build_runner tracks them', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': _config,
      'translations/en.json': '{"a": "A"}',
      'translations/ru.json': '{"a": "А"}',
    });

    await _builder(outputs: _coreOnly).build(step);

    expect(
      step.read.map((id) => id.path),
      containsAll(['translations/en.json', 'translations/ru.json']),
    );
  });

  test('ignores files of unknown formats in the input directory', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': _config,
      'translations/en.json': '{"a": "A"}',
      'translations/notes.txt': 'not a translation file',
    });

    await _builder(outputs: _coreOnly).build(step);
    expect(step.written, hasLength(1));
  });

  test('fails the build on a translation error', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': _config,
      'translations/en.json': '{"a": "Hello {name}"}',
      'translations/ru.json': '{"a": "Привет"}',
    });

    await expectLater(
      _builder(outputs: _coreOnly).build(step),
      throwsStateError,
    );
    expect(step.written, isEmpty);
  });

  test('does nothing without a configuration file', () async {
    final step = _FakeBuildStep({'translations/en.json': '{"a": "A"}'});
    await _builder().build(step);
    expect(step.written, isEmpty);
  });

  test('skips an output the build.yaml does not declare', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': _config.replaceAll(
        '  enabled: false',
        '  enabled: true',
      ),
      'translations/en.json': '{"a": "A"}',
    });

    await _builder(outputs: _coreOnly).build(step);

    // The Flutter glue was generated but not declared, so it is not written.
    expect(step.written.keys, _coreOnly);
  });

  test('writes one file per locale when the config asks for it', () async {
    const outputs = [
      'lib/generated/app_localizations.g.dart',
      'lib/generated/app_localizations_en.g.dart',
      'lib/generated/app_localizations_ru.g.dart',
    ];
    final step = _FakeBuildStep({
      'l10n_plus.yaml': '$_config\nfile_per_locale: true\n',
      'translations/en.json': '{"a": "A"}',
      'translations/ru.json': '{"a": "А"}',
    });

    await _builder(outputs: outputs).build(step);

    expect(step.written.keys, outputs);
    expect(
      step.written[outputs[1]],
      contains("part of 'app_localizations.g.dart';"),
    );
  });

  test('finds translation files in subdirectories', () async {
    final step = _FakeBuildStep({
      'l10n_plus.yaml': '$_config\nfile_pattern: "{locale}/*"\n',
      'translations/en/auth.json': '{"a": "A"}',
      'translations/ru/auth.json': '{"a": "А"}',
    });

    await _builder(outputs: _coreOnly).build(step);

    // The glob has to be `**`: a locale may live in its own directory.
    expect(step.written[_coreOnly.single], contains("String get a => 'A';"));
    expect(
      step.read.map((id) => id.path),
      containsAll(['translations/en/auth.json', 'translations/ru/auth.json']),
    );
  });

  test('declares its outputs for build_runner', () {
    expect(_builder(outputs: _coreOnly).buildExtensions, {
      r'$package$': _coreOnly,
    });
  });
}
