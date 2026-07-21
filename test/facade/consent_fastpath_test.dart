import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cached-consent startup fast path (ADR-072, Google UMP guidance).
///
/// A returning user whose PREVIOUS session already made `canRequestAds()` true
/// must be able to serve ads immediately once THIS launch's consent-info update
/// has been DISPATCHED — without waiting for that (possibly slow) update and
/// form to finish. The slow flow still runs and publishes its final result;
/// a downgrade later drops stale inventory.
///
/// https://developers.google.com/admob/flutter/privacy
void main() {
  late FakeAdSdk sdk;

  const bannerConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
  );

  setUp(() {
    sdk = FakeAdSdk()..consentStatus = AdConsentStatus.notRequired;
  });
  tearDown(() => sdk.dispose());

  test('a returning user with cached canRequestAds()==true serves while the '
      'consent-info update is still in flight, then no duplicate load', () {
    fakeAsync((async) {
      sdk.canRequestAdsResult = true; // cached consent from a previous session
      sdk.consentUpdateHold = Completer<void>(); // this launch's update: SLOW
      AdFlow? ads;
      unawaited(
        AdFlow.initialize(
          bannerConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ).then((f) => ads = f),
      );
      async.flushMicrotasks();

      // The launch's consent-info update was actually DISPATCHED (recorded),
      // even though it has not completed — required before any serving.
      expect(
        sdk.consentUpdateCalls,
        hasLength(1),
        reason: 'requestConsentInfoUpdate must be invoked this launch',
      );

      final banner = ads!.banner();
      unawaited(banner.load(width: 320));
      async.flushMicrotasks();

      // Fast path: cached consent lets the returning user serve NOW, without
      // waiting out the held update (OLD code parked here until the update
      // completed or the 30s timeout fired).
      expect(
        sdk.bannerSpecs,
        hasLength(1),
        reason:
            'cached-consent returning user serves without waiting for the '
            'slow consent-info update',
      );
      expect(banner.state.value, isA<AdLoaded>());

      // The slow update finally completes — it must not cause a second load.
      sdk.consentUpdateHold!.complete();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(
        sdk.bannerSpecs,
        hasLength(1),
        reason: 'no duplicate load / request storm when the update completes',
      );
      expect(banner.state.value, isA<AdLoaded>());
      banner.dispose();
      ads!.dispose();
    });
  });

  test('cached-true -> final-false DOWNGRADE while the SDK load is in flight: '
      'the late handle is disposed, never published as AdLoaded, and the slot '
      'settles into an honest blocked state (canRequestAds tracks true->false)', () {
    fakeAsync((async) {
      sdk.canRequestAdsResult = true; // cached consent from a previous session
      sdk.consentUpdateHold = Completer<void>(); // this launch's update: SLOW
      sdk.loadHold = Completer<void>(); // hold the SDK ad load in flight
      // When the update finally completes, consent has lapsed / been declined:
      // the flow will conclude canRequestAds() == false.
      sdk.onConsentInfoUpdate = () => sdk.canRequestAdsResult = false;
      AdFlow? ads;
      unawaited(
        AdFlow.initialize(
          bannerConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ).then((f) => ads = f),
      );
      async.flushMicrotasks();

      final banner = ads!.banner();
      unawaited(banner.load(width: 320));
      async.flushMicrotasks();

      // The fast path served on cached consent: the load passed the gate and is
      // now in flight at the held SDK load (bannerSpecs is recorded only AFTER
      // the hold releases), and the live reactive answer reflects the accepted
      // fast path.
      expect(banner.state.value, isA<AdLoading>());
      expect(
        ads!.canRequestAds.value,
        isTrue,
        reason: 'the live reactive answer must reflect the accepted fast path',
      );

      // The slow update completes and DOWNGRADES consent to false.
      sdk.consentUpdateHold!.complete();
      async.flushMicrotasks();
      expect(
        ads!.canRequestAds.value,
        isFalse,
        reason: 'the final flow reconciles the reactive answer to false',
      );

      // The SDK finally returns the handle requested under the (now-stale)
      // cached consent.
      sdk.loadHold!.complete();
      async.flushMicrotasks();

      expect(
        banner.state.value,
        isNot(isA<AdLoaded>()),
        reason:
            'a handle requested under cached consent the flow then DENIED '
            'must never be published as AdLoaded',
      );
      expect(banner.handle, isNull);
      expect(
        sdk.banners.single.disposed,
        isTrue,
        reason: 'the stale handle must be disposed',
      );
      expect(
        banner.state.value,
        const AdBlocked(AdBlockReason.consentNotGranted),
        reason: 'the slot settles into an honest blocked state',
      );
      expect(
        sdk.bannerSpecs,
        hasLength(1),
        reason: 'no duplicate request / retry storm',
      );
      banner.dispose();
      ads!.dispose();
    });
  });

  test('a first-install user with cached canRequestAds()==false does NOT load '
      'early — it waits for the flow to settle', () {
    fakeAsync((async) {
      sdk.canRequestAdsResult = false; // no prior-session consent
      sdk.consentUpdateHold = Completer<void>();
      AdFlow? ads;
      unawaited(
        AdFlow.initialize(
          bannerConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ).then((f) => ads = f),
      );
      async.flushMicrotasks();

      final banner = ads!.banner();
      unawaited(banner.load(width: 320));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(
        sdk.bannerSpecs,
        isEmpty,
        reason:
            'a user with no valid cached consent must stay blocked until '
            'the flow settles — the fast path must not open on cached false',
      );
      expect(banner.state.value, isNot(isA<AdLoaded>()));
      banner.dispose();
      ads!.dispose();
    });
  });

  test('the fast path does NOT bypass the fail-closed forwardConsent barrier: '
      'a mediation-capable load still waits for forwarding', () {
    fakeAsync((async) {
      sdk.canRequestAdsResult = true; // cached consent true
      final forwarded = Completer<void>(); // forwarding held (in flight)
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
      // Past the 15s forward bound: the load must be BLOCKED on forwarding, not
      // served from cached consent.
      async.elapse(const Duration(seconds: 16));
      async.flushMicrotasks();

      expect(
        sdk.bannerSpecs,
        isEmpty,
        reason:
            'cached consent must NOT let a mediation request skip the '
            'fail-closed forwarding barrier',
      );
      expect(banner.lastBlockReason, AdBlockReason.consentNotForwarded);

      // Forwarding completes → the load proceeds.
      forwarded.complete();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(sdk.bannerSpecs, hasLength(1));
      banner.dispose();
      ads!.dispose();
    });
  });
}
