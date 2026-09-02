import 'package:source_span/source_span.dart';

/// Thrown by [SpanJsonParser] when the document is not valid JSON.
final class SpanJsonException implements Exception {
  /// Creates a JSON syntax error at [span].
  SpanJsonException(this.message, this.span);

  /// What went wrong.
  final String message;

  /// Where it went wrong.
  final SourceSpan span;

  @override
  String toString() => '$message at ${span.start.toolString}';
}

/// A JSON value that remembers where it came from.
///
/// `dart:convert` discards source locations, and precise `file:line:column`
/// diagnostics are a headline feature, so translations are read with this
/// parser instead. ARB is JSON too, so it will reuse this unchanged.
sealed class JsonValue {
  JsonValue(this.span);

  /// The source range covering this value.
  final FileSpan span;
}

/// A JSON object.
final class JsonObject extends JsonValue {
  /// Creates an object with its [entries] in document order.
  JsonObject(super.span, this.entries);

  /// Members in document order. Duplicate keys are preserved so that the
  /// caller can report them.
  final List<JsonMember> entries;
}

/// A single `"key": value` pair.
final class JsonMember {
  /// Creates a member.
  JsonMember(this.key, this.keySpan, this.value);

  /// Decoded member name.
  final String key;

  /// Span of the quoted member name.
  final FileSpan keySpan;

  /// Member value.
  final JsonValue value;
}

/// A JSON array.
final class JsonArray extends JsonValue {
  /// Creates an array.
  JsonArray(super.span, this.items);

  /// Elements in document order.
  final List<JsonValue> items;
}

/// A JSON string.
final class JsonString extends JsonValue {
  /// Creates a string value.
  JsonString(super.span, this.value, {required this.contentOffset});

  /// Decoded string contents.
  final String value;

  /// Offset of the first character after the opening quote, or `null` when the
  /// literal contained escape sequences.
  ///
  /// When non-null, offsets inside [value] map one to one onto file offsets,
  /// which lets the ICU parser report exact positions inside a message.
  final int? contentOffset;
}

/// A JSON number.
final class JsonNumber extends JsonValue {
  /// Creates a number value.
  JsonNumber(super.span, this.value);

  /// The parsed number.
  final num value;
}

/// A JSON boolean.
final class JsonBoolean extends JsonValue {
  /// Creates a boolean value.
  JsonBoolean(super.span, this.value);

  /// The parsed boolean.
  final bool value;
}

/// A JSON `null`.
final class JsonNull extends JsonValue {
  /// Creates a null value.
  JsonNull(super.span);
}

/// Recursive descent JSON parser that keeps source spans.
final class SpanJsonParser {
  SpanJsonParser._(this._file) : _source = _file.getText(0);

  final SourceFile _file;
  final String _source;
  int _offset = 0;

  /// Parses [content] loaded from [uri].
  ///
  /// Throws [SpanJsonException] on malformed input.
  static JsonValue parse(String content, {required Uri uri}) {
    final parser = SpanJsonParser._(SourceFile.fromString(content, url: uri));
    parser._skipWhitespace();
    final value = parser._parseValue();
    parser._skipWhitespace();
    if (!parser._isDone) {
      throw SpanJsonException(
        'Unexpected trailing content',
        parser._spanAt(parser._offset),
      );
    }
    return value;
  }

  bool get _isDone => _offset >= _source.length;

  String get _current => _source[_offset];

  FileSpan _spanAt(int offset) {
    final clamped = offset.clamp(0, _source.length);
    final end = (clamped + 1).clamp(0, _source.length);
    return _file.span(clamped, end);
  }

  Never _fail(String message, [int? offset]) =>
      throw SpanJsonException(message, _spanAt(offset ?? _offset));

  void _skipWhitespace() {
    while (!_isDone) {
      final code = _source.codeUnitAt(_offset);
      // Space, tab, CR, LF.
      if (code == 0x20 || code == 0x09 || code == 0x0d || code == 0x0a) {
        _offset++;
      } else {
        break;
      }
    }
  }

  JsonValue _parseValue() {
    if (_isDone) _fail('Unexpected end of input');
    return switch (_current) {
      '{' => _parseObject(),
      '[' => _parseArray(),
      '"' => _parseString(),
      't' || 'f' => _parseBoolean(),
      'n' => _parseNull(),
      _ => _parseNumber(),
    };
  }

