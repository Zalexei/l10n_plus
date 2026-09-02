import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../codegen/intl_formatters.dart';
import '../diagnostic.dart';

/// Result of parsing one ICU message.
final class IcuParseResult {
  /// Creates a result.
  IcuParseResult(this.body, this.diagnostics);

  /// The parsed body, or `null` when parsing failed.
  final MessageBody? body;

  /// Problems found while parsing.
  final List<Diagnostic> diagnostics;
}

/// Parses ICU MessageFormat into a [MessageBody].
///
/// Supported: literal text, `{name}` placeholders, `{n, plural, ...}` with
/// `=N` and category branches, `{x, select, ...}`, `{n, number|date|time}` with
/// a style, `#` inside plural branches, arbitrary nesting, and ICU apostrophe
/// quoting.
///
/// Explicitly rejected with a diagnostic (rather than silently mishandled):
/// `selectordinal` and plural `offset:`.
final class IcuMessageParser {
  IcuMessageParser._({
    required String message,
    required this.fallbackSpan,
    required int? contentOffset,
    required this.translationKey,
  }) : _source = message,
       _contentOffset = contentOffset,
       // Spans are cut from the original file, so line and column numbers are
       // the real ones, not offsets into the message.
       _file = contentOffset == null ? null : fallbackSpan.file;

  final String _source;
  final int? _contentOffset;
  final SourceFile? _file;

  /// Span of the whole string literal, used when exact positions are
  /// unavailable.
  final FileSpan fallbackSpan;

  /// Dotted key of the message being parsed, used in diagnostics.
  final String translationKey;

  final List<Diagnostic> _diagnostics = [];
  int _offset = 0;

  /// Parses [message].
  ///
  /// [valueSpan] is the span of the whole string literal and [contentOffset]
  /// the file offset of the message's first character, or `null` when the
  /// literal contained escapes and offsets no longer line up.
  static IcuParseResult parse(
    String message, {
    required FileSpan valueSpan,
    required int? contentOffset,
    required String translationKey,
  }) {
    final parser = IcuMessageParser._(
      message: message,
      fallbackSpan: valueSpan,
      contentOffset: contentOffset,
      translationKey: translationKey,
    );
    final body = parser._parseBody(pluralArgument: null, depth: 0);
    if (!parser._isDone) {
      parser._error(
        code: 'icu_unbalanced_brace',
        message: 'Unexpected "}" without a matching "{".',
        start: parser._offset,
        end: parser._offset + 1,
      );
    }
    final failed = parser._diagnostics.any((d) => d.severity == Severity.error);
    return IcuParseResult(failed ? null : body, parser._diagnostics);
  }

  bool get _isDone => _offset >= _source.length;

  String get _current => _source[_offset];

  SourceSpan _span(int start, int end) {
    final file = _file;
    final offset = _contentOffset;
    if (file == null || offset == null) return fallbackSpan;
    final from = (offset + start).clamp(0, file.length);
    final to = (offset + end).clamp(from, file.length);
    return file.span(from, to);
  }

  void _error({
    required String code,
    required String message,
    required int start,
    required int end,
    String? details,
  }) {
    _diagnostics.add(
      Diagnostic.error(
        code: code,
        message: message,
        span: _span(start, end),
        translationKey: translationKey,
        details: details,
      ),
    );
  }

  MessageBody _parseBody({
    required String? pluralArgument,
    required int depth,
  }) {
    final start = _offset;
    final nodes = <MessageNode>[];
    final literal = StringBuffer();
    var literalStart = _offset;

    void flushLiteral(int end) {
      if (literal.isEmpty) return;
      nodes.add(LiteralNode(_span(literalStart, end), literal.toString()));
      literal.clear();
    }

    while (!_isDone) {
      final char = _current;
      if (char == '}') break;
      if (char == '{') {
        flushLiteral(_offset);
        final node = _parseArgument(depth: depth);
        if (node == null) break;
        nodes.add(node);
        literalStart = _offset;
        continue;
      }
      if (char == '#' && pluralArgument != null) {
        flushLiteral(_offset);
        nodes.add(NumberSignNode(_span(_offset, _offset + 1), pluralArgument));
        _offset++;
        literalStart = _offset;
        continue;
      }
      if (char == "'") {
        final consumed = _consumeQuoted(literal);
        if (consumed) continue;
      }
      literal.write(char);
      _offset++;
    }
    flushLiteral(_offset);
    return MessageBody(nodes, _span(start, _offset));
  }

