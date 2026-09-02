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
    'decimalPercentPattern': 'decimalPercentPattern',
    'currency': 'currency',
    'simpleCurrency': 'simpleCurrency',
    'compact': 'compact',
    'compactLong': 'compactLong',
    'compactCurrency': 'compactCurrency',
    'compactSimpleCurrency': 'compactSimpleCurrency',
    'scientific': 'scientificPattern',
  };

  /// The names `gen_l10n` writes, mapped onto the style this library calls it.
  ///
  /// A bundle exported from `gen_l10n` says `"format": "decimalPattern"`, and
  /// the README promises such a bundle works unedited. These are spellings of
  /// styles that already existed, so they are folded away by
  /// [canonicalNumberStyle] before anything else sees them: one style, one
  /// generated formatter, one name in every diagnostic.
  ///
  /// `decimalPercentPattern` is **not** here. It looks like a spelling of
  /// `percent` and is a different `NumberFormat` constructor — the one that
  /// takes `decimalDigits` — so folding it onto `percent` would silently drop
  /// the digits a bundle asked for. It is a style of its own above.
  static const Map<String, String> numberStyleAliases = {
    'decimalPattern': 'decimal',
    'percentPattern': 'percent',
    'scientificPattern': 'scientific',
  };

  /// [style] under the name the rest of the generator uses.
  ///
  /// Applied wherever a style enters from a source file — the message, the
  /// ARB metadata, a locale's override — so `decimal` and `decimalPattern`
  /// are the same style rather than two that generate the same code twice.
  static String? canonicalNumberStyle(String? style) =>
      style == null ? null : numberStyleAliases[style] ?? style;

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
  static const Set<String> currencyStyles = {
    'currency',
    'simpleCurrency',
    'compactCurrency',
    'compactSimpleCurrency',
  };

  /// The styles whose `NumberFormat` constructor takes `decimalDigits`.
  ///
  /// The currency four, plus `decimalPercentPattern`, which exists in `intl`
  /// for no other reason: `percentPattern` is the same format without the
  /// digits. A style here that is not a currency takes `decimalDigits` and
  /// nothing else — a currency code on a percentage means nothing.
  static const Set<String> decimalDigitsStyles = {
    ...currencyStyles,
    'decimalPercentPattern',
  };

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
      format.kind == ArgumentFormatKind.number &&
      _symbolStyles.contains(format.style);

  /// The currency styles that take an explicit symbol.
  ///
  /// `simpleCurrency` and `compactSimpleCurrency` derive it from the currency,
  /// which is the whole difference between them and the other two.
  static const Set<String> _symbolStyles = {'currency', 'compactCurrency'};

  /// Whether [format] may carry `decimalDigits`.
  ///
  /// Wider than [acceptsCurrencyOptions]: `decimalPercentPattern` takes the
  /// digits without being money.
  static bool acceptsDecimalDigits(ArgumentFormat format) =>
      format.kind == ArgumentFormatKind.number &&
      decimalDigitsStyles.contains(format.style);

  /// Whether [code] is a well formed ISO 4217 alphabetic code.
  ///
  /// The list of assigned codes changes over time, so the shape is checked and
  /// the meaning is left to `intl`: three upper case letters.
  static bool isValidCurrencyCode(String code) => _currencyCode.hasMatch(code);

  static final RegExp _currencyCode = RegExp(r'^[A-Z]{3}$');

  /// Name of the generated helper every `DateFormat` is built through.
  static const String dateFormatHelper = '_dateFormat';

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
        // Wider than the currency styles: `decimalPercentPattern` carries
        // `decimalDigits` and nothing else, and dropping it here would render
        // a different number than the bundle asked for.
        final options = acceptsDecimalDigits(format) ? format.currency : null;
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
          // Built through the generated helper rather than directly: a
          // `DateFormat` throws *while being constructed* when its locale's
          // ICU symbols are not loaded, and says so without naming the
          // initializer this file generated for exactly that purpose.
          initializer:
              "$dateFormatHelper('$locale', () => DateFormat.$skeleton('$locale'))",
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
        constructor == 'decimalPatternDigits' ||
        constructor == 'decimalPercentPattern';
    if (!named) return "NumberFormat.$constructor('$locale')";

    final arguments = [
      "locale: '$locale'",
      // Only money has a currency; the model builder rejects a code on
      // anything else, and this guard keeps a bug there from emitting an
      // argument the constructor does not have.
      if (options?.code case final String code
          when currencyStyles.contains(constructor))
        "name: '$code'",
      // `simpleCurrency` and `compactSimpleCurrency` have no `symbol:`; the
      // model builder rejects one, and this guard keeps a bug there from
      // emitting uncompilable code.
      if (options?.symbol case final String symbol
          when _symbolStyles.contains(constructor))
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
