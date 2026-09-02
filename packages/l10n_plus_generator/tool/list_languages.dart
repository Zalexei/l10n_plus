// Prints every language the cardinal plural table knows, for
// tool/ordinal_oracle.sh.
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';

void main() => print(CldrPluralRules.supportedLanguages.join(' '));
