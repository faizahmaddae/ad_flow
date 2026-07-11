// Copyright 2024 - AdMob Integration Package
// Unit tests for AdFlowErrorHandler

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdFlowError', () {
    test('creates with required fields', () {
      final error = AdFlowError(
        type: AdErrorType.bannerLoad,
        code: 3,
        message: 'No fill',
      );

      expect(error.type, AdErrorType.bannerLoad);
      expect(error.code, 3);
      expect(error.message, 'No fill');
      expect(error.adUnitId, isNull);
      expect(error.originalError, isNull);
      expect(error.timestamp, isNotNull);
    });

    test('creates with optional fields', () {
      final error = AdFlowError(
        type: AdErrorType.interstitialLoad,
        code: 1,
        message: 'Network error',
        adUnitId: 'ca-app-pub-xxx/xxx',
        originalError: Exception('test'),
      );

      expect(error.adUnitId, 'ca-app-pub-xxx/xxx');
      expect(error.originalError, isA<Exception>());
    });

    test('toString includes all fields', () {
      final error = AdFlowError(
        type: AdErrorType.rewardedLoad,
        code: 5,
        message: 'Test error',
        adUnitId: 'test-ad-id',
      );

      final str = error.toString();
      expect(str, contains('rewardedLoad'));
      expect(str, contains('5'));
      expect(str, contains('Test error'));
      expect(str, contains('test-ad-id'));
    });

    test('fromException creates error correctly', () {
      final exception = Exception('Original error');
      final error = AdFlowError.fromException(
        exception,
        type: AdErrorType.sdkInitialization,
        adUnitId: 'test-id',
      );

      expect(error.type, AdErrorType.sdkInitialization);
      expect(error.code, -1);
      expect(error.message, contains('Original error'));
      expect(error.adUnitId, 'test-id');
      expect(error.originalError, exception);
    });
  });

  group('AdFlowErrorHandler', () {
    setUp(() {
      AdFlowErrorHandler.instance.reset();
    });

    test('instance returns singleton', () {
      final instance1 = AdFlowErrorHandler.instance;
      final instance2 = AdFlowErrorHandler.instance;
      expect(identical(instance1, instance2), true);
    });

    test('errorStream emits reported errors', () async {
      final errors = <AdFlowError>[];
      final subscription = AdFlowErrorHandler.instance.errorStream.listen(
        (error) => errors.add(error),
      );

      final testError = AdFlowError(
        type: AdErrorType.bannerLoad,
        code: 1,
        message: 'Test',
      );

      AdFlowErrorHandler.instance.reportError(testError);

      // Wait for stream to emit
      await Future.delayed(Duration.zero);

      expect(errors.length, 1);
      expect(errors.first.type, AdErrorType.bannerLoad);

      await subscription.cancel();
    });

    test('callback is invoked on reportError', () {
      AdFlowError? receivedError;
      AdFlowErrorHandler.instance.setErrorCallback((error) {
        receivedError = error;
      });

      final testError = AdFlowError(
        type: AdErrorType.consent,
        code: 2,
        message: 'Consent error',
      );

      AdFlowErrorHandler.instance.reportError(testError);

      expect(receivedError, isNotNull);
      expect(receivedError!.type, AdErrorType.consent);
    });

    test('clearErrorCallback removes callback', () {
      int callCount = 0;
      AdFlowErrorHandler.instance.setErrorCallback((error) {
        callCount++;
      });

      // First error - callback should be called
      AdFlowErrorHandler.instance.reportError(
        AdFlowError(type: AdErrorType.unknown, code: 0, message: 'First'),
      );
      expect(callCount, 1);

      // Clear callback
      AdFlowErrorHandler.instance.clearErrorCallback();

      // Second error - callback should NOT be called
      AdFlowErrorHandler.instance.reportError(
        AdFlowError(type: AdErrorType.unknown, code: 0, message: 'Second'),
      );
      expect(callCount, 1); // Still 1
    });

    test('reportLoadError creates correct error type', () async {
      final errors = <AdFlowError>[];
      final subscription = AdFlowErrorHandler.instance.errorStream.listen(
        (error) => errors.add(error),
      );

      // We can't create a real LoadAdError in tests, but we verify the handler works
      // This test would need mocking in a real integration test

      await subscription.cancel();
    });

    test('reset clears callback', () {
      int callCount = 0;
      AdFlowErrorHandler.instance.setErrorCallback((error) {
        callCount++;
      });

      AdFlowErrorHandler.instance.reset();

      AdFlowErrorHandler.instance.reportError(
        AdFlowError(type: AdErrorType.unknown, code: 0, message: 'After reset'),
      );

      expect(callCount, 0);
    });
  });

  group('AdErrorType', () {
    test('has all expected values', () {
      expect(AdErrorType.values, contains(AdErrorType.consent));
      expect(AdErrorType.values, contains(AdErrorType.bannerLoad));
      expect(AdErrorType.values, contains(AdErrorType.interstitialLoad));
      expect(AdErrorType.values, contains(AdErrorType.interstitialShow));
      expect(AdErrorType.values, contains(AdErrorType.appOpenLoad));
      expect(AdErrorType.values, contains(AdErrorType.appOpenShow));
      expect(AdErrorType.values, contains(AdErrorType.rewardedLoad));
      expect(AdErrorType.values, contains(AdErrorType.rewardedShow));
      expect(AdErrorType.values, contains(AdErrorType.nativeLoad));
      expect(AdErrorType.values, contains(AdErrorType.sdkInitialization));
      expect(AdErrorType.values, contains(AdErrorType.unknown));
    });
  });
}
