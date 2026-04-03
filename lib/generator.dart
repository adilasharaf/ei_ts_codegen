import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/model_analyzer.dart';
import 'src/zod_generator.dart';

/// The main [Generator] that source_gen invokes per library.
class DartTsGenerator extends Generator {
  final Map<String, dynamic> config;

  DartTsGenerator(this.config);

  final _jsonSerializableChecker = TypeChecker.typeNamedLiterally(
    'JsonSerializable',
    inPackage: 'json_annotation',
  );

  final _tsGenerateChecker = TypeChecker.typeNamedLiterally(
    'TsGenerate',
    inPackage: 'dart_ts_generator',
  );

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) async {
    return generateForLibrary(library.element, buildStep);
  }

  Future<String?> generateForLibrary(
    LibraryElement library,
    BuildStep buildStep,
  ) async {
    final generatorConfig = GeneratorConfig.fromMap(config);

    // Collect ALL classes in library (including enums)
    final allClasses = _collectClasses(library);

    if (allClasses.isEmpty) return null;

    // Build name sets for cross-referencing
    final knownModelNames = allClasses.map((c) => c.name!).toSet();
    final knownEnumNames =
        allClasses.whereType<EnumElement>().map((c) => c.name!).toSet();

    final analyzer = ModelAnalyzer(
      knownModelNames: knownModelNames,
      knownEnumNames: knownEnumNames,
    );

    // Analyze each class
    final classInfos = <ClassInfo>[];
    for (final cls in allClasses) {
      try {
        if (cls is EnumElement) {
          classInfos.add(_analyzeEnum(cls));
        } else if (cls is ClassElement) {
          if (!_shouldGenerate(cls)) continue;
          classInfos.add(analyzer.analyzeClass(cls));
        }
      } catch (e) {
        log.warning('dart_ts_generator: failed to analyze ${cls.name}: $e');
      }
    }

    if (classInfos.isEmpty) return null;

    // Build registry
    final registry = {for (final c in classInfos) c.name!: c};

    // Generate Zod output
    final zodGen = ZodSchemaGenerator(
      classRegistry: registry,
      config: generatorConfig,
    );

    return zodGen.generateFile(classInfos);
  }

  List<InterfaceElement> _collectClasses(LibraryElement library) {
    final result = <InterfaceElement>[];

    // analyzer >=7.x: CompilationUnitElement is removed. Use
    // library.topLevelElements which flattens all units (defining + parts)
    // into a single iterable of top-level elements.
    for (final element in library.children) {
      if (element is EnumElement) result.add(element);
      if (element is ClassElement) result.add(element);
      if (element is MixinElement) result.add(element);
    }

    return result;
  }

  bool _shouldGenerate(ClassElement cls) {
    // Always skip private classes
    if (cls.name!.startsWith('_')) return false;

    // Include if annotated with @JsonSerializable or @TsGenerate
    if (_jsonSerializableChecker.hasAnnotationOf(cls)) return true;
    if (_tsGenerateChecker.hasAnnotationOf(cls)) return true;

    // Also include classes that extend a known class
    final superName = cls.supertype?.element.name;
    if (superName != null &&
        superName != 'Object' &&
        !superName.startsWith('_')) {
      return true;
    }

    return false;
  }

  ClassInfo _analyzeEnum(EnumElement element) {
    final values = element.fields
        .where((f) => f.isEnumConstant)
        .map((f) => f.name)
        .toList();

    return ClassInfo(
      name: element.name,
      fields: [],
      isEnum: true,
      enumValues: values,
      isAbstract: false,
    );
  }
}
