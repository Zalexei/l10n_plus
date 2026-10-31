import 'package:source_span/source_span.dart';

/// One override lookup the generated code actually performs.
///
/// Not a description of what an override *could* say: the emitter records
/// these as it writes the lookups, so the shape a bundle is checked against is
/// the shape the application will consult. A branch the emitter stopped writing
/// cannot stay valid in the checker, which is the only way the two can be
/// guaranteed to agree.
final class OverrideSlot {
  /// Creates a slot.
  const OverrideSlot({required this.branch, required this.tokens});

  /// The branch the compiled condition had already chosen, or `null` for a
  /// message with one form.
  ///
  /// `=0` for an exact plural case, a CLDR category such as `one`, or a select
  /// case label. A choice nested inside the message is numbered in emission
  /// order and prefixes its own branches: `0/one` is the `one` branch of the
  /// message's first nested choice.
  final String? branch;

  /// Every token `L10nOverrides.fill` will substitute in this slot.
  ///
  /// An argument name, `#` for the plural count in scope, and `#0`, `#1`… for
  /// the rendering of a nested choice. A select argument is deliberately absent:
  /// its value is a generated enum, so `{gender}` would print
  /// `ProfileGreetingGender.male` rather than anything a translator meant.
  final Set<String> tokens;
}

/// Every slot of one message in one locale.
final class OverrideMessage {
  /// Creates a message entry.
  const OverrideMessage({
    required this.key,
    required this.keySpan,
    required this.isRich,
    required this.slots,
    this.pluralCategories = const {},
  });

  /// Dotted translation key.
  final String key;

  /// Where the key is in the base locale file, for a diagnostic about it.
  final SourceSpan keySpan;

  /// Whether this is a rich message, which cannot be overridden at all.
  ///
  /// Recorded even though it has no slots: a bundle naming a rich key has made
  /// a different mistake from one naming a key that does not exist, and saying
  /// so is the difference between a fix and a hunt.
  final bool isRich;

  /// The slots, in emission order. Empty for a rich message.
  final List<OverrideSlot> slots;

  /// The categories this locale can produce, per choice of this message.
  ///
  /// Keyed by the choice's branch path prefix: the empty string for the
  /// message's own choice, `0` for its first nested one. Absent for a select,
  /// which has no categories, and empty for a language CLDR has no rules for.
  ///
  /// Recorded from the same tables the conditions were compiled from, and
  /// per choice rather than per message because cardinal and ordinal are two
  /// tables: English has `one, other` counting things and `one, two, few,
  /// other` ranking them, so `two` is a mistake in one and not in the other.
  final Map<String, Set<String>> pluralCategories;

  /// Whether the message's own text is one slot.
  ///
  /// True for a message with one form, and also for one whose single form
  /// *contains* a choice — "You have {plural} linked" is one text with the
  /// plural's rendering as a token, and its branches are slots of their own.
  /// So a key can accept either shape, though one bundle entry is one of them.
  bool get hasPlainSlot => slotOf(null) != null;

  /// Whether anything branches on this message.
  bool get hasBranchSlots => branchNames.isNotEmpty;

  /// The slot [branch] names, or `null`.
  OverrideSlot? slotOf(String? branch) {
    for (final slot in slots) {
      if (slot.branch == branch) return slot;
    }
    return null;
  }

  /// Every branch name, in emission order.
  List<String> get branchNames => [
    for (final slot in slots)
      if (slot.branch != null) slot.branch!,
  ];
}

/// The overridable surface of one locale.
final class OverrideSchema {
  /// Creates a schema.
  const OverrideSchema({
    required this.localeTag,
    required this.language,
    required this.messages,
  });

  /// The locale, as a file tag.
  final String localeTag;

  /// Language subtag, for the CLDR categories a diagnostic quotes.
  final String language;

  /// Every message, by dotted key, in generated order.
  final Map<String, OverrideMessage> messages;
}

/// The overridable surface of a project: one schema per locale.
final class OverrideCatalog {
  /// Creates a catalog.
  const OverrideCatalog(this.locales);

  /// One schema per generated locale, in model order.
  final List<OverrideSchema> locales;

  /// Whether the project emitted no lookups at all.
  ///
  /// True for every project with `runtime_overrides` off, which is what
  /// `check-overrides` refuses on: a bundle checked against a project that
  /// consults nothing would pass and then do nothing.
  bool get isEmpty => locales.isEmpty;

  /// The schema of [localeTag], or `null` when the project has no such locale.
  OverrideSchema? forLocale(String localeTag) {
    for (final schema in locales) {
      if (schema.localeTag == localeTag) return schema;
    }
    return null;
  }

  /// Every locale tag, in model order.
  List<String> get localeTags => [
    for (final schema in locales) schema.localeTag,
  ];
}
