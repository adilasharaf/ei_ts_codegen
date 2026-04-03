import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'type_mapper.dart';

class ModelEmitter {
  /// Extract serializable metadata from a ClassElement into plain JSON
  /// so it can be cached and passed between builder phases.
  static Map<String, dynamic> extractMetadata(ClassElement cls) {
    final fields = <Map<String, dynamic>>[];

    for (final field in cls.fields) {
      if (field.isStatic) continue;
      if ((field.firstFragment.nameOffset ?? 0) < 0) continue;
      if (field.name == 'hashCode' || field.name == 'runtimeType') continue;

      final converterType = TypeMapper.converterOverride(field);
      final jsonName = TypeMapper.jsonKeyName(field) ?? field.name;
      final tsType = converterType ?? TypeMapper.map(field.type);
      final isOptional =
          field.type.nullabilitySuffix == NullabilitySuffix.question ||
              tsType.contains('| undefined');

      final stripped = tsType.replaceAll(' | undefined', '');
      final isArray = stripped.endsWith('[]');
      final baseType = isArray ? stripped.replaceAll('[]', '') : stripped;

      final isDate = baseType == 'Date';
      final isGeoPoint = baseType == 'GeoPoint';
      final isEmail = TypeMapper.hasEmailAnnotation(field);

      // A field has a definite initializer if Dart declares a default value.
      // Required fields WITHOUT an initializer need ! in the TS declaration.
      final hasDefault = field.hasInitializer;

      fields.add({
        'name': field.name,
        'jsonName': jsonName,
        'tsType': tsType,
        'baseType': baseType,
        'isOptional': isOptional,
        'isArray': isArray,
        'isDate': isDate,
        'isGeoPoint': isGeoPoint,
        'isEmail': isEmail,
        'hasDefault': hasDefault,
        'hasConverter': converterType != null,
      });
    }

    final superName = cls.supertype?.element.name;
    final extendsClass =
        (superName != null && superName != 'Object') ? superName : null;
    final hasCopy = extendsClass != null;

    return {
      'name': cls.name,
      'fields': fields,
      'extends': extendsClass,
      'hasCopy': hasCopy,
    };
  }

