import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/consent/explainer_content.dart';
import 'package:ad_flow/src/widgets/att_explainer_screen.dart';
import 'package:ad_flow/src/widgets/consent_explainer_screen.dart';
import 'package:ad_flow/src/widgets/rewarded_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The `presenter(navigatorKey)` helpers replace the presenter closure every
// app used to write by hand (resolve the key's context, bail when it is not
// mounted, show the screen). They must behave exactly like that closure: show
// on the key's navigator, and degrade — never throw — when there is none.
void main() {
  const intro = RewardIntroContent(
    title: 'Get 50 coins',
    continueLabel: 'Watch ad',
    skipLabel: 'No thanks',
  );

  Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const SizedBox()),
    );
    return key;
  }

  group('RewardedIntroScreen.presenter', () {
    testWidgets('shows the intro on the key\'s navigator and resolves the '
        'user\'s choice', (tester) async {
      final key = await pumpApp(tester);
      final watched = RewardedIntroScreen.presenter(key)(intro);
      await tester.pumpAndSettle();
      expect(find.text('Get 50 coins'), findsOneWidget);
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(await watched, isTrue);

      final skipped = RewardedIntroScreen.presenter(key)(intro);
      await tester.pumpAndSettle();
      await tester.tap(find.text('No thanks'));
      await tester.pumpAndSettle();
      expect(await skipped, isFalse);
    });

    testWidgets('resolves false — the ad is skipped, nothing throws — when '
        'the navigator is not mounted', (tester) async {
      final key = GlobalKey<NavigatorState>();
      expect(await RewardedIntroScreen.presenter(key)(intro), isFalse);
    });
  });

  group('AttExplainerScreen.presenter', () {
    testWidgets('shows the primer and completes when it is dismissed', (
      tester,
    ) async {
      final key = await pumpApp(tester);
      var done = false;
      final shown = AttExplainerScreen.presenter(key)(
        const AttExplainerContent(),
      ).then((_) => done = true);
      await tester.pumpAndSettle();
      expect(find.byType(AttExplainerScreen), findsOneWidget);
      expect(done, isFalse, reason: 'it waits for the user');
      await tester.tap(find.text(const AttExplainerContent().continueLabel));
      await tester.pumpAndSettle();
      await shown;
      expect(done, isTrue);
    });

    testWidgets('completes without throwing when the navigator is not '
        'mounted (Apple\'s prompt still follows)', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await AttExplainerScreen.presenter(key)(const AttExplainerContent());
    });
  });

  group('ConsentExplainerScreen.presenter', () {
    testWidgets('shows the primer and completes when it is dismissed', (
      tester,
    ) async {
      final key = await pumpApp(tester);
      var done = false;
      final shown = ConsentExplainerScreen.presenter(key)(
        const ConsentExplainerContent(),
      ).then((_) => done = true);
      await tester.pumpAndSettle();
      expect(find.byType(ConsentExplainerScreen), findsOneWidget);
      expect(done, isFalse, reason: 'it waits for the user');
      await tester.tap(
        find.text(const ConsentExplainerContent().continueLabel),
      );
      await tester.pumpAndSettle();
      await shown;
      expect(done, isTrue);
    });

    testWidgets('completes without throwing when the navigator is not '
        'mounted (the GDPR form still follows)', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await ConsentExplainerScreen.presenter(key)(
        const ConsentExplainerContent(),
      );
    });
  });
}
