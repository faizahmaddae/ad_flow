// Tests for MediationHelper - comprehensive

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  setUp(() {
    MediationHelper.reset();
  });

  tearDown(() {
    MediationHelper.reset();
  });

  group('MediationHelper', () {
    test('hasAdapters is false initially', () {
      expect(MediationHelper.hasAdapters, false);
    });

    test('registerAdapter adds adapter', () {
      MediationHelper.registerAdapter(
        name: 'TestNetwork',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );
      expect(MediationHelper.hasAdapters, true);
      expect(MediationHelper.registeredAdapters, ['TestNetwork']);
    });

    test('unregisterAdapter removes adapter', () {
      MediationHelper.registerAdapter(
        name: 'TestNetwork',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );
      MediationHelper.unregisterAdapter('TestNetwork');
      expect(MediationHelper.hasAdapters, false);
    });

    test('unregisterAll removes all adapters', () {
      MediationHelper.registerAdapter(
        name: 'A',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );
      MediationHelper.registerAdapter(
        name: 'B',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );
      expect(MediationHelper.registeredAdapters.length, 2);
      MediationHelper.unregisterAll();
      expect(MediationHelper.hasAdapters, false);
    });

    test('forwardConsent with no adapters returns empty summary', () async {
      final summary = await MediationHelper.forwardConsent(
        MediationConsentConfig(hasGdprConsent: true, ccpaOptOut: false),
      );
      expect(summary.results, isEmpty);
      expect(summary.allSuccessful, true);
      expect(summary.hasNetworks, false);
    });

    test('forwardConsent forwards to all adapters', () async {
      bool? gdpr1, ccpa1, gdpr2, ccpa2;

      MediationHelper.registerAdapter(
        name: 'Network1',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {
          gdpr1 = gdprConsent;
          ccpa1 = ccpaOptOut;
        },
      );
      MediationHelper.registerAdapter(
        name: 'Network2',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {
          gdpr2 = gdprConsent;
          ccpa2 = ccpaOptOut;
        },
      );

      final summary = await MediationHelper.forwardConsent(
        MediationConsentConfig(
          hasGdprConsent: true,
          ccpaOptOut: false,
          enableLogging: true,
        ),
      );

      expect(gdpr1, true);
      expect(ccpa1, false);
      expect(gdpr2, true);
      expect(ccpa2, false);
      expect(summary.allSuccessful, true);
      expect(summary.successful.length, 2);
    });

    test('forwardConsent captures adapter errors', () async {
      MediationHelper.registerAdapter(
        name: 'FailNetwork',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {
          throw Exception('network error');
        },
      );

      final summary = await MediationHelper.forwardConsent(
        MediationConsentConfig(hasGdprConsent: true, ccpaOptOut: false),
      );

      expect(summary.allSuccessful, false);
      expect(summary.failed.length, 1);
      expect(summary.failed.first.networkName, 'FailNetwork');
      expect(summary.failed.first.error, contains('network error'));
    });

    test('registerUnityWithCallbacks registers Unity', () async {
      bool? gdprValue, ccpaValue;
      MediationHelper.registerUnityWithCallbacks(
        setGDPRConsent: (v) async => gdprValue = v,
        setCCPAConsent: (v) async => ccpaValue = v,
      );

      expect(MediationHelper.registeredAdapters, contains('Unity Ads'));

      await MediationHelper.forwardConsent(
        MediationConsentConfig(hasGdprConsent: true, ccpaOptOut: false),
      );
      expect(gdprValue, true);
      expect(ccpaValue, true); // inverted: !ccpaOptOut
    });

    test('registerApplovinWithCallbacks registers AppLovin', () async {
      bool? consentValue, doNotSellValue;
      MediationHelper.registerApplovinWithCallbacks(
        setHasUserConsent: (v) async => consentValue = v,
        setDoNotSell: (v) async => doNotSellValue = v,
      );

      expect(MediationHelper.registeredAdapters, contains('AppLovin'));

      await MediationHelper.forwardConsent(
        MediationConsentConfig(hasGdprConsent: false, ccpaOptOut: true),
      );
      expect(consentValue, false);
      expect(doNotSellValue, true);
    });

    test('forwardConsent with logging enabled', () async {
      MediationHelper.registerAdapter(
        name: 'LogTest',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );

      final summary = await MediationHelper.forwardConsent(
        MediationConsentConfig(
          hasGdprConsent: true,
          ccpaOptOut: false,
          enableLogging: true,
        ),
      );

      expect(summary.allSuccessful, true);
    });
  });

  group('MediationConsentConfig', () {
    test('constructor sets fields', () {
      final config = MediationConsentConfig(
        hasGdprConsent: true,
        ccpaOptOut: false,
        enableLogging: true,
      );
      expect(config.hasGdprConsent, true);
      expect(config.ccpaOptOut, false);
      expect(config.enableLogging, true);
    });
  });

  group('MediationForwardResult', () {
    test('successful result', () {
      final result = MediationForwardResult(networkName: 'Test', success: true);
      expect(result.networkName, 'Test');
      expect(result.success, true);
      expect(result.error, isNull);
      expect(result.toString(), contains('Test'));
      expect(result.toString(), contains('✓'));
    });

    test('failed result', () {
      final result = MediationForwardResult(
        networkName: 'Test',
        success: false,
        error: 'some error',
      );
      expect(result.success, false);
      expect(result.error, 'some error');
      expect(result.toString(), contains('✗'));
    });
  });

  group('MediationForwardSummary', () {
    test('empty summary', () {
      final summary = MediationForwardSummary(
        results: [],
        timestamp: DateTime.now(),
      );
      expect(summary.allSuccessful, true);
      expect(summary.hasNetworks, false);
      expect(summary.successful, isEmpty);
      expect(summary.failed, isEmpty);
    });

    test('summary with mixed results', () {
      final summary = MediationForwardSummary(
        results: [
          MediationForwardResult(networkName: 'A', success: true),
          MediationForwardResult(
            networkName: 'B',
            success: false,
            error: 'fail',
          ),
        ],
        timestamp: DateTime.now(),
      );
      expect(summary.allSuccessful, false);
      expect(summary.hasNetworks, true);
      expect(summary.successful.length, 1);
      expect(summary.failed.length, 1);
    });

    test('toString with no networks', () {
      final summary = MediationForwardSummary(
        results: [],
        timestamp: DateTime.now(),
      );
      expect(summary.toString(), contains('No networks'));
    });

    test('toString with networks', () {
      final summary = MediationForwardSummary(
        results: [MediationForwardResult(networkName: 'Net', success: true)],
        timestamp: DateTime.now(),
      );
      expect(summary.toString(), contains('Net'));
    });
  });
}