  // ---------------------------------------------------------------------------
  // Topological sort (Kahn's BFS)
  // ---------------------------------------------------------------------------
  // Guarantees every superclass and every nested model field type is declared
  // before the class that references it, regardless of glob order.
  // ---------------------------------------------------------------------------
  static List<Map<String, dynamic>> _topoSort(
    List<Map<String, dynamic>> models,
  ) {
    final modelNames = {for (final m in models) m['name'] as String};

    final deps = <String, Set<String>>{};
    for (final m in models) {
      final name = m['name'] as String;
      final before = <String>{};
      final ext = m['extends'] as String?;
      if (ext != null && modelNames.contains(ext)) before.add(ext);
      for (final f in (m['fields'] as List).cast<Map<String, dynamic>>()) {
        final base = f['baseType'] as String;
        if (modelNames.contains(base) && base != name) before.add(base);
      }
      deps[name] = before;
    }

    final inDegree = <String, int>{
      for (final m in models) (m['name'] as String): deps[m['name']]!.length,
    };

    final dependents = <String, List<String>>{
      for (final m in models) (m['name'] as String): [],
    };
    for (final entry in deps.entries) {
      for (final dep in entry.value) {
        dependents.putIfAbsent(dep, () => []).add(entry.key);
      }
    }

    final queue = <String>[
      for (final e in inDegree.entries)
        if (e.value == 0) e.key,
    ]..sort();

    final byName = {for (final m in models) m['name'] as String: m};
    final sorted = <Map<String, dynamic>>[];

    while (queue.isNotEmpty) {
      queue.sort();
      final name = queue.removeAt(0);
      sorted.add(byName[name]!);
      for (final dependent in dependents[name] ?? []) {
        inDegree[dependent] = (inDegree[dependent] ?? 1) - 1;
        if (inDegree[dependent] == 0) queue.add(dependent);
      }
    }

    // Fallback: append any nodes left in a cycle rather than crashing.
    final emitted = sorted.map((m) => m['name'] as String).toSet();
    for (final m in models) {
      if (!emitted.contains(m['name'] as String)) sorted.add(m);
    }

    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Emit
  // ---------------------------------------------------------------------------

  static String emit(
    List<Map<String, dynamic>> models,
    List<Map<String, dynamic>> enums,
  ) {
    final enumNames = enums.map((e) => e['name'] as String).toSet();
    final modelNames = models.map((m) => m['name'] as String).toSet();
    final sorted = _topoSort(models);

    final buf = StringBuffer();
    buf.writeln('// Auto-generated by ts_codegen. Do not edit manually.');
    buf.writeln();

    // ── Imports ──────────────────────────────────────────────────────────────
    //
    // class-transformer / class-validator: named imports (small, stable set).
    //
    // Utils and Enums use namespace imports (`import * as X`) so that:
    //   • Utils: no matter how many decorator helpers exist, the import line
    //     never needs updating — Utils.TransformDate, Utils.OptionalNested, etc.
    //   • Enums: avoids the 300-character named-import line when a project has
    //     dozens of enums; enum values are accessed as Enums.MyEnum.
    buf.writeln(
        'import { Type, instanceToPlain, plainToInstance } from "class-transformer";');
    buf.writeln(
        'import { IsArray, IsBoolean, IsEmail, IsEnum, IsNumber, IsString, ValidateNested } from "class-validator";');
    buf.writeln('import * as Utils from "./utils";');

    if (enumNames.isNotEmpty) {
      buf.writeln('import * as Enums from "./enums";');
    }

    buf.writeln();

    for (final model in sorted) {
      buf.write(_emitClass(model, modelNames, enumNames));
    }

    return buf.toString();
  }

  static String _emitClass(
    Map<String, dynamic> model,
    Set<String> modelNames,
    Set<String> enumNames,
  ) {
    final name = model['name'] as String;
    final fields = (model['fields'] as List).cast<Map<String, dynamic>>();
    final extendsClass = model['extends'] as String?;
    final hasCopy = model['hasCopy'] as bool? ?? false;
    final buf = StringBuffer();

    final extendsPart = extendsClass != null ? ' extends $extendsClass' : '';
    buf.writeln('export class $name$extendsPart {');

    for (final f in fields) {
      _emitField(buf, f, modelNames, enumNames);
    }

    buf.writeln();
    buf.writeln('  constructor(data?: Partial<$name>) {');
    if (extendsClass != null) buf.writeln('    super(data);');
    buf.writeln('    if (data) {');
    buf.writeln('      Object.assign(this, data);');
    buf.writeln('    }');
    buf.writeln('  }');

    buf.writeln();
    buf.writeln('  static fromJson(json: unknown): $name {');
    buf.writeln('    return plainToInstance($name, json, {');
    buf.writeln('      exposeDefaultValues: true,');
    buf.writeln('      enableImplicitConversion: true,');
    buf.writeln('    });');
    buf.writeln('  }');

    buf.writeln();
    buf.writeln('  toJson(): Record<string, any> {');
    buf.writeln('    return instanceToPlain(this, {');
    buf.writeln('      exposeUnsetFields: false,');
    buf.writeln('      enableImplicitConversion: true,');
    buf.writeln('    });');
    buf.writeln('  }');

    if (hasCopy) {
      buf.writeln();
      buf.writeln('  static copy(r: $name): $name {');
      buf.writeln('    return $name.fromJson(instanceToPlain(r));');
      buf.writeln('  }');
    }

    buf.writeln('}');
    buf.writeln();

    return buf.toString();
  }

  static void _emitField(
    StringBuffer buf,
    Map<String, dynamic> field,
    Set<String> modelNames,
    Set<String> enumNames,
  ) {
    final name = field['name'] as String;
    final tsType = field['tsType'] as String;
    final baseType = field['baseType'] as String;
    final isOptional = field['isOptional'] as bool;
    final isArray = field['isArray'] as bool;
    final isDate = field['isDate'] as bool;
    final isGeoPoint = field['isGeoPoint'] as bool;
    final isEmail = field['isEmail'] as bool;
    final hasDefault = field['hasDefault'] as bool? ?? false;
    final isNested = modelNames.contains(baseType);
    final isEnum = enumNames.contains(baseType);

    // ── Decorators ────────────────────────────────────────────────────────────
    if (isNested) {
      if (isOptional) {
        // Utils namespace: Utils.OptionalNested
        buf.writeln('  @Utils.OptionalNested(() => $baseType)');
      } else if (isArray) {
        buf.writeln('  @IsArray()');
        buf.writeln('  @ValidateNested({ each: true })');
        buf.writeln('  @Type(() => $baseType)');
      } else {
        buf.writeln('  @ValidateNested()');
        buf.writeln('  @Type(() => $baseType)');
      }
    } else if (isDate) {
      if (isOptional) buf.writeln('  @Utils.OptionalValue()');
      if (isArray) {
        buf.writeln('  @Utils.TransformListDate()');
      } else {
        buf.writeln('  @Utils.TransformDate()');
      }
    } else if (isGeoPoint) {
      if (isOptional) buf.writeln('  @Utils.OptionalValue()');
      buf.writeln('  @Utils.TransformGeoPoint()');
    } else {
      if (isOptional) buf.writeln('  @Utils.OptionalValue()');

      if (isEnum) {
        // Enums namespace: Enums.MyEnum
        buf.writeln('  @IsEnum(Enums.$baseType)');
      } else if (isEmail) {
        buf.writeln('  @IsEmail()');
      } else if (isArray) {
        buf.writeln('  @IsArray()');
        buf.writeln('  @IsString({ each: true })');
      } else {
        switch (baseType) {
          case 'string':
            buf.writeln('  @IsString()');
            break;
          case 'number':
            buf.writeln('  @IsNumber()');
            break;
          case 'boolean':
            buf.writeln('  @IsBoolean()');
            break;
        }
      }
    }

    // ── Field declaration ─────────────────────────────────────────────────────
    //
    // TypeScript strict mode requires every non-optional field to be either:
    //   (a) assigned in the constructor, or
    //   (b) marked with ! (definite assignment assertion).
    //
    // Since class-transformer populates fields via Object.assign / plainToInstance
    // rather than explicit constructor assignments, we use:
    //   • optional fields (T?)  → `name?: T`          — already handled
    //   • fields with a Dart default value → `name: T` — TS infers assignment
    //   • required fields with no default  → `name!: T` — suppresses TS2564
    if (isOptional) {
      buf.writeln('  $name?: $tsType;');
    } else if (hasDefault) {
      buf.writeln('  $name: $tsType;');
    } else {
      // Definite assignment assertion: tells TS the value will be set by
      // plainToInstance / Object.assign before it is read.
      buf.writeln('  $name!: $tsType;');
    }

    buf.writeln();
  }
}