  JsonObject _parseObject() {
    final start = _offset;
    _offset++; // '{'
    final entries = <JsonMember>[];
    _skipWhitespace();
    if (!_isDone && _current == '}') {
      _offset++;
      return JsonObject(_file.span(start, _offset), entries);
    }
    while (true) {
      _skipWhitespace();
      if (_isDone) _fail('Unexpected end of input, expected a member name');
      if (_current != '"') _fail('Expected a quoted member name');
      final key = _parseString();
      _skipWhitespace();
      if (_isDone || _current != ':') _fail('Expected ":" after member name');
      _offset++;
      _skipWhitespace();
      final value = _parseValue();
      entries.add(JsonMember(key.value, key.span, value));
      _skipWhitespace();
      if (_isDone) _fail('Unexpected end of input, expected "," or "}"');
      if (_current == ',') {
        _offset++;
        continue;
      }
      if (_current == '}') {
        _offset++;
        return JsonObject(_file.span(start, _offset), entries);
      }
      _fail('Expected "," or "}"');
    }
  }

  JsonArray _parseArray() {
    final start = _offset;
    _offset++; // '['
    final items = <JsonValue>[];
    _skipWhitespace();
    if (!_isDone && _current == ']') {
      _offset++;
      return JsonArray(_file.span(start, _offset), items);
    }
    while (true) {
      _skipWhitespace();
      items.add(_parseValue());
      _skipWhitespace();
      if (_isDone) _fail('Unexpected end of input, expected "," or "]"');
      if (_current == ',') {
        _offset++;
        continue;
      }
      if (_current == ']') {
        _offset++;
        return JsonArray(_file.span(start, _offset), items);
      }
      _fail('Expected "," or "]"');
    }
  }

  JsonString _parseString() {
    final start = _offset;
    _offset++; // opening quote
    final contentStart = _offset;
    final buffer = StringBuffer();
    var escaped = false;
    while (true) {
      if (_isDone) _fail('Unterminated string', start);
      final char = _current;
      if (char == '"') {
        _offset++;
        return JsonString(
          _file.span(start, _offset),
          buffer.toString(),
          contentOffset: escaped ? null : contentStart,
        );
      }
      if (char == r'\') {
        escaped = true;
        _offset++;
        if (_isDone) _fail('Unterminated escape sequence');
        final escape = _current;
        _offset++;
        switch (escape) {
          case '"':
            buffer.write('"');
          case r'\':
            buffer.write(r'\');
          case '/':
            buffer.write('/');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'u':
            if (_offset + 4 > _source.length) {
              _fail('Incomplete unicode escape');
            }
            final hex = _source.substring(_offset, _offset + 4);
            final code = int.tryParse(hex, radix: 16);
            if (code == null) _fail('Invalid unicode escape "\\u$hex"');
            buffer.writeCharCode(code);
            _offset += 4;
          default:
            _fail('Unknown escape sequence "\\$escape"');
        }
        continue;
      }
      if (_source.codeUnitAt(_offset) < 0x20) {
        _fail('Unescaped control character in string');
      }
      buffer.write(char);
      _offset++;
    }
  }

  JsonBoolean _parseBoolean() {
    final start = _offset;
    if (_source.startsWith('true', _offset)) {
      _offset += 4;
      return JsonBoolean(_file.span(start, _offset), true);
    }
    if (_source.startsWith('false', _offset)) {
      _offset += 5;
      return JsonBoolean(_file.span(start, _offset), false);
    }
    _fail('Invalid literal');
  }

  JsonNull _parseNull() {
    final start = _offset;
    if (_source.startsWith('null', _offset)) {
      _offset += 4;
      return JsonNull(_file.span(start, _offset));
    }
    _fail('Invalid literal');
  }

  JsonNumber _parseNumber() {
    final start = _offset;
    if (!_isDone && _current == '-') _offset++;
    while (!_isDone && _isDigit(_source.codeUnitAt(_offset))) {
      _offset++;
    }
    if (!_isDone && _current == '.') {
      _offset++;
      while (!_isDone && _isDigit(_source.codeUnitAt(_offset))) {
        _offset++;
      }
    }
    if (!_isDone && (_current == 'e' || _current == 'E')) {
      _offset++;
      if (!_isDone && (_current == '+' || _current == '-')) _offset++;
      while (!_isDone && _isDigit(_source.codeUnitAt(_offset))) {
        _offset++;
      }
    }
    final text = _source.substring(start, _offset);
    final value = num.tryParse(text);
    if (value == null) _fail('Invalid JSON value', start);
    return JsonNumber(_file.span(start, _offset), value);
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
}
