import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'generator.dart';

/// Builder factory called by build_runner.
Builder dartTsGeneratorBuilder(BuilderOptions options) {
  return SharedPartBuilder(
    [DartTsGenerator(options.config)],
    'dart_ts_generator',
  );
}

/// Standalone file-per-file builder (alternative mode).
Builder dartTsFileBuilder(BuilderOptions options) {
  return _TsFileBuilder(options.config);
}

class _TsFileBuilder implements Builder {
  final Map<String, dynamic> config;

  _TsFileBuilder(this.config);

  @override
  Map<String, List<String>> get buildExtensions => {
        '.dart': ['.g.ts'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final library = await buildStep.inputLibrary;

    final generator = DartTsGenerator(config);
    final output = await generator.generateForLibrary(library, buildStep);

    if (output == null || output.trim().isEmpty) return;

    final outputId = inputId.changeExtension('.g.ts');
    await buildStep.writeAsString(outputId, output);
  }
}
