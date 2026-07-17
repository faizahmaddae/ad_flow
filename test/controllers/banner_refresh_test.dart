import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// How the CLIENT-SIDE banner refresh behaves (ADR-041).
///
/// AdMob refreshes banners server-side from the console (on by default). A
/// client-side timer on top of that is a second, unsynchronised refresh loop:
/// up to 2x the ad requests for the same placement. So it is now OFF by
/// default, and when a publisher does opt in, it must not blank the slot.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  BannerAdController controller({BannerConfig? config}) => BannerAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: sdk.canRequestAds,
      isEnabled: () => true,
      caps: StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
      ),
      coordinator: coordinator,
    ),
    config:
        config ??
        const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
    adUnitId: 'unit-b',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
  );

  test('DEFAULT: no client-side refresh timer runs at all', () {
    fakeAsync((async) {
      final c = controller(); // default config — minRefresh not set
      c.load(width: 320);
      async.flushMicrotasks();
      expect(sdk.banners, hasLength(1));

      async.elapse(const Duration(hours: 1));

      expect(
        sdk.banners,
        hasLength(1),
        reason:
            'AdMob already auto-refreshes this ad unit from the console. A '
            'client timer on top is a second, unsynchronised refresh loop — up '
            'to 2x the requests for one placement.',
      );
      c.dispose();
    });
  });

  test('OPT-IN: a configured minRefresh still refreshes', () {
    fakeAsync((async) {
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          minRefresh: Duration(seconds: 60),
        ),
      );
      c.load(width: 320);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 60));
      expect(sdk.banners, hasLength(2));
      c.dispose();
    });
  });

  group('a refresh never blanks the slot (ADR-041)', () {
    BannerAdController refreshing() => controller(
      config: const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
        minRefresh: Duration(seconds: 60),
      ),
    );

    test('the CURRENT ad stays live and visible until the next one loads', () {
      fakeAsync((async) {
        final c = refreshing();
        c.load(width: 320);
        async.flushMicrotasks();
        final first = sdk.banners.single;

        // Hold the next load in flight: this is the window the user was
        // staring at a blank slot for, on every refresh cycle — and on a weak
        // network that window is seconds long.
        sdk.loadHold = Completer<void>();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(
          first.disposed,
          isFalse,
          reason:
              'the visible ad must NOT be destroyed before its replacement '
              'has actually loaded',
        );
        expect(
          c.handle,
          same(first),
          reason: 'the widget must keep rendering the current ad meanwhile',
        );
        expect(c.state.value, const AdLoaded());

        // The replacement lands: NOW swap.
        sdk.loadHold!.complete();
        async.flushMicrotasks();

        expect(sdk.banners, hasLength(2));
        expect(c.handle, same(sdk.banners.last));
        expect(
          first.disposed,
          isTrue,
          reason: 'the old ad is released on swap',
        );
        expect(c.state.value, const AdLoaded());
        c.dispose();
      });
    });

    test('a FAILED refresh keeps the current ad on screen', () {
      fakeAsync((async) {
        final c = refreshing();
        c.load(width: 320);
        async.flushMicrotasks();
        final first = sdk.banners.single;

        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(
          first.disposed,
          isFalse,
          reason:
              'a no-fill on refresh (routine on a weak network) must not '
              'take the perfectly good ad already on screen down with it',
        );
        expect(c.handle, same(first));
        expect(
          c.state.value,
          const AdLoaded(),
          reason: 'the slot is still showing a loaded ad, so it is AdLoaded',
        );

        // It retries later, and recovers when fill returns.
        sdk.alwaysLoadError = null;
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(sdk.banners.length, greaterThan(1));
        expect(first.disposed, isTrue);
        c.dispose();
      });
    });

    test('the revision counter bumps on swap so the widget rebuilds', () {
      fakeAsync((async) {
        final c = refreshing();
        c.load(width: 320);
        async.flushMicrotasks();
        final before = c.revision.value;

        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(
          c.revision.value,
          greaterThan(before),
          reason:
              'AdLoaded == AdLoaded, so the state notifier does NOT fire on '
              'a swap — without this the widget would keep rendering the old, '
              'disposed handle',
        );
        c.dispose();
      });
    });
  });

  group('refresh/resize interleaving (2026-07 audit)', () {
    BannerAdController refreshing() => controller(
      config: const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
        minRefresh: Duration(seconds: 60),
      ),
    );

    /// Every fake banner the SDK ever produced must either be the one the
    /// controller currently holds, or be disposed — anything else is a leaked
    /// live `BannerAd` (a native ad view the plugin requires disposing).
    void expectNoLeaks(BannerAdController c) {
      final live = sdk.banners.where((b) => !b.disposed).toList();
      expect(
        live,
        c.handle == null ? isEmpty : [same(c.handle)],
        reason:
            'every non-current banner handle must be disposed — a live '
            'orphan is a leaked native ad view',
      );
    }

    test(
      'resize() during an in-flight refresh leaks nothing and ends at the '
      'new width',
      () {
        fakeAsync((async) {
          final c = refreshing();
          c.load(width: 320);
          async.flushMicrotasks();

          // Park the refresh mid-flight, then rotate.
          sdk.loadHold = Completer<void>();
          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();
          c.resize(800);
          async.flushMicrotasks();

          // Everything lands.
          sdk.loadHold!.complete();
          sdk.loadHold = null;
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 2));
          async.flushMicrotasks();

          expect(c.state.value, const AdLoaded());
          expect(
            c.loadedWidth,
            800,
            reason: 'the rotation must not be silently dropped',
          );
          expect(
            (sdk.bannerSpecs.last.size as AnchoredAdaptiveSizeSpec).width,
            800,
            reason: 'the last SDK request must be for the new width',
          );
          expectNoLeaks(c);
          c.dispose();
          expect(sdk.banners.every((b) => b.disposed), isTrue);
        });
      },
    );

    test(
      'a stale refresh completion must not destroy a fresher right-width ad',
      () {
        fakeAsync((async) {
          final c = refreshing();
          c.load(width: 320);
          async.flushMicrotasks();

          // Park the refresh mid-flight...
          final refreshHold = Completer<void>();
          sdk.loadHold = refreshHold;
          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();
          // ...but let anything requested AFTER this point complete at once,
          // so if a resize starts a concurrent load it lands FIRST and the
          // stale refresh continuation runs LAST.
          sdk.loadHold = null;
          c.resize(800);
          async.flushMicrotasks();

          // The stale (320px) refresh finally lands, LAST. On the old code
          // this ordering let a resize-driven load land first with a correct
          // 800px ad, which the stale continuation then destroyed and
          // replaced with the 320px one — letterboxed in the slot for a full
          // refresh interval. Whichever mechanism prevents that (resize
          // deferral + continuation re-validation), the settled outcome must
          // be: current ad at the NEW width, nothing leaked. Assert with NO
          // elapse — a later refresh cycle would mask the damage.
          refreshHold.complete();
          async.flushMicrotasks();

          expect(c.state.value, const AdLoaded());
          expect(c.loadedWidth, 800);
          expect(
            (sdk.bannerSpecs.last.size as AnchoredAdaptiveSizeSpec).width,
            800,
          );
          expectNoLeaks(c);
          c.dispose();
        });
      },
    );

    test('rotate while the FIRST load is in flight reconciles to the new '
        'width without a leak (regression guard)', () {
      fakeAsync((async) {
        final c = refreshing();
        sdk.loadHold = Completer<void>();
        c.load(width: 320);
        async.flushMicrotasks();
        c.resize(800);
        async.flushMicrotasks();

        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.flushMicrotasks();

        expect(c.state.value, const AdLoaded());
        expect(c.loadedWidth, 800);
        expect(
          (sdk.bannerSpecs.last.size as AnchoredAdaptiveSizeSpec).width,
          800,
        );
        expectNoLeaks(c);
        c.dispose();
      });
    });

    test('dispose() during an in-flight refresh leaks nothing', () {
      fakeAsync((async) {
        final c = refreshing();
        c.load(width: 320);
        async.flushMicrotasks();

        sdk.loadHold = Completer<void>();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        c.dispose();
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.flushMicrotasks();

        expect(
          sdk.banners.every((b) => b.disposed),
          isTrue,
          reason: 'a replacement that lands after dispose must be released',
        );
      });
    });
  });
}
