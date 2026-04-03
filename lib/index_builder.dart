import 'dart:async';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'src/cross_file_registry.dart';

/// A post-build aggregating step that:
/// 1. Collects all generated .g.ts files
/// 2. Produces a barrel `index.ts` re-exporting everything
///
/// Register in build.yaml as a separate builder with `build_to: source`.
class TsIndexBuilder implements Builder {
  final Map<String, dynamic> config;

  TsIndexBuilder(this.config);

  String get outputDir => config['output_dir'] as String? ?? 'lib/generated/ts';

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['generated/ts/index.ts'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final generatedFiles = <String>[];

    // Find all .g.ts files in the output directory
    await for (final input in buildStep.findAssets(
      Glob('$outputDir/**.g.ts'),
    )) {
      generatedFiles.add(input.path);
    }

    // Also check for .ts files (non-.g.ts pattern used by file builder)
    await for (final input in buildStep.findAssets(
      Glob('lib/**.g.ts'),
    )) {
      final path = input.path;
      if (!generatedFiles.contains(path)) {
        generatedFiles.add(path);
      }
    }

    if (generatedFiles.isEmpty) return;

    generatedFiles.sort();

    final outputId = AssetId(
      buildStep.inputId.package,
      '$outputDir/index.ts',
    );

    final content = IndexBarrelGenerator.generate(
      generatedFiles,
      outputId.path,
    );

    await buildStep.writeAsString(outputId, content);

    log.info('dart_ts_generator: wrote index.ts with ${generatedFiles.length} exports');
  }
}

Builder tsIndexBuilder(BuilderOptions options) => TsIndexBuilder(options.config);
