import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/widgets/rewarded_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const content = RewardIntroContent(
    title: 'Get 50 coins',
    message: 'Watch a short ad to earn 50 coins.',
    continueLabel: 'Watch ad',
    skipLabel: 'No thanks',
  );

  Future<Future<bool>> pumpAndOpen(WidgetTester tester) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  result = RewardedIntroScreen.show(context, content),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('renders the reward disclosure and both choices', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('Get 50 coins'), findsOneWidget);
    expect(find.text('Watch a short ad to earn 50 coins.'), findsOneWidget);
    expect(find.text('Watch ad'), findsOneWidget);
    expect(find.text('No thanks'), findsOneWidget); // skip is never absent
  });

  testWidgets('continue resolves true', (tester) async {
    final result = await pumpAndOpen(tester);
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('skip resolves false', (tester) async {
    final result = await pumpAndOpen(tester);
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('dismissing the route any other way counts as skip', (
    tester,
  ) async {
    final result = await pumpAndOpen(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop(); // e.g. system back
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
