import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The consent-forwarding barrier (4.1 release gate). A mediation network that
/// does not read the IAB TCF/GPP string itself needs its per-network privacy
/// signal set BEFORE it fills an ad request. `forwardConsent` is that signal,
/// and the barrier is **fail-closed by default**: a mediation-capable load is
/// BLOCKED (not quietly served) until forwarding succeeds, and the block
/// recovers when a retry succeeds. `MediationConsentFailurePolicy.failOpen` is
/// the explicit, unsafe opt-out. UI is never blocked — only the ad request.
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

  AdFlowConfig cfg({
    MediationConsentFailurePolicy? policy,
    bool deferMediationInit = false,
  }) => AdFlowConfig(
    banner: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    deferMediationInit: deferMediationInit,
    mediationConsentPolicy:
        policy ?? MediationConsentFailurePolicy.failClosed,
  );

  group('the barrier holds the first mediation-capable request', () {
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

        forwarded.complete();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(sdk.loadLog, isNotEmpty);
        banner.dispose();
        ads!.dispose();
      });
    });
  });

  group('FAIL-CLOSED by default: forwarding failure blocks, then recovers', () {
    test('a HUNG forwarder BLOCKS (consentNotForwarded) past the bound — it '
        'must NOT quietly degrade open and send an unsignalled request', () {
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

        // Well past the 15s forward bound AND several retry cycles. The state
        // oscillates AdBlocked → (retry) AdLoading → AdBlocked as the barrier
        // keeps re-attempting the hung forwarder; the DURABLE invariants are
        // that no request ever goes out and the reason is recorded.
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(
          sdk.loadLog,
          isEmpty,
          reason:
              'a broken forwarder must FAIL CLOSED — a mediation partner must '
              'never get a request without its privacy signal',
        );
        expect(
          banner.state.value,
          isNot(isA<AdLoaded>()),
          reason: 'never serving while forwarding is unresolved',
        );
        expect(banner.lastBlockReason, AdBlockReason.consentNotForwarded);
        banner.dispose();
        ads!.dispose();
      });
    });

    test('a forwarder that FAILS then SUCCEEDS: the slot blocks, then recovers '
        'on the retry — visibly and without app intervention', () {
      fakeAsync((async) {
        var calls = 0;
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () async {
              calls++;
              if (calls == 1) throw StateError('transient forward failure');
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();

        final reported = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previousOnError);

        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(sdk.loadLog, isEmpty, reason: 'first forward failed → blocked');
        expect(banner.lastBlockReason, AdBlockReason.consentNotForwarded);
        expect(reported, isNotEmpty, reason: 'the failure is visible');

        // Retry re-arms (10s) and the controller re-checks the gate on its
        // backoff; the second forward succeeds and the slot recovers.
        async.elapse(const Duration(minutes: 3));
        async.flushMicrotasks();
        expect(calls, greaterThanOrEqualTo(2));
        expect(sdk.loadLog, isNotEmpty, reason: 'recovered after forwarding');
        banner.dispose();
        ads!.dispose();
      });
    });
  });

  group('explicit, unmistakably-unsafe fail-open opt-out', () {
    test('failOpen serves even when forwarding fails (reported)', () async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final ads = await AdFlow.initialize(
        cfg(policy: MediationConsentFailurePolicy.failOpen),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        forwardConsent: () async => throw StateError('forward bug'),
      );
      await ads.whenReady;
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(
        sdk.loadLog,
        isNotEmpty,
        reason: 'failOpen is the explicit revenue-first opt-out',
      );
      expect(reported, isNotEmpty, reason: 'still visible even when serving');
      banner.dispose();
      ads.dispose();
    });
  });

  group('non-blocking UI + initial-flow coverage', () {
    test('a hung forwarder does NOT delay whenReady/initialize — only the '
        'ad request is gated', () {
      fakeAsync((async) {
        var ready = false;
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () => Completer<void>().future, // never completes
          ).then((f) {
            ads = f;
            unawaited(f.whenReady.then((_) => ready = true));
          }),
        );
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(
          ready,
          isTrue,
          reason:
              'whenReady resolves on consent alone; forwarding gates loads, '
              'never UI',
        );
        ads!.dispose();
      });
    });

    test('forwardConsent runs for the INITIAL flow (cannot be missed like a '
        'post-init onConsentChanged assignment)', () async {
      var forwardCalls = 0;
      final ads = await AdFlow.initialize(
        bannerConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        forwardConsent: () async => forwardCalls++,
      );
      await ads.whenReady;
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(forwardCalls, 1);
      expect(sdk.loadLog, isNotEmpty);
      banner.dispose();
      ads.dispose();
    });

    test('the forwarder runs ONCE per consent generation — concurrent loads '
        'join one attempt, not N', () async {
      var forwardCalls = 0;
      final ads = await AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
          nativeAd: NativeConfig(
            adUnitId: PlatformAdUnitId(android: 'n-a'),
            templateKind: NativeTemplateKind.small,
          ),
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        forwardConsent: () async => forwardCalls++,
      );
      await ads.whenReady;
      final banner = ads.banner();
      final native = ads.native();
      await Future.wait([banner.load(width: 320), native.load()]);
      expect(forwardCalls, 1);
      banner.dispose();
      native.dispose();
      ads.dispose();
    });

    test('no forwardConsent / no deferral → no barrier at all', () async {
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
  });

  group('consent mutations re-establish the barrier (not only startup)', () {
    test('a privacy-options change re-forwards BEFORE the next newly-permitted '
        'load', () async {
      var forwardCalls = 0;
      final ads = await AdFlow.initialize(
        bannerConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        forwardConsent: () async => forwardCalls++,
      );
      await ads.whenReady;
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(forwardCalls, 1, reason: 'forwarded once for the initial load');

      // The user opens the privacy options and changes consent.
      await ads.consent.showPrivacyOptions();
      // The mutation invalidated the forward; a fresh load must re-forward the
      // NEW state before requesting again.
      await banner.recheckGate();
      await banner.load(width: 320);
      expect(
        forwardCalls,
        greaterThanOrEqualTo(2),
        reason:
            'a consent change must re-forward before the next request — the '
            'barrier is per-mutation, not once-at-startup',
      );
      banner.dispose();
      ads.dispose();
    });

    test('a mutation DURING an in-flight forward does not let the stale forward '
        'mark the new generation as forwarded (latest-value-wins)', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        var calls = 0;
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () {
              calls++;
              return calls == 1 ? gate.future : Future<void>.value();
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();

        final banner = ads!.banner();
        unawaited(banner.load(width: 320)); // triggers forward #1 (hung on gate)
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(sdk.loadLog, isEmpty);

        // Consent mutates while forward #1 is still in flight, then #1 resolves
        // — for the OLD generation. It must NOT open the barrier for the new
        // generation.
        unawaited(ads!.consent.showPrivacyOptions());
        async.flushMicrotasks();
        gate.complete(); // stale forward #1 resolves now
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        // A load after the mutation must wait for a FRESH forward (#2+), not
        // ride on the stale #1.
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(
          calls,
          greaterThanOrEqualTo(2),
          reason: 'the new generation forced a fresh forward',
        );
        expect(sdk.loadLog, isNotEmpty, reason: 'recovered via the fresh one');
        banner.dispose();
        ads!.dispose();
      });
    });
  });

  group('deferMediationInit failure is fail-closed by default (4.1)', () {
    test('a persistently failing deferral BLOCKS mediation-capable loads and '
        'is retried before init', () async {
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      sdk.disableMediationInitializationError = StateError('defer failed');
      final ads = await AdFlow.initialize(
        cfg(deferMediationInit: true),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady;

      expect(
        sdk.disableMediationInitializationCalls,
        3,
        reason: 'the deferral is retried before giving up (non-vacuity)',
      );
      expect(reported, isNotEmpty, reason: 'the lost ordering is visible');
      expect(sdk.initializeCalls, greaterThan(0), reason: 'init still ran');

      final banner = ads.banner();
      await banner.load(width: 320);
      expect(
        sdk.loadLog,
        isEmpty,
        reason:
            'the requested pre-init ordering was lost and could not be '
            'restored — fail-closed refuses the mediation-capable request',
      );
      expect(banner.lastBlockReason, AdBlockReason.consentNotForwarded);
      banner.dispose();
      ads.dispose();
    });

    test('failOpen serves despite a failed deferral (explicit)', () async {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previousOnError);

      sdk.disableMediationInitializationError = StateError('defer failed');
      final ads = await AdFlow.initialize(
        cfg(
          policy: MediationConsentFailurePolicy.failOpen,
          deferMediationInit: true,
        ),
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

    test('a SUCCESSFUL deferral imposes no barrier when no forwarder is set',
        () async {
      final ads = await AdFlow.initialize(
        cfg(deferMediationInit: true),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady;
      expect(sdk.disableMediationInitializationCalls, 1);
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.loadLog, isNotEmpty);
      banner.dispose();
      ads.dispose();
    });
  });
}
