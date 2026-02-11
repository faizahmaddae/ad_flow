// Copyright 2024 - AdMob Integration Package
// Tests for consent_explainer_localizations.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  group('getConsentTextsForLanguage', () {
    test('returns Persian texts for fa', () {
      final texts = getConsentTextsForLanguage('fa');
      expect(texts.title, contains('حریم'));
    });

    test('returns Persian texts for per', () {
      final texts = getConsentTextsForLanguage('per');
      expect(texts.title, contains('حریم'));
    });

    test('returns Persian texts for fas', () {
      final texts = getConsentTextsForLanguage('fas');
      expect(texts.title, contains('حریم'));
    });

    test('returns Spanish texts for es', () {
      final texts = getConsentTextsForLanguage('es');
      expect(texts.title, contains('Privacidad'));
    });

    test('returns Spanish texts for spa', () {
      final texts = getConsentTextsForLanguage('spa');
      expect(texts.title, contains('Privacidad'));
    });

    test('returns English texts for en', () {
      final texts = getConsentTextsForLanguage('en');
      expect(texts.title, 'Your Privacy Matters');
    });

    test('returns English texts for eng', () {
      final texts = getConsentTextsForLanguage('eng');
      expect(texts.title, 'Your Privacy Matters');
    });

    test('returns English texts for unknown code', () {
      final texts = getConsentTextsForLanguage('zz');
      expect(texts.title, 'Your Privacy Matters');
    });

    test('is case-insensitive', () {
      final texts = getConsentTextsForLanguage('FA');
      expect(texts.title, contains('حریم'));
    });
  });

  group('getATTTextsForLanguage', () {
    test('returns Persian texts for fa', () {
      final texts = getATTTextsForLanguage('fa');
      expect(texts.title, contains('ردیابی'));
    });

    test('returns Persian texts for per', () {
      final texts = getATTTextsForLanguage('per');
      expect(texts.title, contains('ردیابی'));
    });

    test('returns Persian texts for fas', () {
      final texts = getATTTextsForLanguage('fas');
      expect(texts.title, contains('ردیابی'));
    });

    test('returns Spanish texts for es', () {
      final texts = getATTTextsForLanguage('es');
      expect(texts.title, contains('Seguimiento'));
    });

    test('returns Spanish texts for spa', () {
      final texts = getATTTextsForLanguage('spa');
      expect(texts.title, contains('Seguimiento'));
    });

    test('returns English texts for en', () {
      final texts = getATTTextsForLanguage('en');
      expect(texts.title, 'Allow Tracking?');
    });

    test('returns English texts for eng', () {
      final texts = getATTTextsForLanguage('eng');
      expect(texts.title, 'Allow Tracking?');
    });

    test('returns English texts for unknown code', () {
      final texts = getATTTextsForLanguage('xx');
      expect(texts.title, 'Allow Tracking?');
    });
  });

  group('getExplainerTextsForLanguage', () {
    test('returns both consent and ATT texts', () {
      final (consent, att) = getExplainerTextsForLanguage('es');
      expect(consent.title, contains('Privacidad'));
      expect(att.title, contains('Seguimiento'));
    });

    test('works for Persian', () {
      final (consent, att) = getExplainerTextsForLanguage('fa');
      expect(consent.continueButton, isNotEmpty);
      expect(att.gotItButton, isNotEmpty);
    });

    test('works for English', () {
      final (consent, att) = getExplainerTextsForLanguage('en');
      expect(consent.continueButton, 'Continue');
      expect(att.gotItButton, 'Got it');
    });
  });

  group('predefined constants', () {
    test('kPersianConsentExplainerTexts has all fields', () {
      expect(kPersianConsentExplainerTexts.title, isNotEmpty);
      expect(kPersianConsentExplainerTexts.description, isNotEmpty);
      expect(kPersianConsentExplainerTexts.benefitRelevantAds, isNotEmpty);
      expect(kPersianConsentExplainerTexts.benefitDataSecure, isNotEmpty);
      expect(kPersianConsentExplainerTexts.benefitKeepFree, isNotEmpty);
      expect(kPersianConsentExplainerTexts.settingsHint, isNotEmpty);
      expect(kPersianConsentExplainerTexts.continueButton, isNotEmpty);
      expect(kPersianConsentExplainerTexts.skipButton, isNotEmpty);
    });

    test('kPersianATTExplainerTexts has all fields', () {
      expect(kPersianATTExplainerTexts.title, isNotEmpty);
      expect(kPersianATTExplainerTexts.description, isNotEmpty);
      expect(kPersianATTExplainerTexts.footnote, isNotEmpty);
      expect(kPersianATTExplainerTexts.gotItButton, isNotEmpty);
    });

    test('kSpanishConsentExplainerTexts has all fields', () {
      expect(kSpanishConsentExplainerTexts.title, isNotEmpty);
      expect(kSpanishConsentExplainerTexts.description, isNotEmpty);
      expect(kSpanishConsentExplainerTexts.continueButton, isNotEmpty);
    });

    test('kSpanishATTExplainerTexts has all fields', () {
      expect(kSpanishATTExplainerTexts.title, isNotEmpty);
      expect(kSpanishATTExplainerTexts.description, isNotEmpty);
      expect(kSpanishATTExplainerTexts.gotItButton, isNotEmpty);
    });
  });
}
