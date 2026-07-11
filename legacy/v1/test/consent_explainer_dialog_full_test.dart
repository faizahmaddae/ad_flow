// Copyright 2024 - AdMob Integration Package
// Tests for ConsentExplainerDialog and ATTExplainerDialog

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void addTeardownViewReset(WidgetTester tester) {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('ConsentExplainerTexts', () {
    test('default constructor has all fields', () {
      const texts = ConsentExplainerTexts();
      expect(texts.title, 'Your Privacy Matters');
      expect(texts.description, isNotEmpty);
      expect(texts.benefitRelevantAds, isNotEmpty);
      expect(texts.benefitDataSecure, isNotEmpty);
      expect(texts.benefitKeepFree, isNotEmpty);
      expect(texts.settingsHint, isNotEmpty);
      expect(texts.continueButton, 'Continue');
      expect(texts.skipButton, isNotEmpty);
    });

    test('copyWith replaces fields', () {
      const texts = ConsentExplainerTexts();
      final copy = texts.copyWith(title: 'Test Title', continueButton: 'Go');
      expect(copy.title, 'Test Title');
      expect(copy.continueButton, 'Go');
      expect(copy.description, texts.description);
    });

    test('copyWith replaces all fields', () {
      const texts = ConsentExplainerTexts();
      final copy = texts.copyWith(
        title: 'T',
        description: 'D',
        benefitRelevantAds: 'R',
        benefitDataSecure: 'S',
        benefitKeepFree: 'F',
        settingsHint: 'H',
        continueButton: 'C',
        skipButton: 'K',
      );
      expect(copy.title, 'T');
      expect(copy.description, 'D');
      expect(copy.benefitRelevantAds, 'R');
      expect(copy.benefitDataSecure, 'S');
      expect(copy.benefitKeepFree, 'F');
      expect(copy.settingsHint, 'H');
      expect(copy.continueButton, 'C');
      expect(copy.skipButton, 'K');
    });
  });

  group('ATTExplainerTexts', () {
    test('default constructor has all fields', () {
      const texts = ATTExplainerTexts();
      expect(texts.title, 'Allow Tracking?');
      expect(texts.description, isNotEmpty);
      expect(texts.footnote, isNotEmpty);
      expect(texts.gotItButton, 'Got it');
    });

    test('copyWith replaces fields', () {
      const texts = ATTExplainerTexts();
      final copy = texts.copyWith(title: 'Test', gotItButton: 'OK');
      expect(copy.title, 'Test');
      expect(copy.gotItButton, 'OK');
      expect(copy.description, texts.description);
      expect(copy.footnote, texts.footnote);
    });

    test('copyWith replaces all fields', () {
      const texts = ATTExplainerTexts();
      final copy = texts.copyWith(
        title: 'T',
        description: 'D',
        footnote: 'F',
        gotItButton: 'G',
      );
      expect(copy.title, 'T');
      expect(copy.description, 'D');
      expect(copy.footnote, 'F');
      expect(copy.gotItButton, 'G');
    });
  });

  group('default constants', () {
    test('kDefaultConsentExplainerTexts exists', () {
      expect(kDefaultConsentExplainerTexts, isA<ConsentExplainerTexts>());
      expect(kDefaultConsentExplainerTexts.title, 'Your Privacy Matters');
    });

    test('kDefaultATTExplainerTexts exists', () {
      expect(kDefaultATTExplainerTexts, isA<ATTExplainerTexts>());
      expect(kDefaultATTExplainerTexts.title, 'Allow Tracking?');
    });
  });

  group('ConsentExplainerDialog widget', () {
    testWidgets('shows dialog with default texts and continue returns true', (
      tester,
    ) async {
      // Use a large surface so content fits
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTeardownViewReset(tester);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? result;
      ConsentExplainerDialog.show(capturedContext).then((v) => result = v);
      await tester.pumpAndSettle();

      // Verify dialog content
      expect(find.text('Your Privacy Matters'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      // Tap continue
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(result, true);
    });

    testWidgets('shows custom texts', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTeardownViewReset(tester);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      ConsentExplainerDialog.show(
        capturedContext,
        texts: const ConsentExplainerTexts(
          title: 'Custom Title',
          continueButton: 'Go!',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Title'), findsOneWidget);
      expect(find.text('Go!'), findsOneWidget);

      // Dismiss dialog to avoid deactivated widget error
      await tester.tap(find.text('Go!'));
      await tester.pumpAndSettle();
    });

    testWidgets('skip button returns false, continue returns true', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTeardownViewReset(tester);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? result;
      ConsentExplainerDialog.show(capturedContext).then((v) => result = v);
      await tester.pumpAndSettle();

      // Skip button is present
      final skipFinder = find.text("I'll decide on the next screen");
      expect(skipFinder, findsOneWidget);
      await tester.tap(skipFinder);
      await tester.pumpAndSettle();

      // Skip button pops false to differentiate from Continue
      expect(result, false);
    });
  });

  group('ATTExplainerDialog widget', () {
    testWidgets('shows dialog with default texts', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? result;
      ATTExplainerDialog.show(capturedContext).then((v) => result = v);
      await tester.pumpAndSettle();

      expect(find.text('Allow Tracking?'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(result, true);
    });

    testWidgets('shows custom texts', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      ATTExplainerDialog.show(
        capturedContext,
        texts: const ATTExplainerTexts(title: 'Custom ATT', gotItButton: 'OK'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom ATT'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });
  });
}
