import 'package:l10n_plus/l10n_plus.dart';

import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../ast/rich_ast.dart';
import '../ast/translation_tree.dart';

/// One value of a generated select enum.
final class EnumValueModel {
  /// Creates an enum value.
  EnumValueModel({required this.dartName, required this.icuLabel});

  /// Dart identifier, e.g. `male`.
  final String dartName;

  /// ICU branch label this value came from, e.g. `male`.
  final String icuLabel;
}

/// A generated enum standing for the branches of one select argument.
final class SelectEnumModel {
  /// Creates an enum model.
  SelectEnumModel({
    required this.name,
    required this.values,
    required this.messagePath,
    required this.argumentName,
  });

  /// Dart type name, e.g. `ProfileGreetingGender`.
  final String name;

  /// Values in ICU document order.
  final List<EnumValueModel> values;

  /// Message the enum was derived from.
  final String messagePath;

  /// Argument the enum was derived from.
  final String argumentName;
}

/// One value of a generated key enum: a message, and the string that names it.
final class KeyEnumValueModel {
  /// Creates a value.
  const KeyEnumValueModel({
    required this.dartName,
    required this.key,
    required this.memberPath,
  });

  /// Dart identifier, e.g. `paymentDeclined`.
  final String dartName;

  /// The key as a string, relative to the namespace: `payment.declined`.
  ///
  /// What a server sends and what `tryParse` matches. Relative rather than
  /// absolute because the namespace is the contract: a project that renames
  /// its root group should not have to renegotiate every error code.
  final String key;

  /// How the generated code reaches the message from the namespace, e.g.
  /// `payment.declined`.
  ///
  /// The members, not the keys: both are dotted and they are usually the same
  /// string, but a key with a hyphen is one identifier and not the other.
  final String memberPath;
}

/// A generated enum standing for every addressable message of one namespace.
///
/// What `dynamic_keys` produces. The point of it is where the string stops
/// being a string: `tryParse` is the one nullable step, at the boundary where
/// a value from outside arrives, and everything after it is a typed key that
/// the generated lookup is total over.
final class KeyEnumModel {
  /// Creates a key enum model.
  const KeyEnumModel({
    required this.name,
    required this.namespacePath,
    required this.values,
  });

  /// Dart type name, e.g. `ErrorsKey`.
  final String name;

  /// Dotted path of the namespace it addresses, e.g. `errors`.
  final String namespacePath;

  /// Values in generated order, which is the base locale's document order.
  final List<KeyEnumValueModel> values;
}

/// A Dart parameter of a generated message method.
final class ArgumentModel {
  /// Creates an argument model.
  ArgumentModel({
    required this.name,
    required this.dartName,
    required this.type,
    this.selectEnum,
    this.description,
    this.example,
    this.format,
  });

  /// ICU argument name.
  final String name;

  /// Dart parameter name.
  final String dartName;

  /// Rendered Dart type, e.g. `String`, `num` or an enum name.
  final String type;

  /// The enum backing a select argument, if any.
  final SelectEnumModel? selectEnum;

  /// Prose description declared by the source format, if any.
  final String? description;

  /// Example value declared by the source format, if any.
  final String? example;

  /// Formatting to apply, from the message or from metadata.
  ///
  /// The emitter falls back to this when an [ArgumentNode] carries no format
  /// of its own, which is how `gen_l10n` style bundles keep working.
  final ArgumentFormat? format;
}

/// One tag of a rich message, as the generated code names it.
final class RichTagModel {
  /// Creates a tag model.
  const RichTagModel({required this.tag, required this.dartName});

  /// Tag name as written in the translation, e.g. `link`.
  ///
  /// Kept verbatim: it is the key of the builder map at run time, and the
  /// translation file is what decides it.
  final String tag;

  /// Dart parameter name of the builder for this tag, e.g. `link`.
  final String dartName;
}

/// A generated message: a getter when it has no arguments, a method otherwise.
final class MessageModel {
  /// Creates a message model.
  MessageModel({
    required this.path,
    required this.dartName,
    required this.keySpan,
    required this.arguments,
    required this.bodies,
    this.formatOverrides = const {},
    this.description,
    this.richBodies = const {},
    this.richTags = const [],
  });

  /// Dotted translation key.
  final String path;

  /// Dart member name.
  final String dartName;

  /// Where the key is in the base locale file.
  final SourceSpan keySpan;

  /// Parameters in order of first appearance in the base locale message.
  final List<ArgumentModel> arguments;

  /// Parsed body per locale file tag.
  final Map<String, MessageBody> bodies;

  /// Formatting a non base locale declared for itself, keyed by locale file
  /// tag and then by argument name.
  ///
  /// The base locale's declaration is already part of [ArgumentModel.format].
  /// These are the per locale overrides, which is how one bundle quotes
  /// roubles with no fraction digits while another quotes dollars with two.
  /// The argument's *kind* is never overridden, so the generated signature is
  /// the same in every locale.
  final Map<String, Map<String, ArgumentFormat>> formatOverrides;

  /// Translator facing description, emitted as the member's doc comment.
  final String? description;

  /// Tag structure per locale file tag, for a rich message.
  ///
  /// Empty for an ordinary message. [bodies] still holds the plain ICU parse
  /// of the same string, in which the tags are literal text — that is what
  /// every stage before the emitter reads, and what the doc comment shows.
  final Map<String, List<RichNode>> richBodies;

  /// Tags of this message in document order, for a rich message.
  ///
  /// The order is the base locale's: it decides the parameter order of the
  /// generated wrapper, and only the base locale may decide the signature.
  final List<RichTagModel> richTags;

  /// Whether this message generates spans rather than a string.
  bool get isRich => richBodies.isNotEmpty;

