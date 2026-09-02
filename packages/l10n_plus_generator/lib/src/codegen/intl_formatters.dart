import '../ast/message_ast.dart';

/// A formatter the generated file needs at run time.
///
/// Formatters are emitted as lazily initialized top level finals, one per
/// locale and style, so a message method never constructs a `NumberFormat` or
/// `DateFormat` on the hot path.
final class FormatterBinding {
  /// Creates a binding.
  const FormatterBinding({
    required this.fieldName,
    required this.dartType,
    required this.initializer,
    required this.localeDartName,
  });

  /// Name of the generated top level final, e.g. `_enNumberPercent`.
  final String fieldName;

  /// `NumberFormat` or `DateFormat`.
  final String dartType;

  /// Right hand side of the generated declaration.
  final String initializer;

  /// The locale this formatter formats for.
  ///
  /// Not always the locale of the file that uses it: an untranslated message
  /// filled from the base locale renders as the base locale does, formatters
  /// included. With `file_per_locale` that decides which part file declares
  /// it, so one library never declares the same final twice.
  final String localeDartName;
}

/// Maps ICU argument formats onto `package:intl` constructors.
///
/// The style allowlists are deliberate: an unknown style produces a diagnostic
/// listing what is supported, rather than generated code that does not compile.
abstract final class IntlFormatters {
  /// `{n, number, <style>}` styles and their `NumberFormat` constructors.
  ///
  /// The key `null` is the default style.
  static const Map<String?, String> numberStyles = {
    null: 'decimalPattern',
    'decimal': 'decimalPattern',
    // ICU's `integer` is the decimal pattern with no fraction digits. There is
    // no `NumberFormat.integer`; asking for one used to generate a file that
    // did not compile.
    'integer': 'decimalPatternDigits',
    'percent': 'percentPattern',
    'currency': 'currency',
    'simpleCurrency': 'simpleCurrency',
    'compact': 'compact',
    'compactLong': 'compactLong',
    'scientific': 'scientificPattern',
  };

  /// Named date styles, mapped onto `DateFormat` skeletons.
  static const Map<String, String> dateStyles = {
    'short': 'yMd',
    'medium': 'yMMMd',
    'long': 'yMMMMd',
    'full': 'yMMMMEEEEd',
  };

  /// Named time styles, mapped onto `DateFormat` skeletons.
  static const Map<String, String> timeStyles = {
    'short': 'jm',
    'medium': 'jms',
    'long': 'jms',
    'full': 'jms',
  };

  /// Every `DateFormat` skeleton constructor that may be named directly.
  ///
  /// This is what makes ARB's `"format": "yMMMd"` work unchanged.
  static const Set<String> dateSkeletons = {
    'd',
    'E',
    'EEEE',
    'LLL',
    'LLLL',
    'M',
    'Md',
    'MEd',
    'MMM',
    'MMMd',
    'MMMEd',
    'MMMM',
    'MMMMd',
    'MMMMEEEEd',
    'QQQ',
    'QQQQ',
    'y',
    'yM',
    'yMd',
    'yMEd',
    'yMMM',
    'yMMMd',
    'yMMMEd',
    'yMMMM',
    'yMMMMd',
    'yMMMMEEEEd',
    'yQQQ',
    'yQQQQ',
  };

  /// The clock half of the skeleton set.
  ///
  /// Kept apart so `{t, time, yMMMd}` is caught: it passes `DateFormat`
  /// happily and renders a date, which is not what the author asked for.
  static const Set<String> timeSkeletons = {
    'H',
    'Hm',
    'Hms',
    'j',
    'jm',
    'jms',
    'm',
    'ms',
    's',
  };

  /// The number styles that accept currency options.
  ///
  /// `currency` prints the ISO code (`USD1,234.50`), `simpleCurrency` prints
  /// the locale's symbol for that currency (`\$1,234.50`). Both are `intl`
  /// constructors; the choice is the user's, because the symbol is prettier
  /// and the code is unambiguous.
  static const Set<String> currencyStyles = {'currency', 'simpleCurrency'};

  /// Whether [format] is a currency format, and so may carry currency options.
  static bool acceptsCurrencyOptions(ArgumentFormat format) =>
      format.kind == ArgumentFormatKind.number &&
      currencyStyles.contains(format.style);

  /// Whether [format] accepts an explicit symbol.
  ///
  /// Only `NumberFormat.currency` has a `symbol:` parameter.
  /// `NumberFormat.simpleCurrency` derives the symbol from the currency, which
  /// is the whole difference between the two, so overriding it there is a
  /// contradiction — and would generate code that does not compile.
  static bool acceptsCurrencySymbol(ArgumentFormat format) =>
      format.kind == ArgumentFormatKind.number && format.style == 'currency';

  /// Whether [code] is a well formed ISO 4217 alphabetic code.
  ///
  /// The list of assigned codes changes over time, so the shape is checked and
  /// the meaning is left to `intl`: three upper case letters.
  static bool isValidCurrencyCode(String code) => _currencyCode.hasMatch(code);

  static final RegExp _currencyCode = RegExp(r'^[A-Z]{3}$');

  /// Largest number of fraction digits `NumberFormat` will honour.
  static const int maxDecimalDigits = 20;

  /// Whether [digits] is a usable `decimalDigits` value.
  static bool isValidDecimalDigits(int digits) =>
      digits >= 0 && digits <= maxDecimalDigits;

  /// The Dart parameter type an argument with [format] must have.
  static String parameterType(ArgumentFormat format) =>
      format.kind == ArgumentFormatKind.number ? 'num' : 'DateTime';

