// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for ConsentManager

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

/// Helper to gather consent and wait for the callback to fire.
/// gatherConsent does NOT await the UMP flow, so we must use a Completer.
Future<FormError?> _gatherConsentAndWait(ConsentManager manager) async {
  final completer = Completer<FormError?>();
  manager.gatherConsent(
    onConsentGatheringComplete: (error) {
      if (!completer.isCompleted) completer.complete(error);
    },
  );
  // The UMP flow uses a chain of async callbacks inside void-returning
  // methods. We need multiple microtask pumps for them to complete.
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
  if (!completer.isCompleted) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(
      const AdFlowConfig(
        enableConsentDebug: false,
        tagForUnderAgeOfConsent: false,
      ),
    );
    AdFlowPlatform.platformOverride = TargetPlatform.android;
  });

  tearDown(() {
    ConsentManager.instance.resetConsent();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('singleton', () {
    test('returns same instance', () {
      expect(identical(ConsentManager.instance, ConsentManager.instance), true);
    });
  });

  group('initial state', () {
    test('isInitialized is false', () {
      expect(ConsentManager.instance.isInitialized, false);
    });

    test('canRequestAds is false initially', () {
      expect(ConsentManager.instance.canRequestAds, false);
    });

    test('isPrivacyOptionsRequired returns false', () {
      expect(ConsentManager.instance.isPrivacyOptionsRequired(), false);
    });

    test('lastAttStatus is null initially', () {
      expect(ConsentManager.instance.lastAttStatus, isNull);
    });

    test('isAttDenied is false initially', () {
      expect(ConsentManager.instance.isAttDenied, false);
    });
  });

  group('gatherConsent - Android (no ATT)', () {
    test('completes successfully and sets isInitialized', () async {
      final result = await _gatherConsentAndWait(ConsentManager.instance);

      expect(result, isNull);
      expect(ConsentManager.instance.isInitialized, true);
    });

    test('calls requestConsentInfoUpdate', () async {
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(mockSdk.requestConsentInfoUpdateCalls, 1);
    });

    test('calls loadAndShowConsentFormIfRequired', () async {
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(mockSdk.loadAndShowConsentFormCalls, 1);
    });

    test('updates canRequestAds to true', () async {
      mockSdk.canRequestAdsResult = true;
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(ConsentManager.instance.canRequestAds, true);
    });

    test('does NOT request ATT on Android', () async {
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(mockSdk.getTrackingAuthorizationStatusCalls, 0);
      expect(mockSdk.requestTrackingAuthorizationCalls, 0);
    });
  });

  group('gatherConsent - iOS (with ATT)', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
    });

    test('requests ATT on iOS when notDetermined', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.authorized;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(mockSdk.getTrackingAuthorizationStatusCalls, 1);
      expect(mockSdk.requestTrackingAuthorizationCalls, 1);
    });

    test('skips ATT request when already determined', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.authorized;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(mockSdk.getTrackingAuthorizationStatusCalls, 1);
      expect(mockSdk.requestTrackingAuthorizationCalls, 0);
    });

    test('sets lastAttStatus after ATT request', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(ConsentManager.instance.lastAttStatus, TrackingStatus.denied);
    });

    test('skips GDPR when ATT denied and config set', () async {
      AdFlowConfig.setCurrent(
        const AdFlowConfig(skipGdprConsentIfAttDenied: true),
      );
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(mockSdk.requestConsentInfoUpdateCalls, 0);
      expect(ConsentManager.instance.isInitialized, true);
    });

    test('does NOT skip GDPR when ATT denied but config is false', () async {
      AdFlowConfig.setCurrent(
        const AdFlowConfig(skipGdprConsentIfAttDenied: false),
      );
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(mockSdk.requestConsentInfoUpdateCalls, 1);
    });

    test('isAttDenied returns true when denied', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
      mockSdk.requestTrackingResult = TrackingStatus.denied;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(ConsentManager.instance.isAttDenied, true);
    });

    test('isAttDenied returns true when restricted', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.restricted;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(ConsentManager.instance.isAttDenied, true);
    });

    test('isAttDenied returns false when authorized', () async {
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.authorized;

      await _gatherConsentAndWait(ConsentManager.instance);

      expect(ConsentManager.instance.isAttDenied, false);
    });
  });

  group('gatherConsent - error handling', () {
    test('handles consent update error', () async {
      mockSdk.consentUpdateError = FormError(
        errorCode: 99,
        message: 'Network error',
      );

      final result = await _gatherConsentAndWait(ConsentManager.instance);

      expect(result, isNotNull);
      expect(result!.errorCode, 99);
      expect(ConsentManager.instance.isInitialized, true);
    });

    test('handles consent form error', () async {
      mockSdk.consentFormError = FormError(
        errorCode: 42,
        message: 'Form error',
      );

      final result = await _gatherConsentAndWait(ConsentManager.instance);

      expect(result, isNotNull);
      expect(result!.errorCode, 42);
    });

    test('reports consent error to AdFlowErrorHandler', () async {
      mockSdk.consentUpdateError = FormError(
        errorCode: 99,
        message: 'Network error',
      );

      AdFlowError? capturedError;
      final sub = AdFlowErrorHandler.instance.errorStream.listen((e) {
        capturedError = e;
      });

      await _gatherConsentAndWait(ConsentManager.instance);
      await Future.delayed(Duration.zero);

      expect(capturedError, isNotNull);
      expect(capturedError!.type, AdErrorType.consent);

      await sub.cancel();
    });
  });

  group('consent flow', () {
    test('gathers consent successfully', () async {
      final result = await _gatherConsentAndWait(ConsentManager.instance);
      expect(result, isNull);
      expect(ConsentManager.instance.isInitialized, true);
    });
  });

  group('getIOSTrackingStatus', () {
    test('returns notSupported on Android', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      final status = await ConsentManager.instance.getIOSTrackingStatus();
      expect(status, TrackingStatus.notSupported);
    });

    test('returns status on iOS', () async {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      mockSdk.trackingAuthorizationStatusResult = TrackingStatus.authorized;
      final status = await ConsentManager.instance.getIOSTrackingStatus();
      expect(status, TrackingStatus.authorized);
    });
  });

  group('getConsentStatus', () {
    test('returns consent status', () async {
      mockSdk.consentStatusResult = ConsentStatus.obtained;
      final status = await ConsentManager.instance.getConsentStatus();
      expect(status, ConsentStatus.obtained);
    });

    test('returns required status', () async {
      mockSdk.consentStatusResult = ConsentStatus.required;
      final status = await ConsentManager.instance.getConsentStatus();
      expect(status, ConsentStatus.required);
    });
  });

  group('getConsentStatusDescription', () {
    test('returns description for obtained', () async {
      mockSdk.consentStatusResult = ConsentStatus.obtained;
      final desc = await ConsentManager.instance.getConsentStatusDescription();
      expect(desc, contains('obtained'));
    });

    test('returns description for required', () async {
      mockSdk.consentStatusResult = ConsentStatus.required;
      final desc = await ConsentManager.instance.getConsentStatusDescription();
      expect(desc, contains('required'));
    });

    test('returns description for notRequired', () async {
      mockSdk.consentStatusResult = ConsentStatus.notRequired;
      final desc = await ConsentManager.instance.getConsentStatusDescription();
      expect(desc, contains('not required'));
    });

    test('returns description for unknown', () async {
      mockSdk.consentStatusResult = ConsentStatus.unknown;
      final desc = await ConsentManager.instance.getConsentStatusDescription();
      expect(desc, contains('unknown'));
    });
  });

  group('isPrivacyOptionsRequiredAsync', () {
    test('returns true when required', () async {
      mockSdk.privacyOptionsRequirementStatusResult =
          PrivacyOptionsRequirementStatus.required;
      final result = await ConsentManager.instance
          .isPrivacyOptionsRequiredAsync();
      expect(result, true);
    });

    test('returns false when not required', () async {
      mockSdk.privacyOptionsRequirementStatusResult =
          PrivacyOptionsRequirementStatus.notRequired;
      final result = await ConsentManager.instance
          .isPrivacyOptionsRequiredAsync();
      expect(result, false);
    });
  });

  group('showPrivacyOptionsForm', () {
    test('calls SDK showPrivacyOptionsForm', () async {
      final completer = Completer<FormError?>();
      ConsentManager.instance.showPrivacyOptionsForm(
        onComplete: (error) {
          if (!completer.isCompleted) completer.complete(error);
        },
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      final result = await completer.future;
      expect(mockSdk.showPrivacyOptionsFormCalls, 1);
      expect(result, isNull);
    });

    test('returns error if form fails', () async {
      mockSdk.privacyOptionsFormError = FormError(
        errorCode: 1,
        message: 'Form failed',
      );

      final completer = Completer<FormError?>();
      ConsentManager.instance.showPrivacyOptionsForm(
        onComplete: (error) {
          if (!completer.isCompleted) completer.complete(error);
        },
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      final result = await completer.future;

      expect(result, isNotNull);
      expect(result!.errorCode, 1);
    });
  });

  group('resetConsent', () {
    test('resets all state', () async {
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(ConsentManager.instance.isInitialized, true);

      ConsentManager.instance.resetConsent();

      expect(ConsentManager.instance.isInitialized, false);
      expect(ConsentManager.instance.canRequestAds, false);
      expect(ConsentManager.instance.lastAttStatus, isNull);
      expect(mockSdk.resetConsentInfoCalls, 1);
    });
  });

  group('isPrivacyOptionsRequired after consent', () {
    test('returns true when status is required', () async {
      mockSdk.privacyOptionsRequirementStatusResult =
          PrivacyOptionsRequirementStatus.required;
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(ConsentManager.instance.isPrivacyOptionsRequired(), true);
    });

    test('returns false when not required', () async {
      mockSdk.privacyOptionsRequirementStatusResult =
          PrivacyOptionsRequirementStatus.notRequired;
      await _gatherConsentAndWait(ConsentManager.instance);
      expect(ConsentManager.instance.isPrivacyOptionsRequired(), false);
    });
  });

  group('TCF and US Privacy strings', () {
    test('getTCFConsentString returns null when not set', () async {
      final result = await ConsentManager.instance.getTCFConsentString();
      expect(result, isNull);
    });

    test('getTCFConsentString returns stored value', () async {
      SharedPreferences.setMockInitialValues({
        'IABTCF_TCString': 'test-tc-string',
      });
      final result = await ConsentManager.instance.getTCFConsentString();
      expect(result, 'test-tc-string');
    });

    test('getUSPrivacyString returns null when not set', () async {
      final result = await ConsentManager.instance.getUSPrivacyString();
      expect(result, isNull);
    });

    test('getUSPrivacyString returns stored value', () async {
      SharedPreferences.setMockInitialValues({'IABUSPrivacy_String': '1YNN'});
      final result = await ConsentManager.instance.getUSPrivacyString();
      expect(result, '1YNN');
    });
  });
}
