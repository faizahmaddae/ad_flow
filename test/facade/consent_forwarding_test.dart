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

  AdFlowConfig cfg({MediationConsentFailurePolicy? policy}) => AdFlowConfig(
    banner: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    mediationConsentPolicy: policy ?? MediationConsentFailurePolicy.failClosed,
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
        // The FIRST forward now runs during startup (forward-before-init), so
        // install the error handler BEFORE initialize to observe its failure.
        final reported = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previousOnError);

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
    test('initialize() returns IMMEDIATELY even with a hung forwarder — the '
        'non-blocking-UI guarantee (whenReady/loads may wait, the first frame '
        'does not)', () {
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
        // A single microtask — no timers elapsed — must be enough for
        // initialize() to resolve: graph construction is synchronous and the
        // whole forward→init pipeline runs in the background. The app can
        // runApp() here regardless of the forwarder.
        async.flushMicrotasks();
        expect(
          ads,
          isNotNull,
          reason:
              'AdFlow.initialize() must return before consent/forward/init — '
              'the app renders its first frame immediately',
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

    test('the app forwardConsent callback is never invoked CONCURRENTLY when a '
        'mutation orphans an in-flight forward and a SECOND slot then loads '
        '(release-gate review: serialized, at most one in flight)', () {
      fakeAsync((async) {
        final hold = Completer<void>();
        var concurrent = 0;
        var maxConcurrent = 0;
        var calls = 0;
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
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
            forwardConsent: () async {
              calls++;
              concurrent++;
              if (concurrent > maxConcurrent) maxConcurrent = concurrent;
              // The first call hangs (a slow partner SDK); later calls fast.
              if (calls == 1) await hold.future;
              concurrent--;
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();

        // Banner triggers forward #1, which hangs; the banner parks joining it.
        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(calls, 1);

        // A consent mutation orphans the in-flight forward, THEN a fresh slot
        // (native) starts its own load and reaches the barrier — this is the
        // path that, unserialized, launches a SECOND concurrent forward.
        unawaited(ads!.consent.showPrivacyOptions());
        async.flushMicrotasks();
        final native = ads!.native();
        unawaited(native.load());
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(
          maxConcurrent,
          1,
          reason:
              'the native load must JOIN the in-flight forward, never launch a '
              'second concurrent invocation of a (possibly non-reentrant) '
              'forwardConsent',
        );

        hold.complete();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(maxConcurrent, 1, reason: 'still serial after recovery');
        banner.dispose();
        native.dispose();
        ads!.dispose();
      });
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
        unawaited(
          banner.load(width: 320),
        ); // triggers forward #1 (hung on gate)
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

  group('forward-before-initialize (release gate: adapters read their flag '
      'DURING MobileAds.initialize)', () {
    test('forwardConsent runs BEFORE the GMA SDK is initialized', () {
      fakeAsync((async) {
        final order = <String>[];
        final forwardGate = Completer<void>();
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () {
              order.add('forward');
              return forwardGate.future;
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        // The forwarder started; the GMA SDK must NOT be initialized yet.
        expect(order, ['forward']);
        expect(
          sdk.initializeCalls,
          0,
          reason:
              'MobileAds.initialize() must not run before forwardConsent — an '
              'init-time partner adapter would come up without its flag',
        );

        forwardGate.complete();
        async.flushMicrotasks();
        expect(
          sdk.initializeCalls,
          1,
          reason: 'init proceeds once forwarding succeeds',
        );
        ads!.dispose();
      });
    });

    test('fail-CLOSED: a failing forwarder does NOT initialize the SDK, and '
        'recovers (init runs) once it succeeds', () {
      fakeAsync((async) {
        var calls = 0;
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (_) {};
        addTearDown(() => FlutterError.onError = previousOnError);

        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () async {
              calls++;
              if (calls == 1) throw StateError('forward failed');
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(
          sdk.initializeCalls,
          0,
          reason: 'fail-closed: no init until the flag is forwarded',
        );

        // Retry re-arms and a blocked load drives a fresh forward that succeeds.
        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(calls, greaterThanOrEqualTo(2));
        expect(sdk.initializeCalls, 1, reason: 'init runs after recovery');
        expect(sdk.loadLog, isNotEmpty);
        banner.dispose();
        ads!.dispose();
      });
    });

    test(
      'fail-OPEN: a failing forwarder still INITIALIZES (explicit unsafe)',
      () {
        fakeAsync((async) {
          final previousOnError = FlutterError.onError;
          FlutterError.onError = (_) {};
          addTearDown(() => FlutterError.onError = previousOnError);

          AdFlow? ads;
          unawaited(
            AdFlow.initialize(
              cfg(policy: MediationConsentFailurePolicy.failOpen),
              sdk: sdk,
              store: InMemoryKeyValueStore(),
              platform: AdPlatform.android,
              forwardConsent: () async => throw StateError('forward failed'),
            ).then((f) => ads = f),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(
            sdk.initializeCalls,
            1,
            reason: 'fail-open initializes even though forwarding failed',
          );
          ads!.dispose();
        });
      },
    );

    test('a non-adopter (no forwardConsent) initializes in parallel with '
        'consent — no ordering delay', () async {
      final ads = await AdFlow.initialize(
        bannerConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady;
      expect(sdk.initializeCalls, 1);
      ads.dispose();
    });
  });

  group('source serialization ACROSS the timeout boundary (release gate: '
      'Future.timeout does not cancel its source)', () {
    test('after a forward attempt TIMES OUT, no second forwarder invocation '
        'overlaps the still-running source', () {
      fakeAsync((async) {
        var concurrent = 0;
        var maxConcurrent = 0;
        var calls = 0;
        final firstDone = Completer<void>();
        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            bannerConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            forwardConsent: () async {
              calls++;
              concurrent++;
              if (concurrent > maxConcurrent) maxConcurrent = concurrent;
              // First invocation runs LONGER than the 15s gate bound, so the
              // load's wait times out while this source is still running.
              if (calls == 1) {
                await firstDone.future;
              }
              concurrent--;
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();

        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        // Past the 15s forward bound AND the retry re-arm (10s) + backoffs:
        // the load's wait times out, retries fire — but the source is still
        // running, so none may start a second forwarder.
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(
          maxConcurrent,
          1,
          reason:
              'Future.timeout does not cancel the source; a retry after the '
              'timeout must NOT invoke forwardConsent again while the first '
              'invocation is still running — else stale partner-SDK side '
              'effects can land out of order',
        );

        firstDone.complete();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(maxConcurrent, 1, reason: 'still serial after the source ends');
        banner.dispose();
        ads!.dispose();
      });
    });

    test('a mutation during a TIMED-OUT-but-still-running forward: the newer '
        'generation forward runs only AFTER the older source completes '
        '(no out-of-order external side effect)', () {
      fakeAsync((async) {
        final applied = <int>[]; // the consent "state" each forward applied
        var current = 1; // the current consent generation value
        final firstDone = Completer<void>();
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
              final snapshot = current; // capture state at call time
              if (calls == 1) {
                await firstDone.future; // runs long, past the gate bound
              }
              applied.add(snapshot); // the external side effect
            },
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();

        final banner = ads!.banner();
        unawaited(banner.load(width: 320)); // forward #1 (state 1), hangs
        async.elapse(const Duration(seconds: 20)); // past the 15s bound
        async.flushMicrotasks();

        // Consent mutates to state 2 while forward #1 is still running.
        current = 2;
        unawaited(ads!.consent.showPrivacyOptions());
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(
          applied,
          isEmpty,
          reason: 'forward #1 has not completed, so nothing applied yet',
        );

        // Forward #1 finally completes (applying stale state 1). A fresh
        // forward for state 2 must run AFTER it — never before.
        firstDone.complete();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(
          applied.last,
          2,
          reason:
              'the LAST external side effect must reflect the newest consent '
              'state — the older source cannot apply after the newer one',
        );
        banner.dispose();
        ads!.dispose();
      });
    });
  });
}