  /// Styles [kind] accepts, sorted, for diagnostics.
  static List<String> supportedStyles(ArgumentFormatKind kind) {
    final styles = switch (kind) {
      ArgumentFormatKind.number => numberStyles.keys.nonNulls.toSet(),
      ArgumentFormatKind.date => {
        ...dateStyles.keys,
        ...dateSkeletons,
        ...timeSkeletons,
      },
      ArgumentFormatKind.time => {...timeStyles.keys, ...timeSkeletons},
    };
    return styles.toList(growable: false)..sort();
  }

  /// Whether [format] can be generated.
  static bool isSupported(ArgumentFormat format) => switch (format.kind) {
    ArgumentFormatKind.number => numberStyles.containsKey(format.style),
    // `date` stays permissive: `{d, date, jm}` is odd but harmless, and it has
    // always been accepted. `time` is not, because a date skeleton there
    // renders a date and silently ignores the time.
    ArgumentFormatKind.date =>
      format.style == null ||
          dateStyles.containsKey(format.style) ||
          dateSkeletons.contains(format.style) ||
          timeSkeletons.contains(format.style),
    ArgumentFormatKind.time =>
      format.style == null ||
          timeStyles.containsKey(format.style) ||
          timeSkeletons.contains(format.style),
  };

  /// The binding [format] needs for [localeTag], or `null` when unsupported.
  ///
  /// [localeDartName] is the locale enum value name, used to build a field name
  /// that is unique per locale and stable across runs.
  static FormatterBinding? bindingFor({
    required ArgumentFormat format,
    required String localeTag,
    required String localeDartName,
  }) {
    if (!isSupported(format)) return null;
    final locale = localeTag.replaceAll('_', '-');

    switch (format.kind) {
      case ArgumentFormatKind.number:
        final constructor = numberStyles[format.style]!;
        final options = acceptsCurrencyOptions(format) ? format.currency : null;
        return FormatterBinding(
          fieldName:
              '_$localeDartName'
              'Number${_capitalize(constructor)}${_optionsSuffix(options)}',
          dartType: 'NumberFormat',
          initializer: _numberInitializer(constructor, locale, options),
          localeDartName: localeDartName,
        );

      case ArgumentFormatKind.date:
      case ArgumentFormatKind.time:
        final named = format.kind == ArgumentFormatKind.date
            ? dateStyles
            : timeStyles;
        final skeleton =
            named[format.style] ??
            format.style ??
            (format.kind == ArgumentFormatKind.date ? 'yMMMd' : 'jm');
        return FormatterBinding(
          fieldName:
              '_$localeDartName'
              'Date${_capitalize(skeleton)}',
          dartType: 'DateFormat',
          initializer: "DateFormat.$skeleton('$locale')",
          localeDartName: localeDartName,
        );
    }
  }

  /// The `NumberFormat` construction for [constructor] in [locale].
  ///
  /// The three named-argument constructors take `locale:`; the rest take the
  /// locale positionally.
  static String _numberInitializer(
    String constructor,
    String locale,
    CurrencyOptions? options,
  ) {
    final named =
        currencyStyles.contains(constructor) ||
        constructor == 'compact' ||
        constructor == 'compactLong' ||
        constructor == 'decimalPatternDigits';
    if (!named) return "NumberFormat.$constructor('$locale')";

    final arguments = [
      "locale: '$locale'",
      if (options?.code case final String code) "name: '$code'",
      // `simpleCurrency` has no `symbol:`; the model builder rejects one, and
      // this guard keeps a bug there from emitting uncompilable code.
      if (options?.symbol case final String symbol
          when constructor == 'currency')
        'symbol: ${_stringLiteral(symbol)}',
      if (options?.decimalDigits case final int digits)
        'decimalDigits: $digits',
      // The only style with a fixed argument of its own: `integer` *is*
      // "decimal, zero digits", so the digits are part of the style rather
      // than something the author sets.
      if (constructor == 'decimalPatternDigits') 'decimalDigits: 0',
    ];
    return 'NumberFormat.$constructor(${arguments.join(', ')})';
  }

  /// Field name suffix that makes each distinct set of options its own final.
  ///
  /// Without it two currencies in one locale would collapse onto one formatter
  /// and the last one emitted would silently win.
  static String _optionsSuffix(CurrencyOptions? options) {
    if (options == null || options.isEmpty) return '';
    final buffer = StringBuffer();
    if (options.code case final String code) {
      buffer.write(_capitalize(code.toLowerCase()));
    }
    if (options.symbol case final String symbol) {
      // The symbol is arbitrary text, so it is hashed rather than spelled out;
      // the same symbol always produces the same name.
      buffer.write('Symbol${symbol.hashCode.toUnsigned(20).toRadixString(36)}');
    }
    if (options.decimalDigits case final int digits) {
      buffer.write('Digits$digits');
    }
    return buffer.toString();
  }

  /// A single quoted Dart string literal holding [value].
  static String _stringLiteral(String value) {
    final buffer = StringBuffer("'");
    for (final unit in value.runes) {
      switch (unit) {
        case 0x5c: // backslash
          buffer.write(r'\\');
        case 0x27: // '
          buffer.write(r"\'");
        case 0x24: // $
          buffer.write(r'\$');
        case 0x0a:
          buffer.write(r'\n');
        case 0x0d:
          buffer.write(r'\r');
        case 0x09:
          buffer.write(r'\t');
        default:
          buffer.writeCharCode(unit);
      }
    }
    return (buffer..write("'")).toString();
  }

  static String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);
}
