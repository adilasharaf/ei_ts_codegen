/// Extracts constructor default values by parsing the raw Dart source text.
///
/// The analyzer's element model does NOT expose initializer expressions
/// as structured data for non-const values (e.g. `= []`, `= 0.0`).
/// We solve this by doing a targeted regex parse on the source text of
/// the constructor parameter list.
library;

/// Parses a Dart class source to extract constructor parameter defaults.
///
/// Returns a map of { fieldName → dartLiteralString }.
///
/// Example input (constructor body):
///   ```dart
///   MyModel({
///     this.count = 0,
///     this.tags = const [],
///     this.name,
///     this.status = MyStatus.active,
///   });
///   ```
///
/// Returns: { 'count': '0', 'tags': '[]', 'status': 'MyStatus.active' }
class ConstructorDefaultExtractor {
  static Map<String, String> extract(String classSource) {
    final result = <String, String>{};

    // Find the constructor body: ClassName({ ... })
    // We look for the primary constructor (unnamed).
    final constructorPattern = RegExp(
      r'\w+\s*\(\s*\{([^}]*)\}',
      dotAll: true,
    );

    final match = constructorPattern.firstMatch(classSource);
    if (match == null) return result;

    final paramBlock = match.group(1) ?? '';

    // Match each `this.fieldName = defaultValue` pattern
    // Handles: = 0, = 0.0, = [], = {}, = true, = false, = Enum.value, = 'str', = "str", = const []
    final paramPattern = RegExp(
      r'this\.(\w+)\s*=\s*(const\s+)?([^\s,\n]+(?:\s*\.\s*\w+)?)',
      dotAll: false,
    );

    for (final m in paramPattern.allMatches(paramBlock)) {
      final fieldName = m.group(1)!;
      final value = m.group(3)!.trim();

      // Skip super. parameters
      if (value.startsWith('super.')) continue;

      result[fieldName] = _normalizeLiteral(value);
    }

    return result;
  }

  /// Normalize a Dart literal to a TypeScript-compatible default expression.
  static String _normalizeLiteral(String dartLiteral) {
    // Remove trailing punctuation that may have been captured
    var val = dartLiteral.replaceAll(RegExp(r'[,;]$'), '').trim();

    // const [] → []
    // const {} → {}
    val = val.replaceAll('const ', '');

    return val;
  }
}

/// Extracts field-level initializer defaults (non-constructor).
///
/// Handles patterns like:
///   ```dart
///   double kmsDriven = 0;
///   List<String> tags = [];
///   bool isActive = true;
///   ```
class FieldInitializerExtractor {
  static Map<String, String> extract(String classSource) {
    final result = <String, String>{};

    // Match: Type fieldName = value;
    // We're careful not to match inside constructors or methods.
    // Pattern: word boundary, optional generic, space, fieldName, space, =, space, value, ;
    final pattern = RegExp(
      r'(?:^|\n)\s*(?:final\s+)?(?:[\w<>, ?]+\s+)(\w+)\s*=\s*([^;{]+);',
      multiLine: true,
    );

    for (final m in pattern.allMatches(classSource)) {
      final fieldName = m.group(1)!.trim();
      final value = m.group(2)!.trim();

      // Skip obvious non-field lines (methods, etc.)
      if (fieldName.isEmpty || value.contains('(') && !value.contains(')')) {
        continue;
      }
      // Skip if it looks like a method call (not a literal)
      if (_isComplexExpression(value)) continue;

      result[fieldName] = value;
    }

    return result;
  }

  static bool _isComplexExpression(String val) {
    // .trim() ensures that " true " is still seen as a simple literal.
    final trimmed = val.trim();

    // Updated Regex:
    // 1. ^-?\d+\.?\d*$ -> Handles negative numbers and decimals.
    // 2. r'["\'].*?["\']' -> More robust string matching.
    // 3. \w+ -> Simple identifiers (no dots, to avoid complex property chaining if desired).
    final simple = RegExp(r'^(true|false|null|-?\d+\.?\d*|"[^"]*"|' +
        "'" +
        r"[^']*'" +
        r'|\[\]|\{\}|[\w]+)$');

    return !simple.hasMatch(trimmed);
  }
}
