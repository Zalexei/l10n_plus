/// Flutter integration for `l10n_plus` generated localizations.
///
/// The library deliberately ships only a [ChangeNotifier] and one inherited
/// widget: locale state is app state, and apps already have opinions about how
/// to manage it.
library;

export 'package:l10n_plus/l10n_plus.dart'
    show L10nLocale, L10nOverrides, L10nSpan, L10nTagSpan, L10nTextSpan;

export 'src/flutter_locale.dart' show FlutterLocaleL10n, L10nLocaleFlutter;
export 'src/l10n_controller.dart' show L10nController;
export 'src/l10n_scope.dart' show L10nScope;
export 'src/rich_text.dart' show L10nSpanBuilder, l10nTextSpan;
