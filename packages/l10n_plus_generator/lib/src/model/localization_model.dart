import 'package:l10n_plus/l10n_plus.dart';

import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';

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

  /// Whether this message generates a getter rather than a method.
  bool get isGetter => arguments.isEmpty;
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
}
