// Copyright 2024 - AdMob Integration Package
// Unit tests for ConsentManager (limited - no platform channel mocking)

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsentManager', () {
    // Note: ConsentManager relies heavily on platform channels (UMP SDK)
    // which cannot be easily mocked in unit tests. These tests cover
    // the testable parts without requiring platform channel mocking.

    group('singleton pattern', () {
      test('instance returns the same object', () {
        final instance1 = ConsentManager.instance;
        final instance2 = ConsentManager.instance;

        expect(identical(instance1, instance2), true);
      });
    });

    group('access via AdFlow', () {
      test('AdFlow.consent returns ConsentManager singleton', () {
        final consent = AdFlow.instance.consent;
        expect(consent, ConsentManager.instance);
      });
    });

    group('initial state (without reset)', () {
      // These tests check the API surface without triggering platform calls
      test('isInitialized is accessible', () {
        // Just verify the getter doesn't throw
        final _ = ConsentManager.instance.isInitialized;
      });

      test('canRequestAds is accessible', () {
        // Just verify the getter doesn't throw
        final _ = ConsentManager.instance.canRequestAds;
      });

      test('isPrivacyOptionsRequired returns a boolean', () {
        final result = ConsentManager.instance.isPrivacyOptionsRequired();
        expect(result, isA<bool>());
      });
    });
  });
}
