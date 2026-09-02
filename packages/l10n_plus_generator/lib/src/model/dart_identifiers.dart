/// Maps translation keys onto Dart identifiers.
abstract final class DartIdentifiers {
  /// Words that genuinely cannot be a member or parameter name.
  ///
  /// Built-in identifiers such as `type`, `get` and `when` are *not* here:
  /// they are only restricted as type names, and escaping them would make
  /// perfectly ordinary keys generate ugly `type$` members.
  static const Set<String> _reserved = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
    'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
    // Reserved inside async and generator bodies.
    'await', 'yield',
    // Inherited from Object: redeclaring these would not compile.
    'hashCode', 'noSuchMethod', 'runtimeType', 'toString',
  };

  /// Splits [raw] into words on camel case boundaries and on anything that is
  /// not an ASCII letter or digit.
  ///
  /// Dart identifiers are ASCII only, so any other character is a separator.
  static List<String> words(String raw) {
    final parts = raw
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .expand(_splitCamelCase)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts;
  }

  static Iterable<String> _splitCamelCase(String value) {
    return value
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .split(' ');
  }

  /// Names an enum can never give a constant, on top of [_reserved].
  ///
  /// Every enum declares a static `values` and an instance `index`, so a
  /// select branch called either produces a class that does not compile.
  /// They are escaped only here: an ordinary message called `index` is fine,
  /// and escaping it everywhere would be noise.
  static const Set<String> _reservedEnumConstants = {'values', 'index'};

  /// `in_progress` becomes `inProgress`, escaping what an enum cannot name.
  static String enumConstant(String raw) {
    final name = lowerCamel(raw);
    return _reservedEnumConstants.contains(name) ? '$name\$' : name;
  }

  /// `auth_login` becomes `authLogin`, escaping reserved words.
  static String lowerCamel(String raw) {
    final parts = words(raw);
    if (parts.isEmpty) return '';
    final buffer = StringBuffer(parts.first.toLowerCase());
    for (final part in parts.skip(1)) {
      buffer.write(_capitalize(part));
    }
    return _escape(buffer.toString());
  }

  /// `auth_login` becomes `AuthLogin`.
  static String upperCamel(String raw) {
    final parts = words(raw);
    if (parts.isEmpty) return '';
    return parts.map(_capitalize).join();
  }

  /// Joins path segments into one upper camel case identifier.
  static String upperCamelPath(Iterable<String> segments) =>
      segments.map(upperCamel).join();

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  static String _escape(String identifier) {
    if (identifier.isEmpty) return identifier;
    var result = identifier;
    if (RegExp('^[0-9]').hasMatch(result)) result = r'$' + result;
    if (_reserved.contains(result)) result = '$result\$';
    return result;
  }
}
