import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

// The generated files of the generator's `rich` golden fixture, imported by
// path. This is the one place in the repository that can compile them: the
// glue imports Flutter, and the generator package has no Flutter to run a
// widget test with. Importing the golden rather than copying it means the
// file this test runs is byte for byte the file the generator writes and
// `rich_golden_test.dart` pins — a copy here could drift silently.
import '../../l10n_plus_generator/test/goldens/rich/app_localizations.g.dart';
import '../../l10n_plus_generator/test/goldens/rich/app_localizations_flutter.g.dart';

/// The span under test, as the rendered widget tree holds it.
///
/// `Text.rich` wraps the span it is given in one of its own carrying the
/// ambient text style, so what was passed in is that wrapper's only child.
TextSpan _rendered(WidgetTester tester) {
  // The first `RichText` in tree order is the `Text.rich` under test; a
  // builder that puts a widget in the sentence adds more below it.
  final root =
      tester.widgetList<RichText>(find.byType(RichText)).first.text as TextSpan;
  return root.children!.single as TextSpan;
}

Future<void> _pump(WidgetTester tester, InlineSpan span) => tester.pumpWidget(
  Directionality(textDirection: TextDirection.ltr, child: Text.rich(span)),
);

void main() {
  const en = AppLocalizationsEn();
  const ru = AppLocalizationsRu();

  group('the generated wrapper builds a TextSpan', () {
    testWidgets('one builder per tag, and the tag wraps its own children', (
      tester,
    ) async {
      final span = en.legal.termsRich(
        link: (children) => TextSpan(
          children: children,
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
      );
      await _pump(tester, span);

      final root = _rendered(tester);
      expect(root.children, hasLength(3));
      expect((root.children![0] as TextSpan).text, 'Read the ');
      expect((root.children![2] as TextSpan).text, ' to continue');

      // The wrapped region is the builder's span, and the translated text is
      // inside it rather than beside it.
      final link = root.children![1] as TextSpan;
      expect(link.style!.decoration, TextDecoration.underline);
      expect((link.children!.single as TextSpan).text, 'terms of service');

      // The sentence reads as one line, markup and all.
      expect(root.toPlainText(), 'Read the terms of service to continue');
    });

    testWidgets('nested tags nest, and a placeholder lands inside them', (
      tester,
    ) async {
      final span = en.legal.greetingRich(
        name: 'Ada',
        amount: 12.5,
        bold: (children) => TextSpan(
          children: children,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        italic: (children) => TextSpan(
          children: children,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
      await _pump(tester, span);

      final root = _rendered(tester);
      final bold = root.children![1] as TextSpan;
      expect(bold.style!.fontWeight, FontWeight.bold);
      final italic = bold.children!.single as TextSpan;
      expect(italic.style!.fontStyle, FontStyle.italic);
      expect((italic.children!.single as TextSpan).text, 'Ada');
      // The formatted amount is inside the second `<bold>`, formatted for en.
      final amount = root.children!.last as TextSpan;
      expect((amount.children!.single as TextSpan).text, 'USD12.50');
      expect(root.toPlainText(), 'Hi Ada, you owe USD12.50');
    });

    testWidgets('a builder decides what the tag means', (tester) async {
      // What a tag *is* belongs to the application: a style, a tap
      // recognizer, or a widget in the middle of the sentence. The builder
      // receives the children and returns any [InlineSpan], so all three are
      // the same mechanism.
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);

      await _pump(
        tester,
        en.bannerRich(
          app: (children) => TextSpan(
            recognizer: recognizer,
            children: [
              const WidgetSpan(child: Icon(Icons.star, size: 12)),
              ...children,
            ],
          ),
        ),
      );

      final tag = _rendered(tester).children!.last as TextSpan;
      expect(tag.recognizer, same(recognizer));
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect((tag.children!.last as TextSpan).text, 'l10n_plus');
    });

    testWidgets('the root style is passed through', (tester) async {
      final span = en.legal.termsRich(
        link: (children) => TextSpan(children: children),
        style: const TextStyle(fontSize: 42),
      );
      await _pump(tester, span);
      expect(_rendered(tester).style!.fontSize, 42);
    });

    testWidgets('switching locale changes the words, not the call', (
      tester,
    ) async {
      TextSpan link(List<InlineSpan> children) => TextSpan(children: children);

      await _pump(tester, ru.legal.termsRich(link: link));
      expect(
        _rendered(tester).toPlainText(),
        'Чтобы продолжить, прочитайте условия обслуживания',
      );
    });
  });

  group('l10nTextSpan, called by hand', () {
    test('folds the spans a generated accessor returns', () {
      final span = l10nTextSpan(
        en.legal.terms,
        tags: {'link': (children) => TextSpan(children: children)},
      );
      expect(span.toPlainText(), 'Read the terms of service to continue');
    });

    test('a tag with no builder throws, naming it', () {
      // Generated code cannot reach this: the wrapper requires a builder per
      // tag. A hand written call has no compiler to lean on, and rendering
      // the text unstyled would hide the mistake.
      expect(
        () => l10nTextSpan(en.legal.terms, tags: const {}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            allOf(contains('<link>'), contains('(none)')),
          ),
        ),
      );
    });
  });
}
