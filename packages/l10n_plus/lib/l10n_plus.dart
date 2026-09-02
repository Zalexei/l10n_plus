/// Minimal runtime for `l10n_plus` generated localizations.
///
/// Everything expensive (parsing, validation, plural rule selection) happens at
/// generation time; this package only carries what generated code needs at
/// run time.
library;

export 'src/locale.dart' show L10nLocale;
export 'src/locale_resolver.dart' show L10nLocaleResolver;
export 'src/plural_operands.dart' show PluralOperands;
export 'src/translations.dart' show AppLocaleBase, BaseTranslations;