  /// Handles ICU apostrophe quoting.
  ///
  /// Only `''` and an apostrophe immediately before `{`, `}` or `#` are treated
  /// as quoting, so ordinary apostrophes in `l'ami` stay literal. Returns
  /// whether the apostrophe was consumed as a quote.
  bool _consumeQuoted(StringBuffer literal) {
    final next = _offset + 1 < _source.length ? _source[_offset + 1] : null;
    if (next == "'") {
      literal.write("'");
      _offset += 2;
      return true;
    }
    if (next != '{' && next != '}' && next != '#') return false;

    _offset++; // opening apostrophe
    while (!_isDone) {
      if (_current == "'") {
        if (_offset + 1 < _source.length && _source[_offset + 1] == "'") {
          literal.write("'");
          _offset += 2;
          continue;
        }
        _offset++; // closing apostrophe
        return true;
      }
      literal.write(_current);
      _offset++;
    }
    return true; // Unterminated quote: treat the rest as literal.
  }

  MessageNode? _parseArgument({required int depth}) {
    final start = _offset;
    if (depth > 12) {
      _error(
        code: 'icu_nesting_too_deep',
        message: 'Message nesting is too deep.',
        start: start,
        end: start + 1,
      );
      _offset = _source.length;
      return null;
    }
    _offset++; // '{'
    _skipWhitespace();
    final name = _parseIdentifier();
    if (name == null) {
      _error(
        code: 'icu_missing_argument_name',
        message: 'Expected an argument name after "{".',
        start: start,
        end: (start + 2).clamp(0, _source.length),
        details: 'Write {name} for a placeholder, or {name, plural, ...}.',
      );
      _offset = _source.length;
      return null;
    }
    _skipWhitespace();

    if (_isDone) {
      _error(
        code: 'icu_unclosed_argument',
        message: 'Unclosed argument "{$name".',
        start: start,
        end: _source.length,
        details: 'Add the missing "}".',
      );
      return null;
    }

    if (_current == '}') {
      _offset++;
      return ArgumentNode(_span(start, _offset), name);
    }

    if (_current != ',') {
      _error(
        code: 'icu_unclosed_argument',
        message: 'Expected "}" or "," after argument "$name".',
        start: _offset,
        end: _offset + 1,
      );
      _offset = _source.length;
      return null;
    }
    _offset++; // ','
    _skipWhitespace();
    final typeStart = _offset;
    final type = _parseIdentifier();
    if (type == null) {
      _error(
        code: 'icu_missing_argument_type',
        message: 'Expected an argument type after "$name,".',
        start: typeStart,
        end: (typeStart + 1).clamp(0, _source.length),
        details:
            'Supported types: plural, selectordinal, select, number, date, time.',
      );
      _offset = _source.length;
      return null;
    }

    switch (type) {
      case 'plural':
        return _parseChoice(
          start: start,
          argument: name,
          pluralType: PluralType.cardinal,
          depth: depth,
        );
      case 'select':
        return _parseChoice(
          start: start,
          argument: name,
          pluralType: null,
          depth: depth,
        );
      case 'number':
      case 'date':
      case 'time':
        return _parseFormatted(
          start: start,
          argument: name,
          kind: ArgumentFormatKind.values.byName(type),
          typeStart: typeStart,
        );
      case 'selectordinal':
        return _parseChoice(
          start: start,
          argument: name,
          pluralType: PluralType.ordinal,
          depth: depth,
        );
      default:
        _error(
          code: 'icu_unsupported_type',
          message: 'Unknown argument type "$type".',
          start: typeStart,
          end: _offset,
          details:
              'Supported types: plural, selectordinal, select, number, date, time.',
        );
    }
    _offset = _source.length;
    return null;
  }

