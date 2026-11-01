/// Minimal runtime for `l10n_plus` generated localizations.
///
/// Everything expensive (parsing, validation, plural rule selection) happens at
/// generation time; this package only carries what generated code needs at
/// run time.
library;

export 'src/locale.dart' show L10nLocale;
export 'src/locale_resolver.dart' show L10nLocaleResolver;
export 'src/overrides.dart' show L10nOverrideMismatch, L10nOverrides;
export 'src/plural_operands.dart' show PluralOperands;
export 'src/span.dart' show L10nSpan, L10nTagSpan, L10nTextSpan;
export 'src/translations.dart'
    show AppLocaleBase, BaseTranslations, DeferredAppLocale;
