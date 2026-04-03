import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'source_parser.dart';

/// Represents a parsed Dart field ready for code generation.
class FieldInfo {
  final String? dartName;
  final String tsName; // from @JsonKey(name:...)
  final String dartTypeName;
  final List<String> typeArgs;
  final bool isNullable;
  final bool isIgnored; // @TsIgnore or @JsonKey(ignore: true)
  final String? converterClass; // e.g. 'DateTimeNullableConverter'
  final String? defaultValue; // raw Dart literal
  final String? fromJson; // custom fromJson function name
  final String? toJson; // custom toJson function name
  final bool isEnum;
  final bool isList;
  final bool isMap;
  final bool isModel; // refers to another model class

  const FieldInfo({
    this.dartName,
    required this.tsName,
    required this.dartTypeName,
    required this.typeArgs,
    required this.isNullable,
    required this.isIgnored,
    this.converterClass,
    this.defaultValue,
    this.fromJson,
    this.toJson,
    required this.isEnum,
    required this.isList,
    required this.isMap,
    required this.isModel,
  });
}

/// Represents a parsed Dart class (model or enum).
class ClassInfo {
  final String name;
  final String? superclassName; // direct parent (if not Object)
  final List<FieldInfo> fields;
  final bool isEnum;
  final List<String> enumValues;
  final bool isAbstract;

  const ClassInfo({
    required this.name,
    this.superclassName,
    required this.fields,
    required this.isEnum,
    required this.enumValues,
    required this.isAbstract,
  });
}

/// Parses Dart [ClassElement] into [ClassInfo].
class ModelAnalyzer {
  /// Set of known model names in the current library (for isModel detection)
  final Set<String> knownModelNames;

  /// Set of known enum names
  final Set<String> knownEnumNames;

  /// Cache of constructor defaults per class (populated lazily from source)
  final Map<String, Map<String, String>> _constructorDefaultsCache = {};

  ModelAnalyzer({
    required this.knownModelNames,
    required this.knownEnumNames,
  });

  ClassInfo analyzeClass(ClassElement element) {
    if (element.isEnum) {
      return _analyzeEnum(element);
    }
    return _analyzeModel(element);
  }

