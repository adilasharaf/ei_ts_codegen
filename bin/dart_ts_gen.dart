#!/usr/bin/env dart
// bin/dart_ts_gen.dart
//
// Standalone CLI to generate TypeScript/Zod schemas from Dart source files.
// Uses the analyzer package directly — no build_runner needed.
//
// Usage:
//   dart run dart_ts_generator:dart_ts_gen [options] <file.dart|directory>
//
// Options:
//   --out, -o <dir>       Output directory (default: lib/generated/ts)
//   --zod-import <pkg>    Zod import path (default: zod)
//   --no-index            Skip generating index.ts barrel
//   --watch               Watch mode (re-generate on file changes)
//   --help, -h            Show this help

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:dart_ts_generator/src/model_analyzer.dart';
import 'package:dart_ts_generator/src/zod_generator.dart';
import 'package:dart_ts_generator/src/cross_file_registry.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('out',
        abbr: 'o',
        defaultsTo: 'lib/generated/ts',
        help: 'Output directory for generated .ts files')
    ..addOption('zod-import',
        defaultsTo: 'zod', help: 'Zod package import path')
    ..addFlag('index',
        defaultsTo: true,
        negatable: true,
        help: 'Generate index.ts barrel file')
    ..addFlag('watch',
        abbr: 'w',
        defaultsTo: false,
        help: 'Watch mode: re-run on file changes')
    ..addFlag('verbose', abbr: 'v', defaultsTo: false)
    ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

  final parsed = parser.parse(args);

  if (parsed['help'] as bool || parsed.rest.isEmpty) {
    _printUsage(parser);
    exit(parsed['help'] as bool ? 0 : 1);
  }

  final outDir = parsed['out'] as String;
  final zodImport = parsed['zod-import'] as String;
  final generateIndex = parsed['index'] as bool;
  final watchMode = parsed['watch'] as bool;
  final verbose = parsed['verbose'] as bool;

  final config = GeneratorConfig(
    outputDir: outDir,
    generateIndex: generateIndex,
    zodImport: zodImport,
  );

  final inputs = parsed.rest;

  // Resolve input paths
  final dartFiles = <String>[];
  for (final input in inputs) {
    final entity = FileSystemEntity.typeSync(input);
    if (entity == FileSystemEntityType.file && input.endsWith('.dart')) {
      dartFiles.add(p.absolute(input));
    } else if (entity == FileSystemEntityType.directory) {
      dartFiles.addAll(_findDartFiles(input));
    } else {
      stderr
          .writeln('Warning: skipping $input (not a .dart file or directory)');
    }
  }

  if (dartFiles.isEmpty) {
    stderr.writeln('Error: no .dart files found.');
    exit(1);
  }

  Future<void> runGeneration() async {
    if (verbose) print('Analyzing ${dartFiles.length} file(s)...');
    await _generate(dartFiles, config, verbose);
  }

  await runGeneration();

  if (watchMode) {
    print('Watching for changes...');
    final watched = dartFiles.map(p.dirname).toSet();
    for (final dir in watched) {
      Directory(dir).watch(recursive: true).listen((event) async {
        if (event.path.endsWith('.dart')) {
          print('Changed: ${event.path}');
          await runGeneration();
        }
      });
    }
    // Keep alive
    await Future<void>.delayed(const Duration(days: 365));
  }
}

