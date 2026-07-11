// Tests for AdFlowErrorHandler - comprehensive

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  late AdFlowErrorHandler handler;

  setUp(() {
    handler = AdFlowErrorHandler.instance;
    handler.reset();
  });

  tearDown(() {
    handler.reset();
  });

  group('AdFlowErrorHandler', () {
    test('singleton returns same instance', () {
      expect(AdFlowErrorHandler.instance, same(handler));
    });

    test('reportError sends to stream', () async {
      final errors = <AdFlowError>[];
      final sub = handler.errorStream.listen(errors.add);

      handler.reportError(
        AdFlowError(
          type: AdErrorType.bannerLoad,
          message: 'test error',
          code: 1,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(errors.length, 1);
      expect(errors.first.message, 'test error');
      expect(errors.first.type, AdErrorType.bannerLoad);
      expect(errors.first.code, 1);
      await sub.cancel();
    });

    test('reportError calls error callback', () {
      AdFlowError? captured;
      handler.setErrorCallback((e) => captured = e);

      handler.reportError(
        AdFlowError(
          type: AdErrorType.interstitialShow,
          message: 'show error',
          code: 2,
        ),
      );

      expect(captured, isNotNull);
      expect(captured!.message, 'show error');
    });

    test('clearErrorCallback removes callback', () {
      AdFlowError? captured;
      handler.setErrorCallback((e) => captured = e);
      handler.clearErrorCallback();

      handler.reportError(
        AdFlowError(type: AdErrorType.bannerLoad, message: 'test', code: 0),
      );

      expect(captured, isNull);
    });

    test('reportLoadError creates error from LoadAdError', () async {
      final errors = <AdFlowError>[];
      final sub = handler.errorStream.listen(errors.add);

      handler.reportLoadError(
        LoadAdError(1, 'domain', 'load failed', null),
        type: AdErrorType.bannerLoad,
        adUnitId: 'test-unit-id',
      );

      await Future.delayed(Duration.zero);
      expect(errors.length, 1);
      expect(errors.first.type, AdErrorType.bannerLoad);
      expect(errors.first.adUnitId, 'test-unit-id');
      await sub.cancel();
    });

    test('reportException creates error from exception', () async {
      final errors = <AdFlowError>[];
      final sub = handler.errorStream.listen(errors.add);

      handler.reportException(
        Exception('something went wrong'),
        type: AdErrorType.sdkInitialization,
        adUnitId: 'unit-123',
      );

      await Future.delayed(Duration.zero);
      expect(errors.length, 1);
      expect(errors.first.type, AdErrorType.sdkInitialization);
      await sub.cancel();
    });

    test('reportConsentError creates error from FormError', () async {
      final errors = <AdFlowError>[];
      final sub = handler.errorStream.listen(errors.add);

      handler.reportConsentError(
        FormError(errorCode: 1, message: 'consent fail'),
      );

      await Future.delayed(Duration.zero);
      expect(errors.length, 1);
      expect(errors.first.type, AdErrorType.consent);
      await sub.cancel();
    });

    test('dispose closes stream', () {
      handler.dispose();
      expect(handler.errorStream.isBroadcast, true);
    });

    test('reset recreates stream after dispose', () async {
      handler.dispose();
      handler.reset();

      final errors = <AdFlowError>[];
      final sub = handler.errorStream.listen(errors.add);

      handler.reportError(
        AdFlowError(
          type: AdErrorType.bannerLoad,
          message: 'after reset',
          code: 0,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(errors.length, 1);
      await sub.cancel();
    });

    test('multiple stream listeners', () async {
      final errors1 = <AdFlowError>[];
      final errors2 = <AdFlowError>[];
      final sub1 = handler.errorStream.listen(errors1.add);
      final sub2 = handler.errorStream.listen(errors2.add);

      handler.reportError(
        AdFlowError(
          type: AdErrorType.bannerLoad,
          message: 'broadcast',
          code: 0,
        ),
      );

      await Future.delayed(Duration.zero);
      expect(errors1.length, 1);
      expect(errors2.length, 1);
      await sub1.cancel();
      await sub2.cancel();
    });
  });

  group('AdFlowError', () {
    test('constructor sets all fields', () {
      final error = AdFlowError(
        type: AdErrorType.bannerLoad,
        message: 'test',
        code: 42,
        adUnitId: 'unit-id',
      );
      expect(error.type, AdErrorType.bannerLoad);
      expect(error.message, 'test');
      expect(error.code, 42);
      expect(error.adUnitId, 'unit-id');
      expect(error.timestamp, isA<DateTime>());
    });

    test('fromLoadAdError factory', () {
      final loadError = LoadAdError(3, 'domain', 'message', null);
      final error = AdFlowError.fromLoadAdError(
        loadError,
        type: AdErrorType.interstitialLoad,
        adUnitId: 'ad-unit',
      );
      expect(error.type, AdErrorType.interstitialLoad);
      expect(error.code, 3);
      expect(error.adUnitId, 'ad-unit');
      expect(error.originalError, loadError);
    });

    test('fromFormError factory', () {
      final formError = FormError(errorCode: 7, message: 'form fail');
      final error = AdFlowError.fromFormError(formError);
      expect(error.type, AdErrorType.consent);
      expect(error.code, 7);
      expect(error.originalError, formError);
    });

    test('fromException factory', () {
      final exception = Exception('oops');
      final error = AdFlowError.fromException(
        exception,
        type: AdErrorType.sdkInitialization,
      );
      expect(error.type, AdErrorType.sdkInitialization);
      expect(error.code, -1);
      expect(error.originalError, exception);
    });

    test('toString contains type and message', () {
      final error = AdFlowError(
        type: AdErrorType.bannerLoad,
        message: 'test msg',
        code: 1,
      );
      expect(error.toString(), contains('bannerLoad'));
      expect(error.toString(), contains('test msg'));
    });

    test('toString includes adUnitId when present', () {
      final error = AdFlowError(
        type: AdErrorType.bannerLoad,
        message: 'test',
        code: 1,
        adUnitId: 'my-ad-unit',
      );
      expect(error.toString(), contains('my-ad-unit'));
    });

    test('toString omits adUnitId when null', () {
      final error = AdFlowError(
        type: AdErrorType.bannerLoad,
        message: 'test',
        code: 1,
      );
      expect(error.toString(), isNot(contains('adUnitId')));
    });
  });

  group('AdErrorType', () {
    test('all values exist', () {
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
