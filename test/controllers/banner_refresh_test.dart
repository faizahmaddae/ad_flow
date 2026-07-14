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
        reason: 'AdMob already auto-refreshes this ad unit from the console. A '
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
          reason: 'the visible ad must NOT be destroyed before its replacement '
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
        expect(first.disposed, isTrue, reason: 'the old ad is released on swap');
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
          reason: 'a no-fill on refresh (routine on a weak network) must not '
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
          reason: 'AdLoaded == AdLoaded, so the state notifier does NOT fire on '
              'a swap — without this the widget would keep rendering the old, '
              'disposed handle',
        );
        c.dispose();
      });
    });
  });
}
