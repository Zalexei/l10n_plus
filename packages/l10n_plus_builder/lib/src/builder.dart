import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;

/// Runs the `l10n_plus` generator as a `build_runner` builder.
///
/// The generator itself is unchanged: this only swaps file system reads for
/// build asset reads, so that `build_runner` knows which translation files an
/// output depends on and rebuilds when one of them changes.
final class L10nPlusBuilder implements Builder {
  /// Creates a builder.
  ///
  /// Recognised options:
  ///
  /// * `config`: path to the configuration file, default `l10n_plus.yaml`.
  L10nPlusBuilder(BuilderOptions options)
    : configPath =
          options.config['config'] as String? ?? L10nPlusConfig.defaultFileName,
      _outputs =
          (options.config['outputs'] as List?)?.cast<String>() ??
          const [
            'lib/generated/app_localizations.g.dart',
            'lib/generated/app_localizations_flutter.g.dart',
          ];

  /// Path of the configuration file, relative to the package root.
  final String configPath;

  final List<String> _outputs;

  @override
  Map<String, List<String>> get buildExtensions => {r'$package$': _outputs};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;

    final configId = AssetId(package, configPath);
    if (!await buildStep.canRead(configId)) {
      log.info(
        'No $configPath found, skipping l10n_plus generation for $package.',
      );
      return;
    }

    final diagnostics = DiagnosticCollector();
    final config = L10nPlusConfig.parse(
      await buildStep.readAsString(configId),
      uri: Uri.parse('asset:$package/$configPath'),
      diagnostics: diagnostics,
    );
    if (config == null) {
      _report(diagnostics.diagnostics);
      throw StateError('l10n_plus configuration is invalid.');
    }

    final generator = L10nPlusGenerator(config: config, projectRoot: '.');
    final extensions = {
      for (final parser in generator.parsers) ...parser.extensions,
    };

    // Reading each translation file through `buildStep` is what registers it
    // as a dependency of the generated output.
    final inputs = <TranslationInput>[];
    // `**`, not `*`: a locale may live in a subdirectory, and discovery on the
    // file system side is recursive too.
    await for (final id in buildStep.findAssets(
      Glob('${config.inputDirectory}/**'),
    )) {
      if (!extensions.contains(p.extension(id.path).replaceFirst('.', ''))) {
        continue;
      }
      inputs.add(
        TranslationInput(
          path: id.path,
          uri: Uri.parse('asset:$package/${id.path}'),
          content: await buildStep.readAsString(id),
        ),
      );
    }

    final pubspecId = AssetId(package, 'pubspec.yaml');
    final result = generator.generate(
      inputs,
      pubspec: await buildStep.canRead(pubspecId)
          ? await buildStep.readAsString(pubspecId)
          : null,
      diagnostics: diagnostics,
    );
    _report(result.diagnostics);
    if (result.hasErrors) {
      throw StateError(
        'l10n_plus found ${result.diagnostics.where((d) => d.severity == Severity.error).length} '
        'error(s) in the translations.',
      );
    }

    for (final file in result.files) {
      final normalized = p.url.normalize(file.path);
      if (!_outputs.contains(normalized)) {
        log.severe(
          'l10n_plus wants to write "$normalized", which this builder does '
          'not declare. Declare it in build.yaml:\n'
          '  targets:\n'
          '    \$default:\n'
          '      builders:\n'
          '        l10n_plus_builder:l10n_plus:\n'
          '          options:\n'
          '            outputs: ["$normalized"]',
        );
        continue;
      }
      await buildStep.writeAsString(
        AssetId(package, normalized),
        file.contents,
      );
    }
  }

  void _report(List<Diagnostic> diagnostics) {
    for (final diagnostic in diagnostics) {
      final text = diagnostic.format(highlight: false);
      if (diagnostic.severity == Severity.error) {
        log.severe(text);
      } else {
        log.warning(text);
      }
    }
  }
}
