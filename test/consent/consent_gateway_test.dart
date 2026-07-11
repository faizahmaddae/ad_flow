import 'dart:async';

import 'package:ad_flow/src/consent/consent_gateway.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late UmpConsentGateway gateway;

  setUp(() {
    sdk = FakeAdSdk();
    gateway = UmpConsentGateway(sdk);
  });
  tearDown(() => sdk.dispose());

  group('ensureCanRequestAds', () {
    test('non-EEA: update runs, form no-ops, gate opens', () async {
      sdk.consentStatus = AdConsentStatus.notRequired;
      sdk.canRequestAdsResult = true;

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(sdk.consentUpdateCalls, hasLength(1));
      // Mirrors Google's sample: called unconditionally, no-ops internally.
      expect(sdk.loadAndShowConsentFormCalls, 1);
      expect(gateway.lastError, isNull);
    });

    test('EEA: form dismissal opens the gate', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(sdk.loadAndShowConsentFormCalls, 1);
      expect(gateway.lastError, isNull);
    });

    test('EEA: user keeps consent unresolved, gate stays closed', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false;

      expect(await gateway.ensureCanRequestAds(), isFalse);
    });

    test('update error degrades to canRequestAds (previously obtained)',
        () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'network down');
      sdk.consentUpdateError = error;
      sdk.canRequestAdsResult = true; // consent obtained on a prior launch

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(gateway.lastError, same(error));
      // Form step must be skipped after a failed update.
      expect(sdk.loadAndShowConsentFormCalls, 0);
    });

    test('update error with no prior consent yields false', () async {
      sdk.consentUpdateError = const AdFlowError(
        AdFlowErrorKind.consent,
        'network down',
      );
      sdk.canRequestAdsResult = false;

      expect(await gateway.ensureCanRequestAds(), isFalse);
      expect(gateway.lastError, isNotNull);
    });

    test('form error degrades to canRequestAds and surfaces lastError',
        () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'form failed');
      sdk.consentFormError = error;
      sdk.canRequestAdsResult = false;

      expect(await gateway.ensureCanRequestAds(), isFalse);
      expect(gateway.lastError, same(error));
    });

    test('lastError clears on a subsequent successful run', () async {
      sdk.consentUpdateError = const AdFlowError(
        AdFlowErrorKind.consent,
        'flaky',
      );
      await gateway.ensureCanRequestAds();
      expect(gateway.lastError, isNotNull);

      sdk.consentUpdateError = null;
      sdk.canRequestAdsResult = true;
      await gateway.ensureCanRequestAds();
      expect(gateway.lastError, isNull);
    });

    test('hanging info update times out and degrades', () async {
      gateway = UmpConsentGateway(
        sdk,
        infoUpdateTimeout: const Duration(milliseconds: 50),
      );
      sdk.consentUpdateHold = Completer<void>();
      sdk.canRequestAdsResult = true;

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(gateway.lastError?.kind, AdFlowErrorKind.timeout);
      expect(sdk.loadAndShowConsentFormCalls, 0);
    });

    test('concurrent calls join the in-flight run (double-load guard)',
        () async {
      sdk.consentUpdateHold = Completer<void>();
      sdk.canRequestAdsResult = true;

      final first = gateway.ensureCanRequestAds();
      final second = gateway.ensureCanRequestAds();
      sdk.consentUpdateHold!.complete();

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(sdk.consentUpdateCalls, hasLength(1));
      expect(sdk.loadAndShowConsentFormCalls, 1);
    });

    test('a later call after completion runs the flow again', () async {
      sdk.canRequestAdsResult = true;
      await gateway.ensureCanRequestAds();
      await gateway.ensureCanRequestAds();
      expect(sdk.consentUpdateCalls, hasLength(2));
    });

    test('forwards tagForUnderAgeOfConsent and debug options', () async {
      gateway = UmpConsentGateway(sdk, tagForUnderAgeOfConsent: true);
      const debug = ConsentDebugOptions(
        geography: ConsentDebugGeography.eea,
        testIdentifiers: ['HASH'],
      );

      await gateway.ensureCanRequestAds(debug: debug);

      expect(sdk.consentUpdateCalls.single.tagForUnderAgeOfConsent, isTrue);
      expect(sdk.consentUpdateCalls.single.debug, same(debug));
    });
  });

  group('privacy options', () {
    test('isPrivacyOptionsRequired reflects the post-flow status', () async {
      sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
      expect(gateway.isPrivacyOptionsRequired, isFalse); // before the flow

      await gateway.ensureCanRequestAds();
      expect(gateway.isPrivacyOptionsRequired, isTrue);
    });

    test('showPrivacyOptions delegates to the seam', () async {
      await gateway.showPrivacyOptions();
      expect(sdk.showPrivacyOptionsFormCalls, 1);
    });

    test('showPrivacyOptions rethrows form errors', () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'no form');
      sdk.privacyOptionsFormError = error;
      await expectLater(gateway.showPrivacyOptions(), throwsA(same(error)));
    });
  });

  test('reset delegates to the seam', () async {
    await gateway.reset();
    expect(sdk.resetConsentCalls, 1);
  });
}
