// Prints every language the **ordinal** plural table knows, for
// tool/ordinal_oracle.sh.
//
// The ordinal table, not the cardinal one: the oracle exists to check
// `selectordinal`, and CLDR publishes ordinals for about half as many
// languages as cardinals. The two lists were the same size while both tables
// were curated by hand, which is why this said `supportedLanguages` and
// nothing noticed.
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';

void main() => print(CldrPluralRules.supportedOrdinalLanguages.join(' '));