  /// Whether this message generates a getter rather than a method.
  bool get isGetter => arguments.isEmpty;

  /// Name of the `TextSpan` wrapper the Flutter glue emits for a rich message.
  ///
  /// The data accessor keeps the message's own name, because the data is the
  /// library's answer in any application; the Flutter convenience is the one
  /// that takes a suffix. It cannot be the same name: an extension member is
  /// unreachable when the interface already declares that name, so the two
  /// would not be an overload but a silently dead method.
  String get richWrapperName => '${dartName}Rich';
}

/// One element of a collection: a message, or a record of them.
final class CollectionEntryModel {
  /// Creates an entry.
  const CollectionEntryModel({required this.key, required this.values});

  /// The element's own key: its index in a list, or the key a map wrote.
  final String key;

  /// One message for a collection of text, or one per field — in the
  /// collection's field order — for a collection of records.
  final List<MessageModel> values;
}

/// A group of messages generated as one `List` or `Map` accessor.
///
/// The entries are ordinary [MessageModel]s — parsed, validated and rendered
/// by the same code every other message goes through — and every one of them
/// takes no arguments. That is checked rather than assumed, and it is what
/// makes the accessor a `const` collection: an element that needed values
/// would allocate on every read, and its signature would be the union of what
/// each element happens to use, which is a parameter list no caller could
/// read. An element that wants a value interpolated uses a link, which is
/// resolved before there is a signature at all.
///
/// An element may be a *record*: an object rather than a string, which
/// generates one interface the elements implement and one implementation per
/// locale. Then [fields] is the record's field names and every element has to
/// have all of them, because a list has one element type.
final class CollectionModel {
  /// Creates a collection model.
  const CollectionModel({
    required this.kind,
    required this.path,
    required this.dartName,
    required this.keySpan,
    required this.entries,
    this.fields = const [],
    this.interfaceName,
  });

  /// Whether this is a list or a map. Never [CollectionKind.namespace].
  final CollectionKind kind;

  /// Dotted translation key, including the `(map)` suffix when it has one.
  final String path;

  /// Dart member name, e.g. `steps`.
  final String dartName;

  /// Where the key is in the base locale file.
  final SourceSpan keySpan;

  /// The elements, in the base locale's order.
  final List<CollectionEntryModel> entries;

  /// Field names of the record each element is, in the first element's order.
  ///
  /// Empty for a collection of plain text, which is what [isRecord] reads.
  final List<String> fields;

  /// Name of the generated interface each element implements, e.g.
  /// `$OnboardingStepsItem`. `null` for a collection of plain text.
  final String? interfaceName;

  /// Whether the elements are records rather than single messages.
  bool get isRecord => fields.isNotEmpty;

  /// The Dart type one element has.
  String get elementType => interfaceName ?? 'String';

  /// The Dart type the accessor returns.
  String get type => kind == CollectionKind.list
      ? 'List<$elementType>'
      : 'Map<String, $elementType>';

  /// Every message of every element, which is what a translator is asked for.
  Iterable<MessageModel> get messages =>
      entries.expand((entry) => entry.values);
}

/// A nested namespace, generated as its own class.
final class NamespaceModel {
  /// Creates a namespace model.
  NamespaceModel({
    required this.path,
    required this.dartName,
    required this.interfaceName,
    required this.children,
    required this.messages,
    this.collections = const [],
  });

  /// Dotted key path, empty for the root.
  final String path;

  /// Accessor name on the parent, empty for the root.
  final String dartName;

  /// Name of the generated interface, e.g. `$AuthLogin`.
  final String interfaceName;

  /// Nested namespaces in document order.
  final List<NamespaceModel> children;

  /// Messages in document order.
  final List<MessageModel> messages;

  /// Lists and maps declared directly under this namespace, in document
  /// order.
  ///
  /// Empty in a project with none, which is what keeps every other project's
  /// output exactly what it was.
  final List<CollectionModel> collections;

  /// Whether this is the document root.
  bool get isRoot => path.isEmpty;
}

/// One locale participating in generation.
final class LocaleModel {
  /// Creates a locale model.
  LocaleModel({required this.locale, required this.dartName});

  /// The locale.
  final L10nLocale locale;

  /// Enum value name, e.g. `en` or `ptBR`.
  final String dartName;

  /// File tag used as the key into [MessageModel.bodies].
  String get tag => locale.toFileTag();

  /// Suffix appended to generated class names, e.g. `En` or `PtBR`.
  String get classSuffix => dartName[0].toUpperCase() + dartName.substring(1);
}

/// Everything the emitters need, with no ICU or source concepts left except
/// the message bodies themselves.
final class LocalizationModel {
  /// Creates a localization model.
  LocalizationModel({
    required this.className,
    required this.localeEnumName,
    required this.baseLocale,
    required this.fallbackLocale,
    required this.locales,
    required this.root,
    required this.enums,
    this.keyEnums = const [],
  });

  /// Name of the generated root class, e.g. `AppLocalizations`.
  final String className;

  /// Name of the generated locale enum, e.g. `AppLocale`.
  final String localeEnumName;

  /// The locale defining the API contract.
  final LocaleModel baseLocale;

  /// The locale used when nothing matches at run time.
  final LocaleModel fallbackLocale;

  /// All locales, sorted by language tag for deterministic output.
  final List<LocaleModel> locales;

  /// Root namespace.
  final NamespaceModel root;

  /// Generated select enums, sorted by name.
  final List<SelectEnumModel> enums;

  /// Generated key enums, sorted by name.
  ///
  /// Empty unless `dynamic_keys` named a namespace, which is what keeps a
  /// project that does not address messages by string generating exactly what
  /// it generated before.
  final List<KeyEnumModel> keyEnums;
}
