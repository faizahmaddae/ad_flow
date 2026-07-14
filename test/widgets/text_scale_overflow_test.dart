import 'package:ad_flow/ad_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small phone (iPhone SE / low-end Android) at the system's maximum
/// accessibility text scale — a combination a real slice of the maintainer's
/// users run every day.
Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  double scale = 2.0,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(home: child),
    ),
  );
}

void main() {
  testWidgets(
    'POLICY: the rewarded-interstitial SKIP option stays reachable at 200% '
    'text scale',
    (tester) async {
      await pumpAt(
        tester,
        const RewardedIntroScreen(content: RewardIntroContent()),
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the intro screen must not overflow — the skip button is the '
            'LAST child, so it is the first thing clipped off-screen, and an '
            'unreachable skip option is an AdMob policy violation, not a nit',
      );

      // The mandatory skip must be reachable and actually work.
      final skip = find.text(const RewardIntroContent().skipLabel);
      await tester.ensureVisible(skip);
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the consent primer stays dismissable at 200% text scale', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const ConsentExplainerScreen(content: ConsentExplainerContent()),
    );

    expect(
      tester.takeException(),
      isNull,
      reason:
          'an overflowing primer pushes its only dismiss button '
          'off-screen — an un-escapable dead end before the GDPR form',
    );
    final continueButton = find.text(
      const ConsentExplainerContent().continueLabel,
    );
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ATT primer stays dismissable at 200% text scale', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const AttExplainerScreen(content: AttExplainerContent()),
    );

    expect(tester.takeException(), isNull);
    final continueButton = find.text(const AttExplainerContent().continueLabel);
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('at normal text scale the intro is still vertically centred', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const RewardedIntroScreen(content: RewardIntroContent()),
      scale: 1.0,
    );

    expect(tester.takeException(), isNull);
    // Nothing to scroll when it fits: the content is centred, not top-aligned.
    final column = tester.getRect(find.byType(Column).first);
    expect(column.top, greaterThan(0));
  });
}
