import 'locale.dart';

/// Implemented by the generated `AppLocale` enum.
///
/// Lets the runtime resolve locales without knowing the generated type.
abstract interface class AppLocaleBase {
  /// The locale this enum value stands for.
  L10nLocale get l10nLocale;
}

/// Implemented by the generated root translations class of every locale.
abstract interface class BaseTranslations {
  /// The locale these translations were generated for.
  L10nLocale get l10nLocale;
}
