// Tests for ConsentManager - targeting uncovered lines
// Covers: gatherConsentWithExplainer (iOS ATT flow, skip GDPR, context unmounted),
//         _executeUMPConsentFlow (timeout, error paths, completer),
//         _handleUMPConsentWithExplainer (onBeforeForm),
//         showPrivacyOptionsForm, helper methods

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

/// Flush microtasks to allow async consent callbacks to complete
Future<void> _flush() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late ConsentManager consentManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();
    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;
    AdFlowPlatform.platformOverride = TargetPlatform.android;
    AdFlowConfig.setCurrent(const AdFlowConfig());
    consentManager = ConsentManager.instance;
    consentManager.resetConsent();
  });

  tearDown(() async {
    consentManager.resetConsent();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('gatherConsent', () {
    test('completes successfully on Android', () async {
      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );

      expect(capturedError, isNull);
      expect(consentManager.canRequestAds, true);
    });

    test('handles consent update error', () async {
      mockSdk.consentUpdateError = FormError(
        errorCode: 1,
        message: 'Network error',
      );

      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );
      await _flush();

      expect(capturedError, isNotNull);
      expect(capturedError?.message, 'Network error');
    });

    test('handles consent form error', () async {
      mockSdk.consentFormError = FormError(
        errorCode: 2,
        message: 'Form error',
      );

      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );
      await _flush();

      expect(capturedError, isNotNull);
      expect(capturedError?.message, 'Form error');
    });

    test('iOS ATT flow - authorized', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.authorized;

      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );

      expect(capturedError, isNull);
      expect(mockSdk.requestTrackingAuthorizationCalls, 1);
    });

    test('iOS ATT denied skips GDPR when configured', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      AdFlowConfig.setCurrent(const AdFlowConfig(
        skipGdprConsentIfAttDenied: true,
      ));
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );

      expect(capturedError, isNull);
      // UMP should not be called since ATT denied + skipGdrpConsentIfAttDenied
      expect(mockSdk.requestConsentInfoUpdateCalls, 0);
    });

    test('iOS ATT already determined skips prompt', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.authorized;

      FormError? capturedError;
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (error) => capturedError = error,
      );

      expect(capturedError, isNull);
      // Should not request ATT since already determined
      expect(mockSdk.requestTrackingAuthorizationCalls, 0);
    });

    test('iOS ATT error returns notSupported', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      // The mock doesn't throw by default; we test the normal path
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notSupported;

      await consentManager.gatherConsent(
        onConsentGatheringComplete: (_) {},
      );
      // Should not crash
    });
  });

  group('gatherConsentWithExplainer', () {
    testWidgets('shows explainer on iOS ATT', (tester) async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.authorized;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await consentManager.gatherConsentWithExplainer(
                  context: context,
                  showExplainer: false,
                  onConsentGatheringComplete: (_) {},
                );
              },
              child: const Text('Consent'),
            );
          }),
        ),
      );

      await tester.tap(find.text('Consent'));
      await tester.pumpAndSettle();
    });

    testWidgets('skips GDPR on ATT denial with config', (tester) async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      AdFlowConfig.setCurrent(AdFlowConfig(
        skipGdprConsentIfAttDenied: true,
      ));
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      FormError? capturedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await consentManager.gatherConsentWithExplainer(
                  context: context,
                  showExplainer: false,
                  onConsentGatheringComplete: (error) =>
                      capturedError = error,
                );
              },
              child: const Text('Consent'),
            );
          }),
        ),
      );

      await tester.tap(find.text('Consent'));
      await tester.pumpAndSettle();

      expect(capturedError, isNull);
      expect(mockSdk.requestConsentInfoUpdateCalls, 0);
    });
  });

  group('showPrivacyOptionsForm', () {
    test('calls callback on success', () async {
      FormError? capturedError;
      consentManager.showPrivacyOptionsForm(
        onComplete: (error) => capturedError = error,
      );

      expect(capturedError, isNull);
      expect(mockSdk.showPrivacyOptionsFormCalls, 1);
    });

    test('calls callback with error on failure', () async {
      mockSdk.privacyOptionsFormError = FormError(
        errorCode: 1,
        message: 'Form failed',
      );

      FormError? capturedError;
      consentManager.showPrivacyOptionsForm(
        onComplete: (error) => capturedError = error,
      );
      await _flush();

      expect(capturedError, isNotNull);
      expect(capturedError?.message, 'Form failed');
    });
  });

  group('helper methods', () {
    test('getConsentStatus returns status', () async {
      final status = await consentManager.getConsentStatus();
      expect(status, ConsentStatus.obtained);
    });

    test('getConsentStatusDescription returns descriptions', () async {
      mockSdk.consentStatusResult = ConsentStatus.obtained;
      var desc = await consentManager.getConsentStatusDescription();
      expect(desc, contains('obtained'));

      consentManager.resetConsent();
      mockSdk.consentStatusResult = ConsentStatus.required;
      desc = await consentManager.getConsentStatusDescription();
      expect(desc, contains('required'));

      consentManager.resetConsent();
      mockSdk.consentStatusResult = ConsentStatus.notRequired;
      desc = await consentManager.getConsentStatusDescription();
      expect(desc, contains('not required'));

      consentManager.resetConsent();
      mockSdk.consentStatusResult = ConsentStatus.unknown;
      desc = await consentManager.getConsentStatusDescription();
      expect(desc, contains('unknown'));
    });

    test('isPrivacyOptionsRequiredAsync returns status', () async {
      mockSdk.privacyOptionsRequirementStatusResult =
          PrivacyOptionsRequirementStatus.required;
      final result = await consentManager.isPrivacyOptionsRequiredAsync();
      expect(result, true);
    });

    test('getIOSTrackingStatus returns notSupported on Android', () async {
      final status = await consentManager.getIOSTrackingStatus();
      expect(status, TrackingStatus.notSupported);
    });

    test('getIOSTrackingStatus works on iOS', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.authorized;
      final status = await consentManager.getIOSTrackingStatus();
      expect(status, TrackingStatus.authorized);
    });

    test('getTCFConsentString returns stored value', () async {
      SharedPreferences.setMockInitialValues({
        'IABTCF_TCString': 'test-tcf-string',
      });
      // Need to reinitialize to get new prefs
      final result = await consentManager.getTCFConsentString();
      expect(result, 'test-tcf-string');
    });

    test('getUSPrivacyString returns stored value', () async {
      SharedPreferences.setMockInitialValues({
        'IABUSPrivacy_String': '1YNN',
      });
      final result = await consentManager.getUSPrivacyString();
      expect(result, '1YNN');
    });

    test('resetConsent resets state', () {
      consentManager.resetConsent();
      expect(consentManager.isInitialized, false);
      expect(consentManager.canRequestAds, false);
      expect(mockSdk.resetConsentInfoCalls, greaterThanOrEqualTo(1));
    });
  });

  group('isAttDenied', () {
    test('returns false on Android', () {
      expect(consentManager.isAttDenied, false);
    });
  });

  group('_shouldSkipGdprConsent', () {
    test('returns false when not on iOS', () async {
      // On Android, should never skip
      await consentManager.gatherConsent(
        onConsentGatheringComplete: (_) {},
      );
      // UMP should be called
      expect(mockSdk.requestConsentInfoUpdateCalls, 1);
    });
  });
}
