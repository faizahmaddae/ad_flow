import 'package:ad_flow/src/consent/explainer_content.dart';
import 'package:ad_flow/src/widgets/att_explainer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const content = AttExplainerContent(
    title: 'Allow tracking?',
    description: 'Apple will ask on the next screen.',
    footnote: 'It will not change how many ads you see.',
    continueLabel: 'Got it',
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
                final future = AttExplainerScreen.show(context, content);
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

  testWidgets('renders the title, description and footnote', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Allow tracking?'), findsOneWidget);
    expect(find.text('Apple will ask on the next screen.'), findsOneWidget);
    expect(
      find.text('It will not change how many ads you see.'),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('the continue button dismisses the primer', (tester) async {
    Future<void>? result;
    await pumpAndOpen(tester, capture: (f) => result = f);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await result; // completes on dismissal
    expect(find.text('Allow tracking?'), findsNothing);
  });

  testWidgets('renders the shipped default copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AttExplainerScreen(content: AttExplainerContent()),
      ),
    );
    expect(find.text('Allow tracking?'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });
}
