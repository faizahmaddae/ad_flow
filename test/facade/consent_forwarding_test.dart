import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The awaited consent-forwarding barrier (4.1): mediation networks that do
/// not read the IAB TCF string themselves need their per-network privacy
/// signal set BEFORE the first ad request. The fire-and-forget
/// `onConsentChanged` hook cannot guarantee that ordering; `forwardConsent`,
/// supplied at initialize(), does — the first ad LOAD waits for it.
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..consentStatus = AdConsentStatus.notRequired
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  const bannerConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
  );

  test('the first ad load waits for forwardConsent to complete', () {
    fakeAsync((async) {
      final forwarded = Completer<void>();
      AdFlow? ads;
      unawaited(
        AdFlow.initialize(
          bannerConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
          forwardConsent: () => forwarded.future,
        ).then((f) => ads = f),
      );
      async.flushMicrotasks();

      final banner = ads!.banner();
      unawaited(banner.load(width: 320));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(
        sdk.loadLog,
        isEmpty,
        reason:
            'the network must not receive the ad request before its consent '
            'signal has been forwarded',
      );

      // Forwarding finishes — NOW the request may go out.
      forwarded.complete();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(sdk.loadLog, isNotEmpty);
      banner.dispose();
      ads!.dispose();
    });
  });

  test('a hung forwardConsent degrades OPEN after the bound — it never hangs '
      'the ad pipeline', () {
    fakeAsync((async) {
      AdFlow? ads;
      unawaited(
        AdFlow.initialize(
          bannerConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
          forwardConsent: () => Completer<void>().future, // never completes
        ).then((f) => ads = f),
      );
      async.flushMicrotasks();

      final banner = ads!.banner();
      unawaited(banner.load(width: 320));

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(sdk.loadLog, isEmpty); // still within the bound

      async.elapse(const Duration(seconds: 30)); // past the forward timeout
      async.flushMicrotasks();
      expect(
        sdk.loadLog,
        isNotEmpty,
        reason: 'a broken forwarder must degrade open, never freeze loads',
      );
      banner.dispose();
      ads!.dispose();
    });
  });

  test('forwardConsent runs for the INITIAL flow (not lost to a post-init '
      'property assignment like onConsentChanged can be)', () async {
    var forwardCalls = 0;
    final ads = await AdFlow.initialize(
      bannerConfig,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
      forwardConsent: () async => forwardCalls++,
    );
    await ads.whenReady;
    expect(
      forwardCalls,
      1,
      reason:
          'supplied at initialize(), the forwarder cannot miss the first '
          'consent flow',
    );
    ads.dispose();
  });

  test('a throwing forwardConsent is contained (reported) and loads still '
      'proceed', () async {
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    final ads = await AdFlow.initialize(
      bannerConfig,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
      forwardConsent: () async => throw StateError('forward bug'),
    );
    await ads.whenReady;
    final banner = ads.banner();
    await banner.load(width: 320);
    expect(sdk.loadLog, isNotEmpty); // degrade open on a throwing forwarder
    expect(reported, isNotEmpty); // but the failure is visible
    banner.dispose();
    ads.dispose();
  });

  test('no forwardConsent supplied → behaviour is byte-for-byte as before '
      '(no barrier)', () async {
    final ads = await AdFlow.initialize(
      bannerConfig,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    final banner = ads.banner();
    await banner.load(width: 320);
    expect(sdk.loadLog, isNotEmpty);
    banner.dispose();
    ads.dispose();
  });

  group('deferMediationInit failure is reported, not swallowed (4.1)', () {
    test(
      'a throwing disableMediationInitialization surfaces + init proceeds',
      () async {
        final reported = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previousOnError);

        sdk.disableMediationInitializationError = StateError('defer failed');
        final ads = await AdFlow.initialize(
          const AdFlowConfig(
            banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
            deferMediationInit: true,
          ),
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        );
        await ads.whenReady;
        expect(
          reported,
          isNotEmpty,
          reason:
              'a lost mediation-deferral ordering guarantee must be visible, '
              'matching the request-config no-silent-loss contract',
        );
        expect(sdk.initializeCalls, greaterThan(0)); // init still proceeded
        ads.dispose();
      },
    );
  });
}