Future<void> _generate(
  List<String> dartFiles,
  GeneratorConfig config,
  bool verbose,
) async {
  final collection = AnalysisContextCollection(
    includedPaths: dartFiles,
  );

  final registry = CrossFileRegistry();
  final pendingOutputs = <String, String>{}; // outputPath → content

  // Phase 1: Analyze all files, build cross-file registry
  final allClassInfosByFile = <String, List<ClassInfo>>{};

  for (final filePath in dartFiles) {
    try {
      final context = collection.contextFor(filePath);
      final result = await context.currentSession.getResolvedLibrary(filePath);

      if (result is! ResolvedLibraryResult) continue;
      final library = result.element;

      final classInfos = _analyzeLibrary(library);
      if (classInfos.isEmpty) continue;

      final outputPath = _outputPathFor(filePath, config.outputDir);
      allClassInfosByFile[outputPath] = classInfos;

      // Register types for cross-file resolution
      registry.registerTypes(
          outputPath, classInfos.map((c) => c.name!).toList());

      if (verbose) {
        print('  Found ${classInfos.length} types in ${p.basename(filePath)}');
      }
    } catch (e) {
      stderr.writeln('Error analyzing $filePath: $e');
    }
  }

  // Phase 2: Generate output (now that registry is fully populated)
  for (final entry in allClassInfosByFile.entries) {
    final outputPath = entry.key;
    final classInfos = entry.value;

    final classRegistry = {for (final c in classInfos) c.name!: c};

    final gen = ZodSchemaGenerator(
      classRegistry: classRegistry,
      config: config,
      crossFileRegistry: registry,
      currentOutputFile: outputPath,
    );

    pendingOutputs[outputPath] = gen.generateFile(classInfos);
  }

  // Phase 3: Write files
  final outputDir = Directory(config.outputDir);
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  final writtenFiles = <String>[];
  for (final entry in pendingOutputs.entries) {
    final file = File(entry.key);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
    writtenFiles.add(entry.key);
    if (verbose) print('  Wrote: ${entry.key}');
  }

  // Phase 4: Generate index barrel
  if (config.generateIndex && writtenFiles.isNotEmpty) {
    final indexPath = p.join(config.outputDir, 'index.ts');
    final indexContent = IndexBarrelGenerator.generate(writtenFiles, indexPath);
    File(indexPath).writeAsStringSync(indexContent);
    if (verbose) print('  Wrote: $indexPath');
  }

  print('✓ Generated ${writtenFiles.length} file(s) → ${config.outputDir}');
}

List<ClassInfo> _analyzeLibrary(LibraryElement library) {
  final allElements = <InterfaceElement>[];

  for (final element in library.children) {
    if (element is EnumElement) allElements.add(element);
    if (element is ClassElement) allElements.add(element);
  }

  // Filter to only annotated or json_serializable classes
  final relevant = allElements.where((e) {
    if (e.name!.startsWith('_')) return false;
    return _hasJsonSerializable(e) || _hasTsAnnotation(e);
  }).toList();

  if (relevant.isEmpty) return [];

  final knownModelNames = relevant.map((e) => e.name!).toSet();
  final knownEnumNames =
      relevant.whereType<EnumElement>().map((e) => e.name!).toSet();

  final analyzer = ModelAnalyzer(
    knownModelNames: knownModelNames,
    knownEnumNames: knownEnumNames,
  );

  final result = <ClassInfo>[];
  for (final element in relevant) {
    try {
      if (element is EnumElement) {
        final values = element.fields
            .where((f) => f.isEnumConstant)
            .map((f) => f.name)
            .toList();
        result.add(ClassInfo(
          name: element.name,
          fields: [],
          isEnum: true,
          enumValues: values,
          isAbstract: false,
        ));
      } else if (element is ClassElement) {
        result.add(analyzer.analyzeClass(element));
      }
    } catch (e) {
      stderr.writeln('Warning: failed to analyze ${element.name}: $e');
    }
  }

  return result;
}

bool _hasJsonSerializable(InterfaceElement element) {
  // analyzer >=6.x: element.metadata is List<ElementAnnotation> directly.
  return element.metadata.annotations.any((m) {
    final name = m.element?.enclosingElement?.name ?? m.element?.name ?? '';
    return name == 'JsonSerializable';
  });
}

bool _hasTsAnnotation(InterfaceElement element) {
  return element.metadata.annotations.any((m) {
    final name = m.element?.enclosingElement?.name ?? '';
    return name == 'TsGenerate' || name == 'TsFirestoreModel';
  });
}

String _outputPathFor(String dartFilePath, String outputDir) {
  final base = p.basenameWithoutExtension(dartFilePath);
  return p.join(outputDir, '$base.g.ts');
}

List<String> _findDartFiles(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !p.basename(f.path).startsWith('_'))
      .map((f) => p.absolute(f.path))
      .toList();
}

void _printUsage(ArgParser parser) {
  print('''
dart_ts_generator — Generate TypeScript/Zod schemas from Dart models

Usage:
  dart run dart_ts_generator:dart_ts_gen [options] <path>

  <path> can be a single .dart file or a directory (searched recursively).

${parser.usage}

Examples:
  # Generate from a single file
  dart run dart_ts_generator:dart_ts_gen lib/models/user.dart

  # Generate from entire models directory
  dart run dart_ts_generator:dart_ts_gen -o src/types lib/models/

  # Custom Zod import path (e.g. monorepo)
  dart run dart_ts_generator:dart_ts_gen --zod-import @myapp/zod lib/models/

  # Watch mode
  dart run dart_ts_generator:dart_ts_gen --watch lib/models/
''');
}
