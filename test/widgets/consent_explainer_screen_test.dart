import 'package:ad_flow/src/consent/explainer_content.dart';
import 'package:ad_flow/src/widgets/consent_explainer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const content = ConsentExplainerContent(
    title: 'Your privacy matters',
    description: 'We would like your consent on the next screen.',
    bullets: ['Relevant ads', 'Secure data', 'Keeps the app free'],
    settingsHint: 'Change this anytime in Settings.',
    continueLabel: 'Continue',
    skipLabel: 'Decide next screen',
  );

  // Pumps a button that opens the primer; if [capture] is given it receives
  // the Future returned by `show(...)` so a test can await its completion.
  Future<void> pumpAndOpen(
    WidgetTester tester, {
    void Function(Future<void>)? capture,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                final future = ConsentExplainerScreen.show(context, content);
                capture?.call(future);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the title, description, bullets and hint', (
    tester,
  ) async {
    await pumpAndOpen(tester);
    expect(find.text('Your privacy matters'), findsOneWidget);
    expect(
      find.text('We would like your consent on the next screen.'),
      findsOneWidget,
    );
    expect(find.text('Relevant ads'), findsOneWidget);
    expect(find.text('Secure data'), findsOneWidget);
    expect(find.text('Keeps the app free'), findsOneWidget);
    expect(find.text('Change this anytime in Settings.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Decide next screen'), findsOneWidget);
  });

  testWidgets('the continue button dismisses the primer', (tester) async {
    Future<void>? result;
    await pumpAndOpen(tester, capture: (f) => result = f);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await result; // completes on dismissal
    expect(find.text('Your privacy matters'), findsNothing);
  });

  testWidgets('the secondary button also dismisses the primer', (tester) async {
    Future<void>? result;
    await pumpAndOpen(tester, capture: (f) => result = f);
    await tester.tap(find.text('Decide next screen'));
    await tester.pumpAndSettle();
    await result;
    expect(find.text('Your privacy matters'), findsNothing);
  });

  testWidgets('renders the shipped default copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConsentExplainerScreen(content: ConsentExplainerContent()),
      ),
    );
    expect(find.text('Your privacy matters'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text("I'll decide on the next screen"), findsOneWidget);
  });
}