  ClassInfo _analyzeEnum(ClassElement element) {
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

  ClassInfo _analyzeModel(ClassElement element) {
    final superName = _resolveSuperclass(element);
    final fields = <FieldInfo>[];

    for (final field in element.fields) {
      if (field.isStatic || field.isSynthetic) continue;
      final info = _analyzeField(field);
      if (info != null) fields.add(info);
    }

    return ClassInfo(
      name: element.name,
      superclassName: superName,
      fields: fields,
      isEnum: false,
      enumValues: [],
      isAbstract: element.isAbstract,
    );
  }

  String? _resolveSuperclass(ClassElement element) {
    final supertype = element.supertype;
    if (supertype == null) return null;
    final name = supertype.element.name;
    if (name == 'Object' || name == 'dynamic') return null;
    return name;
  }

  FieldInfo? _analyzeField(FieldElement field) {
    // Check for @TsIgnore
    if (_hasAnnotation(field, 'TsIgnore')) return null;

    // Parse @JsonKey annotation
    final jsonKey = _getAnnotation(field, 'JsonKey');
    bool isIgnored = false;
    String? jsonName;
    String? defaultValue;
    String? fromJson;
    String? toJson;
    bool includeFromJson = true;
    bool includeToJson = true;

    if (jsonKey != null) {
      isIgnored = _getBoolField(jsonKey, 'ignore') ??
          false ||
              _getBoolField(jsonKey, 'includeFromJson') == false ||
              _getBoolField(jsonKey, 'includeToJson') == false;

      // Check includeFromJson: false means skip
      includeFromJson = _getBoolField(jsonKey, 'includeFromJson') ?? true;
      includeToJson = _getBoolField(jsonKey, 'includeToJson') ?? true;

      if (!includeFromJson && !includeToJson) isIgnored = true;

      jsonName = _getStringField(jsonKey, 'name');
      defaultValue = _getDefaultValueLiteral(jsonKey);
      fromJson = _getFunctionName(jsonKey, 'fromJson');
      toJson = _getFunctionName(jsonKey, 'toJson');
    }

    if (isIgnored) return null;

    // Check for converter annotation on the field
    final converterClass = _detectConverter(field);

    // Parse type
    final typeInfo = _parseType(field.type);

    // Determine default from constructor if not from @JsonKey
    final constructorDefault = defaultValue ?? _getConstructorDefault(field);

    return FieldInfo(
      dartName: field.name,
      tsName: jsonName ?? _camelToSnakeOrKeep(field.name),
      dartTypeName: typeInfo.typeName,
      typeArgs: typeInfo.typeArgs,
      isNullable: typeInfo.isNullable,
      isIgnored: false,
      converterClass: converterClass,
      defaultValue: constructorDefault,
      fromJson: fromJson,
      toJson: toJson,
      isEnum: knownEnumNames.contains(typeInfo.typeName),
      isList: typeInfo.typeName == 'List' || typeInfo.typeName == 'Iterable',
      isMap: typeInfo.typeName == 'Map',
      isModel: _isModelType(typeInfo.typeName),
    );
  }

  _TypeInfo _parseType(DartType type) {
    final isNullable = type.nullabilitySuffix.toString().contains('question');

    if (type is ParameterizedType) {
      final name = type.element?.name ?? 'dynamic';
      final args =
          type.typeArguments.map((a) => _parseType(a).typeName).toList();
      return _TypeInfo(name, isNullable, args);
    }

    if (type is InterfaceType) {
      final name = type.element.name;
      final args =
          type.typeArguments.map((a) => _parseType(a).typeName).toList();
      return _TypeInfo(name, isNullable, args);
    }

    final name = type.element?.name ?? type.toString().replaceAll('?', '');
    return _TypeInfo(name, isNullable, []);
  }

  bool _isModelType(String typeName) {
    return knownModelNames.contains(typeName) &&
        !knownEnumNames.contains(typeName);
  }

  String? _detectConverter(FieldElement field) {
    for (final metadata in field.metadata) {
      final element = metadata.element;
      if (element == null) continue;

      String? className;
      if (element is ConstructorElement) {
        className = element.enclosingElement.name;
      } else if (element is PropertyAccessorElement) {
        className = element.returnType.element?.name;
      }

      if (className != null && _looksLikeConverter(className)) {
        return className;
      }
    }
    return null;
  }

  bool _looksLikeConverter(String name) {
    final lower = name.toLowerCase();
    return lower.contains('converter') ||
        lower.contains('transformer') ||
        lower.contains('serializer');
  }

  bool _hasAnnotation(FieldElement field, String annotationName) {
    return field.metadata.any((m) {
      final element = m.element;
      if (element is ConstructorElement) {
        return element.enclosingElement.name == annotationName;
      }
      if (element is PropertyAccessorElement) {
        return element.name == annotationName;
      }
      return false;
    });
  }

  ElementAnnotation? _getAnnotation(FieldElement field, String name) {
    for (final meta in field.metadata) {
      final element = meta.element;
      String? className;
      if (element is ConstructorElement) {
        className = element.enclosingElement.name;
      } else if (element is PropertyAccessorElement) {
        className = element.name;
      }
      if (className == name) return meta;
    }
    return null;
  }

  bool? _getBoolField(ElementAnnotation annotation, String fieldName) {
    try {
      final value = annotation.computeConstantValue();
      final field = value?.getField(fieldName);
      return field?.toBoolValue();
    } catch (_) {
      return null;
    }
  }

  String? _getStringField(ElementAnnotation annotation, String fieldName) {
    try {
      final value = annotation.computeConstantValue();
      return value?.getField(fieldName)?.toStringValue();
    } catch (_) {
      return null;
    }
  }

  String? _getDefaultValueLiteral(ElementAnnotation annotation) {
    try {
      final value = annotation.computeConstantValue();
      final defaultField = value?.getField('defaultValue');
      if (defaultField == null || defaultField.isNull) return null;
      return _dartObjectToLiteral(defaultField);
    } catch (_) {
      return null;
    }
  }

  String? _dartObjectToLiteral(DartObject obj) {
    if (obj.isNull) return null;
    final boolVal = obj.toBoolValue();
    if (boolVal != null) return boolVal.toString();
    final intVal = obj.toIntValue();
    if (intVal != null) return intVal.toString();
    final doubleVal = obj.toDoubleValue();
    if (doubleVal != null) return doubleVal.toString();
    final stringVal = obj.toStringValue();
    if (stringVal != null) return '"$stringVal"';
    final listVal = obj.toListValue();
    if (listVal != null) {
      if (listVal.isEmpty) return '[]';
      final items = listVal.map((e) => _dartObjectToLiteral(e) ?? 'null');
      return '[${items.join(', ')}]';
    }
    final mapVal = obj.toMapValue();
    if (mapVal != null && mapVal.isEmpty) return '{}';

    // Enum value: get the field name
    final type = obj.type;
    if (type != null) {
      final typeName = type.element?.name ?? '';
      final variable = obj.variable;
      if (variable != null) {
        return '"${variable.name}"';
      }
    }
    return null;
  }

  String? _getFunctionName(ElementAnnotation annotation, String fieldName) {
    try {
      final value = annotation.computeConstantValue();
      final fn = value?.getField(fieldName);
      // Functions can't really be evaluated as constants, but we detect presence
      if (fn != null && !fn.isNull) return '__custom__';
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _getConstructorDefault(FieldElement field) {
    try {
      final cls = field.enclosingElement;
      if (cls is! ClassElement) return null;

      // Lazy-load defaults from source for this class
      if (!_constructorDefaultsCache.containsKey(cls.name)) {
        _constructorDefaultsCache[cls.name] = _loadDefaultsForClass(cls);
      }

      final defaults = _constructorDefaultsCache[cls.name]!;
      final raw = defaults[field.name];
      if (raw == null) return null;

      return TypeMapping.resolveLiteralDefault(raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _loadDefaultsForClass(ClassElement cls) {
    try {
      final source = cls.source;
      if (source == null) return {};

      // Get the source text slice for this class
      final fullSource = source.contents.data;
      final offset = cls.nameOffset;
      final end = cls.nameOffset + cls.nameLength + 2000; // generous window
      final classSlice = fullSource.substring(
        offset.clamp(0, fullSource.length),
        end.clamp(0, fullSource.length),
      );

      // Merge constructor defaults and field initializer defaults
      final ctorDefaults = ConstructorDefaultExtractor.extract(classSlice);
      final fieldDefaults = FieldInitializerExtractor.extract(classSlice);

      return {...fieldDefaults, ...ctorDefaults}; // ctor takes priority
    } catch (_) {
      return {};
    }
  }

  String _camelToSnakeOrKeep(String name) =>
      name; // json_serializable keeps camelCase by default
}

class _TypeInfo {
  final String typeName;
  final bool isNullable;
  final List<String> typeArgs;

  _TypeInfo(this.typeName, this.isNullable, this.typeArgs);
}