  /// Parses the tail of `{arg, number|date|time[, style]}`.
  MessageNode? _parseFormatted({
    required int start,
    required String argument,
    required ArgumentFormatKind kind,
    required int typeStart,
  }) {
    _skipWhitespace();
    String? style;
    String? currencyCode;
    var styleStart = _offset;

    if (!_isDone && _current == ',') {
      _offset++;
      _skipWhitespace();
      styleStart = _offset;
      style = _parseIdentifier();
      if (style == null) {
        // `::currency/USD` is valid ICU 60 skeleton syntax, so pointing at the
        // supported spelling beats "expected a style".
        final skeleton = _source.startsWith('::', styleStart);
        _error(
          code: 'icu_invalid_style',
          message: 'Expected a style after "$argument, ${kind.label},".',
          start: styleStart,
          end: (styleStart + 1).clamp(0, _source.length),
          details: skeleton
              ? 'ICU number skeletons are not supported. For an explicit '
                    'currency write {$argument, number, currency:USD}.\n'
                    '${_styleHelp(kind)}'
              : _styleHelp(kind),
        );
        _offset = _source.length;
        return null;
      }
      if (!_isDone && _current == ':') {
        currencyCode = _parseCurrencyCode(
          argument: argument,
          kind: kind,
          style: style,
        );
        if (currencyCode == null) {
          _offset = _source.length;
          return null;
        }
      }
      _skipWhitespace();
    }

    if (_isDone || _current != '}') {
      _error(
        code: 'icu_unclosed_argument',
        message: 'Expected "}" after "$argument, ${kind.label}".',
        start: start,
        end: _offset.clamp(0, _source.length),
      );
      _offset = _source.length;
      return null;
    }
    _offset++;

    final format = ArgumentFormat(
      kind,
      // `{n, number, decimalPattern}` is `{n, number, decimal}` spelled the
      // way `gen_l10n` spells it. Folding it here means the rest of the
      // pipeline, the diagnostics and the generated formatter name all see
      // one style rather than two.
      kind == ArgumentFormatKind.number
          ? IntlFormatters.canonicalNumberStyle(style)
          : style,
      currencyCode == null ? null : CurrencyOptions(code: currencyCode),
    );
    if (!IntlFormatters.isSupported(format)) {
      _error(
        code: 'icu_invalid_style',
        message: 'Unknown ${kind.label} style "$style".',
        start: styleStart,
        end: styleStart + (style?.length ?? 1),
        details: _styleHelp(kind),
      );
      return null;
    }
    return ArgumentNode(_span(start, _offset), argument, format: format);
  }

  /// Parses `:USD` after a style, positioned on the `:`.
  ///
  /// Returns `null` after reporting a diagnostic. ICU number skeletons
  /// (`::currency/USD`) are deliberately not supported: implementing one stem
  /// of a spec while rejecting the rest would be worse than not claiming it,
  /// so the syntax here is an extension of the style token and says so.
  String? _parseCurrencyCode({
    required String argument,
    required ArgumentFormatKind kind,
    required String style,
  }) {
    final colon = _offset;
    _offset++; // ':'
    final codeStart = _offset;
    final code = _parseIdentifier();
    if (code == null) {
      _error(
        code: 'icu_invalid_currency_code',
        message: 'Expected a currency code after "$style:".',
        start: colon,
        end: (codeStart + 1).clamp(0, _source.length),
        details:
            'Write an ISO 4217 code of three upper case letters, for example '
            '{$argument, number, $style:USD}.',
      );
      return null;
    }
    if (!(kind == ArgumentFormatKind.number &&
        IntlFormatters.currencyStyles.contains(style))) {
      _error(
        code: 'icu_unexpected_currency_code',
        message: 'The "${kind.label}" style "$style" takes no currency code.',
        start: colon,
        end: _offset,
        details:
            'Only ${IntlFormatters.currencyStyles.join(' and ')} accept one: '
            '{$argument, number, currency:$code}.',
      );
      return null;
    }
    if (!IntlFormatters.isValidCurrencyCode(code)) {
      _error(
        code: 'icu_invalid_currency_code',
        message: 'Invalid currency code "$code".',
        start: codeStart,
        end: _offset,
        details:
            'Expected an ISO 4217 code of three upper case letters.\n'
            '  found: $code',
      );
      return null;
    }
    return code;
  }

