import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

/// Describes how a field should be decorated and typed in TypeScript.
class FieldMapping {
  final String tsType;
  final String baseType;
  final bool isOptional;
  final bool isArray;
  final bool isDate;
  final bool isEmail;
  final bool isGeoPoint;
  final bool isNested; // model class
  final bool isEnum;
  final bool hasConverter; // explicit Dart converter annotation

  const FieldMapping({
    required this.tsType,
    required this.baseType,
    required this.isOptional,
    required this.isArray,
    required this.isDate,
    required this.isEmail,
    required this.isGeoPoint,
    required this.isNested,
    required this.isEnum,
    required this.hasConverter,
  });
}

class TypeMapper {
  static const _primitives = {
    'String': 'string',
    'int': 'number',
    'double': 'number',
    'num': 'number',
    'bool': 'boolean',
    'dynamic': 'unknown',
    'Object': 'unknown',
    'void': 'void',
    'Never': 'never',
  };

  /// Converter annotation name → TS type override.
  static const _converterOverrides = {
    'DateTimeNullableConverter': 'Date | undefined',
    'DateTimeConverter': 'Date',
    'TimestampConverter': 'Timestamp',
    'GeoPointConverter': 'GeoPoint',
  };

  /// Maps a Dart DartType to a TypeScript type string.
  static String map(DartType type, {bool forceNonNull = false}) {
    final isNullable =
        !forceNonNull && type.nullabilitySuffix == NullabilitySuffix.question;
    final suffix = isNullable ? ' | undefined' : '';

    if (type.isDartCoreNull) return 'null';

    final typeName = type.element?.name ?? '';

    if (_primitives.containsKey(typeName)) {
      return _primitives[typeName]! + suffix;
    }

    if (typeName == 'DateTime') return 'Date$suffix';
    if (typeName == 'Timestamp') return 'Timestamp$suffix';
    if (typeName == 'GeoPoint') return 'GeoPoint$suffix';

    if (type is InterfaceType && typeName == 'List') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first, forceNonNull: true)
          : 'unknown';
      return '$inner[]$suffix';
    }

    if (type is InterfaceType && typeName == 'Map') {
      final key = type.typeArguments.isNotEmpty
          ? map(type.typeArguments[0], forceNonNull: true)
          : 'string';
      final val = type.typeArguments.length > 1
          ? map(type.typeArguments[1], forceNonNull: true)
          : 'unknown';
      return 'Record<$key, $val>$suffix';
    }

    if (type is InterfaceType && typeName == 'Set') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first, forceNonNull: true)
          : 'unknown';
      return 'Set<$inner>$suffix';
    }

    if (type is InterfaceType && typeName == 'Future') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first, forceNonNull: true)
          : 'void';
      return 'Promise<$inner>$suffix';
    }

    return '$typeName$suffix';
  }

  /// Returns the TS type if a converter annotation is present, else null.
  static String? converterOverride(FieldElement field) {
    for (final meta in field.metadata.annotations) {
      final name = meta.element?.enclosingElement?.name ?? '';
      if (_converterOverrides.containsKey(name)) {
        return _converterOverrides[name];
      }
    }
    return null;
  }

  /// Returns @JsonKey(name:) override if present.
  static String? jsonKeyName(FieldElement field) {
    for (final meta in field.metadata.annotations) {
      if (meta.element?.enclosingElement?.name == 'JsonKey') {
        final reader = ConstantReader(meta.computeConstantValue());
        final name = reader.peek('name');
        if (name != null && !name.isNull) return name.stringValue;
      }
    }
    return null;
  }

  /// Returns true if the field has an @Email / @IsEmail annotation.
  static bool hasEmailAnnotation(FieldElement field) {
    return field.metadata.annotations.any((a) {
      final n = a.element?.enclosingElement?.name ?? a.element?.name ?? '';
      return n == 'Email' || n == 'IsEmail';
    });
  }

  /// Checks whether a type name looks like a GeoPoint.
  static bool _isGeoPointType(String typeName) => typeName == 'GeoPoint';

  /// Full field analysis — returns a [FieldMapping] describing decorators needed.
  static FieldMapping analyze(
    FieldElement field,
    Set<String> modelNames,
    Set<String> enumNames,
  ) {
    final converterType = converterOverride(field);
    final rawTsType = converterType ?? map(field.type);
    final isOptional =
        field.type.nullabilitySuffix == NullabilitySuffix.question ||
            rawTsType.contains('| undefined');

    // Strip nullability suffix and array suffix to get the base element type.
    final strippedType =
        rawTsType.replaceAll(' | undefined', '').replaceAll('?', '');
    final isArray = strippedType.endsWith('[]');
    final baseType = isArray ? strippedType.replaceAll('[]', '') : strippedType;

    final isDate = baseType == 'Date';
    final isGeoPoint = _isGeoPointType(baseType);
    final isEmail = hasEmailAnnotation(field);
    final isEnum = enumNames.contains(baseType);
    final isNested = modelNames.contains(baseType);

    return FieldMapping(
      tsType: rawTsType,
      baseType: baseType,
      isOptional: isOptional,
      isArray: isArray,
      isDate: isDate,
      isEmail: isEmail,
      isGeoPoint: isGeoPoint,
      isNested: isNested,
      isEnum: isEnum,
      hasConverter: converterType != null,
    );
  }
}
