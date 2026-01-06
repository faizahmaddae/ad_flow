// Copyright 2024 - AdMob Integration Package
// Unit tests for MediationHelper

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  group('MediationHelper', () {
    setUp(() {
      // Reset state before each test
      MediationHelper.reset();
    });

    group('registration', () {
      test('hasAdapters returns false when no adapters registered', () {
        expect(MediationHelper.hasAdapters, false);
        expect(MediationHelper.registeredAdapters, isEmpty);
      });

      test('hasAdapters returns true after registering an adapter', () {
        MediationHelper.registerAdapter(
          name: 'Test Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );

        expect(MediationHelper.hasAdapters, true);
        expect(MediationHelper.registeredAdapters, contains('Test Network'));
      });

      test('can register multiple adapters', () {
        MediationHelper.registerAdapter(
          name: 'Network A',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );
        MediationHelper.registerAdapter(
          name: 'Network B',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );

        expect(MediationHelper.registeredAdapters.length, 2);
        expect(MediationHelper.registeredAdapters, contains('Network A'));
        expect(MediationHelper.registeredAdapters, contains('Network B'));
      });

      test('unregisterAdapter removes specific adapter', () {
        MediationHelper.registerAdapter(
          name: 'Network A',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );
        MediationHelper.registerAdapter(
          name: 'Network B',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );

        MediationHelper.unregisterAdapter('Network A');

        expect(MediationHelper.registeredAdapters.length, 1);
        expect(MediationHelper.registeredAdapters, contains('Network B'));
        expect(MediationHelper.registeredAdapters, isNot(contains('Network A')));
      });

      test('unregisterAll clears all adapters', () {
        MediationHelper.registerAdapter(
          name: 'Network A',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );
        MediationHelper.registerAdapter(
          name: 'Network B',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );

        MediationHelper.unregisterAll();

        expect(MediationHelper.hasAdapters, false);
        expect(MediationHelper.registeredAdapters, isEmpty);
      });
    });

    group('forwardConsent', () {
      test('returns empty summary when no adapters registered', () async {
        final summary = await MediationHelper.forwardConsent(
          MediationConsentConfig.fullConsent(enableLogging: false),
        );

        expect(summary.hasNetworks, false);
        expect(summary.results, isEmpty);
        expect(summary.allSuccessful, true);
      });

      test('forwards consent to registered adapter', () async {
        bool? receivedGdprConsent;
        bool? receivedCcpaOptOut;

        MediationHelper.registerAdapter(
          name: 'Test Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            receivedGdprConsent = gdprConsent;
            receivedCcpaOptOut = ccpaOptOut;
          },
        );

        await MediationHelper.forwardConsent(
          MediationConsentConfig(
            hasGdprConsent: true,
            ccpaOptOut: false,
            enableLogging: false,
          ),
        );

        expect(receivedGdprConsent, true);
        expect(receivedCcpaOptOut, false);
      });

      test('forwards no-consent correctly', () async {
        bool? receivedGdprConsent;
        bool? receivedCcpaOptOut;

        MediationHelper.registerAdapter(
          name: 'Test Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            receivedGdprConsent = gdprConsent;
            receivedCcpaOptOut = ccpaOptOut;
          },
        );

        await MediationHelper.forwardConsent(
          MediationConsentConfig.noConsent(enableLogging: false),
        );

        expect(receivedGdprConsent, false);
        expect(receivedCcpaOptOut, true);
      });

      test('summary shows success for successful forwarding', () async {
        MediationHelper.registerAdapter(
          name: 'Test Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
        );

        final summary = await MediationHelper.forwardConsent(
          MediationConsentConfig.fullConsent(enableLogging: false),
        );

        expect(summary.allSuccessful, true);
        expect(summary.successful.length, 1);
        expect(summary.failed, isEmpty);
        expect(summary.successful.first.networkName, 'Test Network');
      });

      test('summary captures failures', () async {
        MediationHelper.registerAdapter(
          name: 'Failing Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            throw Exception('Test error');
          },
        );

        final summary = await MediationHelper.forwardConsent(
          MediationConsentConfig.fullConsent(enableLogging: false),
        );

        expect(summary.allSuccessful, false);
        expect(summary.failed.length, 1);
        expect(summary.failed.first.networkName, 'Failing Network');
        expect(summary.failed.first.error, contains('Test error'));
      });

      test('forwards to multiple adapters', () async {
        final receivedConsents = <String, bool>{};

        MediationHelper.registerAdapter(
          name: 'Network A',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            receivedConsents['A'] = gdprConsent;
          },
        );
        MediationHelper.registerAdapter(
          name: 'Network B',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            receivedConsents['B'] = gdprConsent;
          },
        );

        await MediationHelper.forwardConsent(
          MediationConsentConfig(
            hasGdprConsent: true,
            enableLogging: false,
          ),
        );

        expect(receivedConsents['A'], true);
        expect(receivedConsents['B'], true);
      });

      test('partial failures do not block other adapters', () async {
        final calledAdapters = <String>[];

        MediationHelper.registerAdapter(
          name: 'Network A',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            calledAdapters.add('A');
          },
        );
        MediationHelper.registerAdapter(
          name: 'Failing Network',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            calledAdapters.add('Failing');
            throw Exception('Error');
          },
        );
        MediationHelper.registerAdapter(
          name: 'Network B',
          forwarder: ({required gdprConsent, required ccpaOptOut}) async {
            calledAdapters.add('B');
          },
        );

        final summary = await MediationHelper.forwardConsent(
          MediationConsentConfig.fullConsent(enableLogging: false),
        );

        // All adapters should be called
        expect(calledAdapters, contains('A'));
        expect(calledAdapters, contains('Failing'));
        expect(calledAdapters, contains('B'));

        // Summary should show 2 successes and 1 failure
        expect(summary.successful.length, 2);
        expect(summary.failed.length, 1);
      });
    });

    group('convenience methods', () {
      test('registerUnityWithCallbacks registers Unity adapter', () {
        MediationHelper.registerUnityWithCallbacks(
          setGDPRConsent: (value) async {},
          setCCPAConsent: (value) async {},
        );

        expect(MediationHelper.registeredAdapters, contains('Unity Ads'));
      });

      test('registerApplovinWithCallbacks registers AppLovin adapter', () {
        MediationHelper.registerApplovinWithCallbacks(
          setHasUserConsent: (value) async {},
          setDoNotSell: (value) async {},
        );

        expect(MediationHelper.registeredAdapters, contains('AppLovin'));
      });

      test('Unity convenience method inverts CCPA correctly', () async {
        bool? ccpaReceived;

        MediationHelper.registerUnityWithCallbacks(
          setGDPRConsent: (_) async {},
          setCCPAConsent: (value) async => ccpaReceived = value,
        );

        // When user opts OUT (ccpaOptOut = true),
        // Unity should receive setCCPAConsent(false)
        await MediationHelper.forwardConsent(
          MediationConsentConfig(
            hasGdprConsent: false,
            ccpaOptOut: true, // User opted out
            enableLogging: false,
          ),
        );

        // Unity's setCCPAConsent: true = consent given, false = no consent
        // So when ccpaOptOut = true, we pass !ccpaOptOut = false
        expect(ccpaReceived, false);
      });
    });

    group('MediationConsentConfig', () {
      test('fullConsent creates config with consent', () {
        final config = MediationConsentConfig.fullConsent();

        expect(config.hasGdprConsent, true);
        expect(config.ccpaOptOut, false);
      });

      test('noConsent creates config without consent', () {
        final config = MediationConsentConfig.noConsent();

        expect(config.hasGdprConsent, false);
        expect(config.ccpaOptOut, true);
      });
    });

    group('MediationForwardResult', () {
      test('toString shows success correctly', () {
        const result = MediationForwardResult(
          networkName: 'Test',
          success: true,
        );

        expect(result.toString(), contains('✓'));
        expect(result.toString(), contains('Test'));
      });

      test('toString shows failure correctly', () {
        const result = MediationForwardResult(
          networkName: 'Test',
          success: false,
          error: 'Some error',
        );

        expect(result.toString(), contains('✗'));
        expect(result.toString(), contains('Some error'));
      });
    });

    group('MediationForwardSummary', () {
      test('toString handles empty results', () {
        final summary = MediationForwardSummary(
          results: [],
          timestamp: DateTime.now(),
        );

        expect(summary.toString(), contains('No networks registered'));
      });

      test('hasNetworks is correct', () {
        final emptySum = MediationForwardSummary(
          results: [],
          timestamp: DateTime.now(),
        );
        expect(emptySum.hasNetworks, false);

        final withNetworks = MediationForwardSummary(
          results: [
            MediationForwardResult(networkName: 'Test', success: true),
          ],
          timestamp: DateTime.now(),
        );
        expect(withNetworks.hasNetworks, true);
      });
    });
  });
}
