import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

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

  static const _converterOverrides = {
    'DateTimeNullableConverter': 'Date | undefined',
    'DateTimeConverter': 'Date',
    'TimestampConverter': 'Timestamp',
  };

  /// Maps a Dart DartType to a TypeScript type string.
  static String map(DartType type, {bool nullable = false}) {
    final suffix = nullable ? ' | undefined' : '';

    // Handle null itself
    if (type.isDartCoreNull) return 'null';

    // Unwrap nullable wrapper (Dart 3 style — T?)
    if (type is InterfaceType &&
        type.nullabilitySuffix == NullabilitySuffix.question) {
      return '${map(type, nullable: false)} | undefined';
    }

    // Primitives
    final typeName = type.element?.name ?? '';
    if (_primitives.containsKey(typeName)) {
      return _primitives[typeName]! + suffix;
    }

    // DateTime → Date
    if (typeName == 'DateTime') return 'Date$suffix';

    // Firestore Timestamp (from cloud_firestore)
    if (typeName == 'Timestamp') return 'Timestamp$suffix';

    // List<T>
    if (type is InterfaceType && typeName == 'List') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first)
          : 'unknown';
      return '$inner[]$suffix';
    }

    // Map<K, V>
    if (type is InterfaceType && typeName == 'Map') {
      final key =
          type.typeArguments.isNotEmpty ? map(type.typeArguments[0]) : 'string';
      final val = type.typeArguments.length > 1
          ? map(type.typeArguments[1])
          : 'unknown';
      return 'Record<$key, $val>$suffix';
    }

    // Set<T>
    if (type is InterfaceType && typeName == 'Set') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first)
          : 'unknown';
      return 'Set<$inner>$suffix';
    }

    // Future<T> → Promise<T>
    if (type is InterfaceType && typeName == 'Future') {
      final inner = type.typeArguments.isNotEmpty
          ? map(type.typeArguments.first)
          : 'void';
      return 'Promise<$inner>$suffix';
    }

    // All other types (assumed to be model classes)
    return '$typeName$suffix';
  }

  /// Checks if a field has a custom converter annotation and returns its TS type.
  static String? converterOverride(FieldElement field) {
    for (final meta in field.metadata.annotations) {
      final name = meta.element?.enclosingElement?.name ?? '';
      if (_converterOverrides.containsKey(name)) {
        return _converterOverrides[name];
      }
    }
    return null;
  }

  /// Gets the @JsonKey name override for a field, if any.
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
}
