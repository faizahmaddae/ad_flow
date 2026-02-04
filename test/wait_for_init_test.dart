// Test for non-blocking initialization and waitForInit() functionality
//
// Note: These tests cannot call AdFlow.instance.initialize() directly because
// TestAdUnitIds uses Platform.isAndroid/isIOS which don't work in unit tests.
// Instead, we test the waitForInit() behavior directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdFlow.instance.reset();
    AdFlowErrorHandler.instance.reset();
  });

  group('waitForInit() state checks', () {
    test('throws StateError if initialize() was never called', () async {
      expect(
        () => AdFlow.instance.waitForInit(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('initialize() was never called'),
          ),
        ),
      );
    });

    test('isInitialized is false before init', () {
      expect(AdFlow.instance.isInitialized, isFalse);
    });

    test('isInitialized is false after reset', () async {
      // We can't call initialize(), but we can verify reset clears state
      await AdFlow.instance.reset();
      expect(AdFlow.instance.isInitialized, isFalse);
    });
  });

  group('initStream', () {
    test('is a broadcast stream', () {
      final stream = AdFlow.instance.initStream;
      expect(stream.isBroadcast, isTrue);
    });

    test('can have multiple listeners', () {
      final emissions1 = <bool>[];
      final emissions2 = <bool>[];

      final sub1 = AdFlow.instance.initStream.listen(emissions1.add);
      final sub2 = AdFlow.instance.initStream.listen(emissions2.add);

      // Clean up
      sub1.cancel();
      sub2.cancel();

      // No crash = success
    });
  });

  group('completer behavior', () {
    test('reset clears completer for re-initialization', () async {
      await AdFlow.instance.reset();

      // After reset, waitForInit should throw StateError
      // (completer is null)
      expect(() => AdFlow.instance.waitForInit(), throwsStateError);
    });

    test('multiple resets are safe', () async {
      await AdFlow.instance.reset();
      await AdFlow.instance.reset();
      await AdFlow.instance.reset();

      // No crash = success
      expect(AdFlow.instance.isInitialized, isFalse);
    });
  });
}
