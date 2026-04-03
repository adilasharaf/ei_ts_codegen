import 'package:test/test.dart';
import 'package:dart_ts_generator/src/zod_generator.dart';
import 'package:dart_ts_generator/src/model_analyzer.dart';
import 'package:dart_ts_generator/src/type_mapping.dart';
import 'package:dart_ts_generator/src/source_parser.dart';
import 'package:dart_ts_generator/src/cross_file_registry.dart';

void main() {
  // ─────────────────────────────────────────────────────────
  group('TypeMapping — primitives', () {
    test('maps all primitive Dart types', () {
      expect(TypeMapping.resolveZod('String'), 'z.string()');
      expect(TypeMapping.resolveZod('int'), 'z.number().int()');
      expect(TypeMapping.resolveZod('double'), 'z.number()');
      expect(TypeMapping.resolveZod('num'), 'z.number()');
      expect(TypeMapping.resolveZod('bool'), 'z.boolean()');
      expect(TypeMapping.resolveZod('dynamic'), 'z.any()');
      expect(TypeMapping.resolveZod('Object'), 'z.unknown()');
    });

    test('appends .optional() for nullable', () {
      expect(TypeMapping.resolveZod('String', isNullable: true), 'z.string().optional()');
      expect(TypeMapping.resolveZod('bool', isNullable: true), 'z.boolean().optional()');
    });

    test('appends .default() when provided', () {
      expect(TypeMapping.resolveZod('double', defaultValue: '0'), 'z.number().default(0)');
      expect(TypeMapping.resolveZod('bool', defaultValue: 'false'), 'z.boolean().default(false)');
    });

    test('nullable + default together', () {
      final result = TypeMapping.resolveZod('String', isNullable: true, defaultValue: '"x"');
      expect(result, 'z.string().optional().default("x")');
    });
  });

  // ─────────────────────────────────────────────────────────
  group('TypeMapping — collections', () {
    test('List<String>', () {
      expect(TypeMapping.resolveZod('List', typeArgs: ['String']), 'z.array(z.string())');
    });

    test('nullable List', () {
      expect(
        TypeMapping.resolveZod('List', typeArgs: ['String'], isNullable: true),
        'z.array(z.string()).optional()',
      );
    });

    test('Map<String, dynamic>', () {
      expect(TypeMapping.resolveZod('Map', typeArgs: ['String', 'dynamic']), 'z.record(z.any())');
    });
  });

  // ─────────────────────────────────────────────────────────
  group('TypeMapping — Firestore types', () {
    test('Timestamp gets transform', () {
      final result = TypeMapping.resolveZod('Timestamp');
      expect(result, contains('z.any().transform'));
      expect(result, contains('toDate'));
    });

    test('GeoPoint is opaque', () {
      expect(TypeMapping.resolveZod('GeoPoint'), 'z.any()');
    });
  });

  // ─────────────────────────────────────────────────────────
  group('TypeMapping — converters', () {
    test('DateTimeNullableConverter emits nullable transform', () {
      final result = TypeMapping.resolveZod(
        'DateTime',
        converterClass: 'DateTimeNullableConverter',
        isNullable: true,
      );
      expect(result, contains('z.any().transform'));
      expect(result, contains('.optional()'));
    });

    test('DateTimeListConverter wraps in array', () {
      final result = TypeMapping.resolveZod(
        'DateTime',
        converterClass: 'DateTimeListConverter',
        isList: true,
      );
      expect(result, contains('z.array('));
      expect(result, contains('z.any().transform'));
    });

    test('unknown converter → z.any()', () {
      expect(
        TypeMapping.resolveZod('MyType', converterClass: 'WeirdCustomConverter'),
        'z.any()',
      );
    });
  });

  // ─────────────────────────────────────────────────────────
  group('TypeMapping — literal defaults', () {
    test('numeric', () {
      expect(TypeMapping.resolveLiteralDefault('0'), '0');
      expect(TypeMapping.resolveLiteralDefault('3.14'), '3.14');
    });

    test('boolean', () {
      expect(TypeMapping.resolveLiteralDefault('true'), 'true');
      expect(TypeMapping.resolveLiteralDefault('false'), 'false');
    });

    test('empty collections', () {
      expect(TypeMapping.resolveLiteralDefault('[]'), '[]');
      expect(TypeMapping.resolveLiteralDefault('{}'), '{}');
    });

    test('enum extracts last segment', () {
      expect(TypeMapping.resolveLiteralDefault('EiAppSource.other'), '"other"');
    });

    test('null returns null', () {
      expect(TypeMapping.resolveLiteralDefault('null'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────
  group('SourceParser — constructor defaults', () {
    test('extracts numeric defaults', () {
      const source = '''
class MyModel {
  MyModel({
    this.count = 0,
    this.score = 3.14,
  });
}
''';
      final d = ConstructorDefaultExtractor.extract(source);
      expect(d['count'], '0');
      expect(d['score'], '3.14');
    });

    test('extracts boolean defaults', () {
      const source = '''
class MyModel {
  MyModel({this.isActive = true, this.isDeleted = false});
}
''';
      final d = ConstructorDefaultExtractor.extract(source);
      expect(d['isActive'], 'true');
      expect(d['isDeleted'], 'false');
    });

    test('strips const from const []', () {
      const source = '''
class MyModel {
  MyModel({this.tags = const []});
}
''';
      final d = ConstructorDefaultExtractor.extract(source);
      expect(d['tags'], '[]');
    });

    test('extracts enum defaults', () {
      const source = '''
class MyModel {
  MyModel({this.status = MyStatus.active});
}
''';
      final d = ConstructorDefaultExtractor.extract(source);
      expect(d['status'], 'MyStatus.active');
    });

    test('empty map when no constructor', () {
      expect(ConstructorDefaultExtractor.extract('class Empty {}'), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────
  group('CrossFileRegistry', () {
    late CrossFileRegistry registry;

    setUp(() {
      registry = CrossFileRegistry();
      registry.registerTypes('lib/generated/ts/ei_model.g.ts', ['EiModel', 'EiAppSource']);
      registry.registerTypes('lib/generated/ts/ei_user.g.ts', ['EiUser']);
    });

    test('fileForType returns correct file', () {
      expect(registry.fileForType('EiModel'), 'lib/generated/ts/ei_model.g.ts');
      expect(registry.fileForType('Unknown'), isNull);
    });

    test('importPathFor returns null for same-file type', () {
      expect(
        registry.importPathFor('lib/generated/ts/ei_model.g.ts', 'EiModel'),
        isNull,
      );
    });

    test('importPathFor returns relative path for cross-file type', () {
      expect(
        registry.importPathFor('lib/generated/ts/ei_user.g.ts', 'EiModel'),
        './ei_model.g',
      );
    });
  });

  // ─────────────────────────────────────────────────────────
  group('ZodSchemaGenerator — enums', () {
    test('generates z.enum() with values quoted', () {
      final e = ClassInfo(
        name: 'EiAppSource',
        fields: [],
        isEnum: true,
        enumValues: ['admin', 'user', 'other'],
        isAbstract: false,
      );
      final gen = ZodSchemaGenerator(
        classRegistry: {'EiAppSource': e},
        config: const GeneratorConfig(),
      );
      final out = gen.generateFile([e]);
      expect(out, contains('z.enum(["admin", "user", "other"])'));
      expect(out, contains('export const EiAppSourceSchema'));
      expect(out, contains('export type EiAppSource = z.infer'));
    });
  });

  // ─────────────────────────────────────────────────────────
  group('ZodSchemaGenerator — models', () {
    FieldInfo f(String name, String type,
        {bool nullable = false, String? def, bool isList = false,
         bool isEnum = false, bool isModel = false,
         List<String> typeArgs = const [],
         String? converter, String? fromJson}) =>
        FieldInfo(
          dartName: name, tsName: name, dartTypeName: type,
          typeArgs: typeArgs, isNullable: nullable, isIgnored: false,
          defaultValue: def, converterClass: converter, fromJson: fromJson,
          isEnum: isEnum, isList: isList, isMap: false, isModel: isModel,
        );

    ZodSchemaGenerator makeGen(Map<String, ClassInfo> registry) =>
        ZodSchemaGenerator(classRegistry: registry, config: const GeneratorConfig());

    test('standalone model uses z.object()', () {
      final m = ClassInfo(
        name: 'Address',
        fields: [f('street', 'String', nullable: true)],
        isEnum: false, enumValues: [], isAbstract: false,
      );
      final out = makeGen({'Address': m}).generateFile([m]);
      expect(out, contains('AddressSchema = z.object({'));
      expect(out, contains('street: z.string().optional()'));
    });

    test('child model uses ParentSchema.extend()', () {
      final base = ClassInfo(name: 'Base', fields: [f('id', 'String')],
          isEnum: false, enumValues: [], isAbstract: false);
      final child = ClassInfo(name: 'Child', superclassName: 'Base',
          fields: [f('extra', 'String')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'Base': base, 'Child': child}).generateFile([base, child]);
      expect(out, contains('ChildSchema = BaseSchema.extend({'));
    });

    test('topological sort: child passed first, parent declared first', () {
      final base = ClassInfo(name: 'Base', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final child = ClassInfo(name: 'Child', superclassName: 'Base', fields: [],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'Base': base, 'Child': child}).generateFile([child, base]);
      expect(out.indexOf('BaseSchema'), lessThan(out.indexOf('ChildSchema')));
    });

    test('three-level chain sorts A < B < C', () {
      final a = ClassInfo(name: 'A', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final b = ClassInfo(name: 'B', superclassName: 'A', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final c = ClassInfo(name: 'C', superclassName: 'B', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'A': a, 'B': b, 'C': c}).generateFile([c, b, a]);
      final aI = out.indexOf('const ASchema');
      final bI = out.indexOf('const BSchema');
      final cI = out.indexOf('const CSchema');
      expect(aI, lessThan(bI));
      expect(bI, lessThan(cI));
    });

    test('default value emitted via .default()', () {
      final m = ClassInfo(name: 'M', fields: [f('count', 'int', def: '0')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains('count: z.number().int().default(0)'));
    });

    test('List<String> with default []', () {
      final m = ClassInfo(name: 'M',
          fields: [f('tags', 'List', isList: true, typeArgs: ['String'], def: '[]')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains('z.array(z.string()).default([])'));
    });

    test('nested model field references schema', () {
      final addr = ClassInfo(name: 'Address', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final user = ClassInfo(name: 'User',
          fields: [f('address', 'Address', nullable: true, isModel: true)],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'Address': addr, 'User': user}).generateFile([addr, user]);
      expect(out, contains('address: AddressSchema.optional()'));
    });

    test('fromJson field becomes z.any()', () {
      final m = ClassInfo(name: 'M',
          fields: [f('geoPoint', 'GeoPoint', nullable: true, fromJson: '__custom__')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains('geoPoint: z.any().optional()'));
    });

    test('DateTimeNullableConverter field', () {
      final m = ClassInfo(name: 'M',
          fields: [f('addedOn', 'DateTime', nullable: true, converter: 'DateTimeNullableConverter')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains('z.any().transform'));
      expect(out, contains('.optional()'));
    });

    test('DateTimeListConverter field wraps in array', () {
      final field = FieldInfo(
        dartName: 'checkpointTimes', tsName: 'checkpoint_times',
        dartTypeName: 'List', typeArgs: ['DateTime'],
        isNullable: false, isIgnored: false,
        converterClass: 'DateTimeListConverter', defaultValue: '[]',
        isEnum: false, isList: true, isMap: false, isModel: false,
      );
      final m = ClassInfo(name: 'M', fields: [field], isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains('z.array('));
      expect(out, contains('z.any().transform'));
      expect(out, contains('.default([])'));
    });

    test('enum field with default', () {
      final status = ClassInfo(name: 'Status', fields: [], isEnum: true,
          enumValues: ['active', 'inactive'], isAbstract: false);
      final m = ClassInfo(name: 'M',
          fields: [f('status', 'Status', isEnum: true, def: '"active"')],
          isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'Status': status, 'M': m}).generateFile([status, m]);
      expect(out, contains('status: StatusSchema.default("active")'));
    });

    test('output includes zod import header', () {
      final m = ClassInfo(name: 'M', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final out = makeGen({'M': m}).generateFile([m]);
      expect(out, contains("import { z } from 'zod'"));
    });

    test('custom zodImport config is respected', () {
      final m = ClassInfo(name: 'M', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final gen = ZodSchemaGenerator(
        classRegistry: {'M': m},
        config: const GeneratorConfig(zodImport: '@myapp/zod'),
      );
      final out = gen.generateFile([m]);
      expect(out, contains("import { z } from '@myapp/zod'"));
    });
  });

  // ─────────────────────────────────────────────────────────
  group('ZodSchemaGenerator — cross-file imports', () {
    test('emits import statement for external parent', () {
      final registry = CrossFileRegistry();
      registry.registerTypes('lib/generated/ts/ei_model.g.ts', ['EiModel']);
      registry.registerTypes('lib/generated/ts/ei_user.g.ts', ['EiUser']);

      final eiModel = ClassInfo(name: 'EiModel', fields: [], isEnum: false, enumValues: [], isAbstract: false);
      final eiUser = ClassInfo(name: 'EiUser', superclassName: 'EiModel', fields: [],
          isEnum: false, enumValues: [], isAbstract: false);

      final gen = ZodSchemaGenerator(
        classRegistry: {'EiModel': eiModel, 'EiUser': eiUser},
        config: const GeneratorConfig(),
        crossFileRegistry: registry,
        currentOutputFile: 'lib/generated/ts/ei_user.g.ts',
      );

      final out = gen.generateFile([eiUser]);
      expect(out, contains("import { EiModelSchema } from './ei_model.g'"));
    });
  });

  // ─────────────────────────────────────────────────────────
  group('IndexBarrelGenerator', () {
    test('re-exports all provided files', () {
      final files = [
        'lib/generated/ts/ei_model.g.ts',
        'lib/generated/ts/ei_user.g.ts',
      ];
      final content = IndexBarrelGenerator.generate(files, 'lib/generated/ts/index.ts');
      expect(content, contains("export * from './ei_model.g'"));
      expect(content, contains("export * from './ei_user.g'"));
      expect(content, contains('DO NOT EDIT'));
    });
  });

  // ─────────────────────────────────────────────────────────
  group('GeneratorConfig', () {
    test('defaults', () {
      final c = GeneratorConfig.fromMap({});
      expect(c.outputDir, 'lib/generated/ts');
      expect(c.zodImport, 'zod');
      expect(c.generateIndex, isTrue);
      expect(c.firestoreTransforms, isTrue);
    });

    test('custom values', () {
      final c = GeneratorConfig.fromMap({
        'output_dir': 'src/types',
        'zod_import': '@myapp/zod',
        'generate_index': false,
      });
      expect(c.outputDir, 'src/types');
      expect(c.zodImport, '@myapp/zod');
      expect(c.generateIndex, isFalse);
    });
  });
}
