import 'dart:async';
import 'dart:convert';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:glob/glob.dart';
import 'model_emitter.dart';
import 'enum_emitter.dart';
import 'utils_emitter.dart';

/// Phase 1: scan each .dart file, extract model/enum metadata, write
/// a sidecar .ts_meta.json so Phase 2 can aggregate across the whole
/// package in one pass.
class TsCodegenBuilder implements Builder {
  final BuilderOptions options;
  TsCodegenBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => {
        '.dart': ['.ts_meta.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final library = await buildStep.inputLibrary;
    final reader = LibraryReader(library);

    final models = <Map<String, dynamic>>[];
    final enums = <Map<String, dynamic>>[];

    // Collect all classes annotated with @JsonSerializable
    for (final cls in reader.classes) {
      if (_hasJsonSerializable(cls)) {
        models.add(ModelEmitter.extractMetadata(cls));
      }
    }

    // Collect all enums in the library
    for (final enm in reader.enums) {
      enums.add(EnumEmitter.extractMetadata(enm));
    }

    if (models.isEmpty && enums.isEmpty) return;

    final meta = {'models': models, 'enums': enums};
    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.ts_meta.json'),
      jsonEncode(meta),
    );
  }

  bool _hasJsonSerializable(ClassElement cls) {
    return cls.metadata.annotations.any((a) =>
        a.element?.enclosingElement?.name == 'JsonSerializable' ||
        a.element?.enclosingElement?.name == 'json_serializable');
  }
}

/// Phase 2: aggregate all .ts_meta.json files and write the final
/// TypeScript output files.
class TsCodegenAggregateBuilder implements Builder {
  final BuilderOptions options;
  final String outputDir;

  TsCodegenAggregateBuilder(this.options)
      : outputDir = options.config['output_dir'] as String? ?? 'lib/ts_output';

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$package$': [
          '$outputDir/models.ts',
          '$outputDir/enums.ts',
          '$outputDir/utils.ts',
          '$outputDir/index.ts',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final allModels = <Map<String, dynamic>>[];
    final allEnums = <Map<String, dynamic>>[];

    // Glob all sidecar meta files
    await for (final asset in buildStep.findAssets(
      Glob('lib/**/*.ts_meta.json'),
    )) {
      final content = await buildStep.readAsString(asset);
      final meta = jsonDecode(content) as Map<String, dynamic>;
      allModels.addAll((meta['models'] as List).cast());
      allEnums.addAll((meta['enums'] as List).cast());
    }

    // Emit each output file
    final pkg = buildStep.inputId.package;

    await buildStep.writeAsString(
      AssetId(pkg, '$outputDir/enums.ts'),
      EnumEmitter.emit(allEnums),
    );

    await buildStep.writeAsString(
      AssetId(pkg, '$outputDir/utils.ts'),
      UtilsEmitter.emit(),
    );

    await buildStep.writeAsString(
      AssetId(pkg, '$outputDir/models.ts'),
      ModelEmitter.emit(allModels, allEnums),
    );

    await buildStep.writeAsString(
      AssetId(pkg, '$outputDir/index.ts'),
      _emitIndex(),
    );
  }

  String _emitIndex() => '''
// Auto-generated. Do not edit manually.
export * from './enums';
export * from './utils';
export * from './models';
''';
}
