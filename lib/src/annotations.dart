/// Annotations for controlling TypeScript generation behavior.

/// Marks a field to be ignored during TypeScript generation.
class TsIgnore {
  const TsIgnore();
}

/// Overrides the TypeScript type for a field.
/// Example:
/// ```dart
/// @TsType('string | number')
/// dynamic myField;
/// ```
class TsType {
  final String typeName;
  final String? zodSchema;
  const TsType(this.typeName, {this.zodSchema});
}

/// Marks a class for TypeScript generation.
/// By default any class with @JsonSerializable is picked up automatically.
class TsGenerate {
  const TsGenerate();
}

/// Marks a class as a Firestore document model.
/// Adds special handling for Timestamp, GeoPoint, etc.
class TsFirestoreModel {
  const TsFirestoreModel();
}
