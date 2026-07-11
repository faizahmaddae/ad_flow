// Copyright 2024 - AdMob Integration Package
// Unit tests for ConsentExplainerTexts and ATTExplainerTexts

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  group('ConsentExplainerTexts', () {
    group('default values', () {
      test('has correct default title', () {
        const texts = ConsentExplainerTexts();
        expect(texts.title, 'Your Privacy Matters');
      });

      test('has correct default continueButton', () {
        const texts = ConsentExplainerTexts();
        expect(texts.continueButton, 'Continue');
      });

      test('has correct default skipButton', () {
        const texts = ConsentExplainerTexts();
        expect(texts.skipButton, "I'll decide on the next screen");
      });

      test('has correct default benefits', () {
        const texts = ConsentExplainerTexts();
        expect(texts.benefitRelevantAds, 'Ads that match your interests');
        expect(texts.benefitDataSecure, 'Your data stays secure');
        expect(texts.benefitKeepFree, 'Helps keep the app free');
      });
    });

    group('custom values', () {
      test('accepts custom title', () {
        const texts = ConsentExplainerTexts(title: 'Custom Title');
        expect(texts.title, 'Custom Title');
      });

      test('accepts custom continueButton', () {
        const texts = ConsentExplainerTexts(continueButton: 'Next');
        expect(texts.continueButton, 'Next');
      });

      test('accepts all custom values', () {
        const texts = ConsentExplainerTexts(
          title: 'Privacy',
          description: 'Custom description',
          benefitRelevantAds: 'Relevant ads',
          benefitDataSecure: 'Secure data',
          benefitKeepFree: 'Free app',
          settingsHint: 'Custom hint',
          continueButton: 'OK',
          skipButton: 'Skip',
        );

        expect(texts.title, 'Privacy');
        expect(texts.description, 'Custom description');
        expect(texts.benefitRelevantAds, 'Relevant ads');
        expect(texts.benefitDataSecure, 'Secure data');
        expect(texts.benefitKeepFree, 'Free app');
        expect(texts.settingsHint, 'Custom hint');
        expect(texts.continueButton, 'OK');
        expect(texts.skipButton, 'Skip');
      });
    });

    group('copyWith', () {
      test('creates copy with single changed value', () {
        const original = ConsentExplainerTexts();
        final copy = original.copyWith(title: 'New Title');

        expect(copy.title, 'New Title');
        expect(copy.continueButton, original.continueButton);
        expect(copy.description, original.description);
      });

      test('creates copy with multiple changed values', () {
        const original = ConsentExplainerTexts();
        final copy = original.copyWith(
          title: 'New Title',
          continueButton: 'Proceed',
          skipButton: 'Not now',
        );

        expect(copy.title, 'New Title');
        expect(copy.continueButton, 'Proceed');
        expect(copy.skipButton, 'Not now');
        expect(copy.description, original.description);
      });

      test('returns unchanged copy when no arguments provided', () {
        const original = ConsentExplainerTexts();
        final copy = original.copyWith();

        expect(copy.title, original.title);
        expect(copy.continueButton, original.continueButton);
        expect(copy.description, original.description);
      });
    });
  });

  group('ATTExplainerTexts', () {
    group('default values', () {
      test('has correct default title', () {
        const texts = ATTExplainerTexts();
        expect(texts.title, 'Allow Tracking?');
      });

      test('has correct default gotItButton', () {
        const texts = ATTExplainerTexts();
        expect(texts.gotItButton, 'Got it');
      });

      test('has correct default footnote', () {
        const texts = ATTExplainerTexts();
        expect(
          texts.footnote,
          "Your choice won't affect the number of ads you see.",
        );
      });
    });

    group('custom values', () {
      test('accepts custom title', () {
        const texts = ATTExplainerTexts(title: 'Tracking Permission');
        expect(texts.title, 'Tracking Permission');
      });

      test('accepts all custom values', () {
        const texts = ATTExplainerTexts(
          title: 'Tracking',
          description: 'Custom ATT description',
          footnote: 'Custom footnote',
          gotItButton: 'Understood',
        );

        expect(texts.title, 'Tracking');
        expect(texts.description, 'Custom ATT description');
        expect(texts.footnote, 'Custom footnote');
        expect(texts.gotItButton, 'Understood');
      });
    });

    group('copyWith', () {
      test('creates copy with single changed value', () {
        const original = ATTExplainerTexts();
        final copy = original.copyWith(title: 'New ATT Title');

        expect(copy.title, 'New ATT Title');
        expect(copy.gotItButton, original.gotItButton);
      });

      test('creates copy with multiple changed values', () {
        const original = ATTExplainerTexts();
        final copy = original.copyWith(
          title: 'Tracking Info',
          gotItButton: 'OK',
        );

        expect(copy.title, 'Tracking Info');
        expect(copy.gotItButton, 'OK');
        expect(copy.footnote, original.footnote);
      });
    });
  });

  group('default constants', () {
    test('kDefaultConsentExplainerTexts has expected values', () {
      expect(kDefaultConsentExplainerTexts.title, 'Your Privacy Matters');
      expect(kDefaultConsentExplainerTexts.continueButton, 'Continue');
    });

    test('kDefaultATTExplainerTexts has expected values', () {
      expect(kDefaultATTExplainerTexts.title, 'Allow Tracking?');
      expect(kDefaultATTExplainerTexts.gotItButton, 'Got it');
    });
  });

  group('localization examples', () {
    test('Spanish localization example', () {
      const spanishTexts = ConsentExplainerTexts(
        title: 'Tu Privacidad Importa',
        continueButton: 'Continuar',
        skipButton: 'Decidiré en la siguiente pantalla',
      );

      expect(spanishTexts.title, 'Tu Privacidad Importa');
      expect(spanishTexts.continueButton, 'Continuar');
    });

    test('German ATT localization example', () {
      const germanATT = ATTExplainerTexts(
        title: 'Tracking erlauben?',
        gotItButton: 'Verstanden',
      );

      expect(germanATT.title, 'Tracking erlauben?');
      expect(germanATT.gotItButton, 'Verstanden');
    });

    test('French localization example', () {
      const frenchTexts = ConsentExplainerTexts(
        title: 'Votre vie privée compte',
        continueButton: 'Continuer',
      );

      expect(frenchTexts.title, 'Votre vie privée compte');
    });
  });
}
