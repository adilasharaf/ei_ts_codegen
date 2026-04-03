/// Maps Dart types to TypeScript/Zod equivalents.

class TypeMapping {
  /// Primitive type map: Dart type name → Zod schema expression
  static const Map<String, String> primitiveZodMap = {
    'String': 'z.string()',
    'int': 'z.number().int()',
    'double': 'z.number()',
    'num': 'z.number()',
    'bool': 'z.boolean()',
    'dynamic': 'z.any()',
    'Object': 'z.unknown()',
    'Map': 'z.record(z.unknown())',
  };

  /// Firestore special types → Zod schema with transforms
  static const Map<String, String> firestoreZodMap = {
    'Timestamp': 'z.any()',
    'GeoPoint': 'z.any()',
    'DocumentReference': 'z.any()',
    'FieldValue': 'z.any()',
    'Blob': 'z.any()',
  };

  /// Firestore types that need Timestamp transform
  static const Set<String> timestampTypes = {'Timestamp'};

  /// Firestore types treated as opaque any
  static const Set<String> opaqueFirestoreTypes = {
    'GeoPoint',
    'DocumentReference',
    'FieldValue',
    'Blob',
  };

  /// Known converter class name patterns → transform logic
  static const Map<String, ConverterTransform> knownConverters = {
    'DateTimeConverter': ConverterTransform(
      zodBase: 'z.any()',
      transform: r'''(val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : val instanceof Date ? val : new Date(val)''',
    ),
    'DateTimeNullableConverter': ConverterTransform(
      zodBase: 'z.any()',
      transform: r'''(val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : null''',
    ),
    'TimestampConverter': ConverterTransform(
      zodBase: 'z.any()',
      transform: r'''(val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : val''',
    ),
    'DateTimeListConverter': ConverterTransform(
      zodBase: 'z.any()',
      transform: r'''(val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : val''',
      isList: true,
    ),
    'ServerTimestampConverter': ConverterTransform(
      zodBase: 'z.any()',
      transform: r'''(val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : val''',
    ),
  };

  /// Resolve a Dart type name to a Zod expression.
  /// [typeName]: bare type name (no nullability)
  /// [isNullable]: whether the type is nullable
  /// [typeArgs]: generic type arguments
  static String resolveZod(
    String typeName, {
    bool isNullable = false,
    List<String> typeArgs = const [],
    String? converterClass,
    String? defaultValue,
    bool isList = false,
  }) {
    String schema;

    // Converter takes precedence
    if (converterClass != null) {
      schema = _resolveConverter(converterClass, typeArgs, isList);
    } else if (typeName == 'List' || typeName == 'Iterable') {
      final inner =
          typeArgs.isNotEmpty ? resolveZod(typeArgs[0]) : 'z.unknown()';
      schema = 'z.array($inner)';
    } else if (typeName == 'Map') {
      final value =
          typeArgs.length >= 2 ? resolveZod(typeArgs[1]) : 'z.unknown()';
      schema = 'z.record($value)';
    } else if (primitiveZodMap.containsKey(typeName)) {
      schema = primitiveZodMap[typeName]!;
    } else if (firestoreZodMap.containsKey(typeName)) {
      if (timestampTypes.contains(typeName)) {
        schema = _timestampZod();
      } else {
        schema = firestoreZodMap[typeName]!;
      }
    } else {
      // Assume it's a model or enum schema reference
      schema = '${typeName}Schema';
    }

    if (isNullable) {
      schema = '$schema.optional()';
    }

    if (defaultValue != null) {
      schema = '$schema.default($defaultValue)';
    }

    return schema;
  }

  static String _resolveConverter(
    String converterClass,
    List<String> typeArgs,
    bool isList,
  ) {
    // Check known converters (case-insensitive prefix match)
    for (final entry in knownConverters.entries) {
      if (converterClass.toLowerCase().contains(entry.key.toLowerCase()) ||
          _matchesConverterPattern(converterClass, entry.key)) {
        final transform = entry.value;
        if (transform.isList || isList) {
          return 'z.array(\n    z.any().transform(${transform.transform})\n  )';
        }
        return 'z.any().transform(${transform.transform})';
      }
    }

    // Generic DateTime detection
    if (_isDateTimeConverter(converterClass)) {
      final nullable = converterClass.toLowerCase().contains('nullable');
      return nullable
          ? 'z.any().transform(${knownConverters['DateTimeNullableConverter']!.transform})'
          : 'z.any().transform(${knownConverters['DateTimeConverter']!.transform})';
    }

    // Unknown converter → opaque any
    return 'z.any()';
  }

  static bool _matchesConverterPattern(String cls, String pattern) {
    // Match like DateTimeNullableConverter matches DateTimeNullable
    final patternBase = pattern.replaceAll('Converter', '').toLowerCase();
    return cls.toLowerCase().contains(patternBase);
  }

  static bool _isDateTimeConverter(String cls) {
    final lower = cls.toLowerCase();
    return lower.contains('datetime') || lower.contains('timestamp');
  }

  static String _timestampZod() {
    return r'''z.any().transform((val) =>
    val?.toDate ? val.toDate() : typeof val === "number" ? new Date(val) : val)''';
  }

  /// Resolve a literal default value to its TypeScript representation.
  static String? resolveLiteralDefault(String dartLiteral) {
    if (dartLiteral == 'null') return null;
    if (dartLiteral == 'true' || dartLiteral == 'false') return dartLiteral;
    if (dartLiteral == '[]') return '[]';
    if (dartLiteral == '{}') return '{}';

    // Numeric
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(dartLiteral)) return dartLiteral;

    // String literal
    if (dartLiteral.startsWith('"') || dartLiteral.startsWith("'")) {
      return '"${dartLiteral.replaceAll("'", "").replaceAll('"', '')}"';
    }

    // Enum: e.g. EiAppSource.other → "other"
    if (dartLiteral.contains('.')) {
      final parts = dartLiteral.split('.');
      return '"${parts.last}"';
    }

    return '"$dartLiteral"';
  }
}

class ConverterTransform {
  final String zodBase;
  final String transform;
  final bool isList;

  const ConverterTransform({
    required this.zodBase,
    required this.transform,
    this.isList = false,
  });
}