  static String _styleHelp(ArgumentFormatKind kind) =>
      'Supported ${kind.label} styles: '
      '${IntlFormatters.supportedStyles(kind).join(', ')}.';

  MessageNode? _parseChoice({
    required int start,
    required String argument,
    required PluralType? pluralType,
    required int depth,
  }) {
    final isPlural = pluralType != null;
    final typeLabel = pluralType?.label ?? 'select';
    _skipWhitespace();
    if (_isDone || _current != ',') {
      _error(
        code: 'icu_missing_branches',
        message: 'Expected "," and branches after "$argument, $typeLabel".',
        start: _offset,
        end: (_offset + 1).clamp(0, _source.length),
        details: isPlural
            ? 'For example: {$argument, $typeLabel, one{1 item} other{# items}}'
            : 'For example: {$argument, select, male{He} other{They}}',
      );
      _offset = _source.length;
      return null;
    }
    _offset++; // ','
    num offset = 0;

    final pluralCases = <PluralCase, MessageBody>{};
    final selectCases = <String, MessageBody>{};
    final seenLabels = <String>{};

    while (true) {
      _skipWhitespace();
      if (_isDone) {
        _error(
          code: 'icu_unclosed_argument',
          message: 'Unclosed argument "{$argument, ...".',
          start: start,
          end: _source.length,
          details: 'Add the missing "}".',
        );
        return null;
      }
      if (_current == '}') {
        _offset++;
        break;
      }

      final labelStart = _offset;
      if (_source.startsWith('offset:', _offset)) {
        if (pluralType != PluralType.cardinal) {
          _error(
            code: 'icu_unsupported_offset',
            message: '"offset:" is only allowed on a plural argument.',
            start: labelStart,
            end: labelStart + 7,
          );
          _offset = _source.length;
          return null;
        }
        if (seenLabels.isNotEmpty) {
          _error(
            code: 'icu_unsupported_offset',
            message: '"offset:" must come before the branches.',
            start: labelStart,
            end: labelStart + 7,
          );
          _offset = _source.length;
          return null;
        }
        _offset += 'offset:'.length;
        final numberStart = _offset;
        if (!_isDone && _current == '-') _offset++;
        while (!_isDone && _isDigit(_source.codeUnitAt(_offset))) {
          _offset++;
        }
        final parsed = num.tryParse(_source.substring(numberStart, _offset));
        if (parsed == null) {
          _error(
            code: 'icu_unsupported_offset',
            message: 'Expected a number after "offset:".',
            start: labelStart,
            end: _offset.clamp(0, _source.length),
            details: 'For example: {n, plural, offset:1 other{# others}}',
          );
          _offset = _source.length;
          return null;
        }
        offset = parsed;
        continue;
      }

      String? label;
      if (isPlural && _current == '=') {
        _offset++;
        final numberStart = _offset;
        while (!_isDone && _isDigit(_source.codeUnitAt(_offset))) {
          _offset++;
        }
        if (numberStart == _offset) {
          _error(
            code: 'icu_invalid_branch',
            message: 'Expected a number after "=".',
            start: labelStart,
            end: _offset + 1,
          );
          _offset = _source.length;
          return null;
        }
        label = '=${_source.substring(numberStart, _offset)}';
      } else {
        label = _parseIdentifier();
      }

      if (label == null) {
        _error(
          code: 'icu_invalid_branch',
          message: 'Expected a branch name inside "$argument".',
          start: labelStart,
          end: (labelStart + 1).clamp(0, _source.length),
          details: isPlural
              ? 'Branches look like =0{...}, one{...} or other{...}.'
              : 'Branches look like male{...} or other{...}.',
        );
        _offset = _source.length;
        return null;
      }

      if (!seenLabels.add(label)) {
        _error(
          code: 'icu_duplicate_branch',
          message: 'Duplicate branch "$label" in "$argument".',
          start: labelStart,
          end: _offset,
        );
      }

      _skipWhitespace();
      if (_isDone || _current != '{') {
        _error(
          code: 'icu_invalid_branch',
          message: 'Expected "{" after branch "$label".',
          start: _offset,
          end: (_offset + 1).clamp(0, _source.length),
        );
        _offset = _source.length;
        return null;
      }
      _offset++; // '{'
      final body = _parseBody(
        pluralArgument: isPlural ? argument : null,
        depth: depth + 1,
      );
      if (_isDone || _current != '}') {
        _error(
          code: 'icu_invalid_branch',
          message: 'Unclosed branch "$label" in "$argument".',
          start: labelStart,
          end: _source.length,
        );
        return null;
      }
      _offset++; // '}'

      if (isPlural) {
        final pluralCase = label.startsWith('=')
            ? ExactPluralCase(num.parse(label.substring(1)))
            : _categoryCase(label, labelStart);
        if (pluralCase == null) {
          _offset = _source.length;
          return null;
        }
        pluralCases[pluralCase] = body;
      } else {
        selectCases[label] = body;
      }
    }

    final span = _span(start, _offset);
    if (pluralType != null) {
      if (!pluralCases.keys.any(
        (c) => c is CategoryPluralCase && c.category == PluralCategory.other,
      )) {
        _error(
          code: 'icu_missing_other_branch',
          message:
              '${pluralType.label} "$argument" is missing the required '
              '"other" branch.',
          start: start,
          end: _offset,
          details:
              'Every ${pluralType.label} must define other{...} as its '
              'fallback.',
        );
        return null;
      }
      return PluralNode(
        span,
        argument,
        pluralCases,
        type: pluralType,
        offset: offset,
      );
    }
    if (!selectCases.containsKey('other')) {
      _error(
        code: 'icu_missing_other_branch',
        message: 'Select "$argument" is missing the required "other" branch.',
        start: start,
        end: _offset,
        details: 'Every select must define other{...} as its fallback.',
      );
      return null;
    }
    return SelectNode(span, argument, selectCases);
  }

  CategoryPluralCase? _categoryCase(String label, int labelStart) {
    final category = PluralCategory.tryParse(label);
    if (category == null) {
      _error(
        code: 'icu_invalid_branch',
        message: 'Unknown plural branch "$label".',
        start: labelStart,
        end: labelStart + label.length,
        details:
            'Use =N or one of: '
            '${PluralCategory.values.map((c) => c.name).join(', ')}.',
      );
      return null;
    }
    return CategoryPluralCase(category);
  }

  void _skipWhitespace() {
    while (!_isDone && _isWhitespace(_source.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  String? _parseIdentifier() {
    final start = _offset;
    while (!_isDone && _isIdentifierChar(_source.codeUnitAt(_offset))) {
      _offset++;
    }
    if (start == _offset) return null;
    return _source.substring(start, _offset);
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;

  static bool _isIdentifierChar(int code) =>
      (code >= 0x61 && code <= 0x7a) || // a-z
      (code >= 0x41 && code <= 0x5a) || // A-Z
      (code >= 0x30 && code <= 0x39) || // 0-9
      code == 0x5f; // _
}
