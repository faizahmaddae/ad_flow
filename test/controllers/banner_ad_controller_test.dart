import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late bool consented;
  late bool enabled;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
    enabled = true;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() => AdGate(
    canRequestAds: () async => consented && sdk.canRequestAdsResult,
    isEnabled: () => enabled,
    caps: StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
    ),
    coordinator: coordinator,
  );

  BannerAdController controller({
    BannerConfig? config,
    RetryConfig retryConfig = const RetryConfig(),
    void Function(AdPaidEvent)? onPaid,
  }) => BannerAdController(
    sdk: sdk,
    gate: gate(),
    config:
        config ??
        const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
    adUnitId: 'unit-b',
    retry: RetryPolicy(retryConfig, random: () => 0.5),
    onPaid: onPaid,
  );

  group('gating (invariant 1)', () {
    test('never loads while consent is closed', () async {
      consented = false;
      sdk.canRequestAdsResult = false;
      final c = controller();
      await c.load(width: 320);
      expect(c.state.value, const AdIdle());
      expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
      c.dispose();
    });

    test('never loads while ads are disabled', () async {
      enabled = false;
      final c = controller();
      await c.load(width: 320);
      expect(sdk.loadLog, isEmpty);
      c.dispose();
    });
  });

  group('loading', () {
    test('walks idle → loading → loaded and exposes the handle', () async {
      final c = controller();
      final states = <AdLoadState>[];
      c.state.addListener(() => states.add(c.state.value));

      await c.load(width: 360);

      expect(states, [const AdLoading(), const AdLoaded()]);
      expect(c.handle, same(sdk.banners.single));
      expect(
        sdk.bannerSpecs.single.size,
        isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 360),
      );
      c.dispose();
    });

    test('double load is a no-op while loading or loaded', () async {
      final c = controller();
      await c.load(width: 320);
      await c.load(width: 320);
      expect(sdk.banners, hasLength(1));
      c.dispose();
    });

    test('adaptive kind without a width fails with invalidConfig', () async {
      final c = controller();
      await c.load();
      expect(
        c.state.value,
        isA<AdFailed>().having(
          (s) => s.error.kind,
          'kind',
          AdFlowErrorKind.invalidConfig,
        ),
      );
      expect(sdk.loadLog, isEmpty);
      c.dispose();
    });

    test(
      'fixed kind loads without a width and passes the right spec',
      () async {
        final c = controller(
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
            kind: BannerKind.fixed,
            fixedSize: FixedBannerSize.mediumRectangle,
          ),
        );
        await c.load();
        expect(c.state.value, const AdLoaded());
        expect(
          sdk.bannerSpecs.single.size,
          isA<FixedSizeSpec>().having(
            (s) => s.size,
            'size',
            FixedBannerSize.mediumRectangle,
          ),
        );
        c.dispose();
      },
    );

    test('collapsible placement flows into the load spec', () async {
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          collapsible: CollapsiblePlacement.bottom,
        ),
      );
      await c.load(width: 320);
      expect(sdk.bannerSpecs.single.collapsible, CollapsiblePlacement.bottom);
      c.dispose();
    });

    test('forwards paid events', () async {
      final paid = <AdPaidEvent>[];
      final c = controller(onPaid: paid.add);
      await c.load(width: 320);

      const event = AdPaidEvent(
        adUnitId: 'unit-b',
        valueMicros: 1000,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.precise,
      );
      sdk.banners.single.simulatePaid(event);
      // Tagged with the slot so one onPaidEvent listener can log per-format
      // revenue (2026-07 audit).
      expect(paid, [event.taggedWithSlot(BannerAdController.slot)]);
      c.dispose();
    });
  });

  group('retry and auto re-arm (ADR-008)', () {
    test('retries with exponential backoff until success', () {
      fakeAsync((async) {
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        final c = controller(
          retryConfig: const RetryConfig(
            maxAttempts: 3,
            baseDelay: Duration(seconds: 5),
          ),
        );
        c.load(width: 320);
        async.flushMicrotasks();
        expect(c.state.value, isA<AdFailed>());
        expect(sdk.consentUpdateCalls, isEmpty);

        // First retry after 5s fails again.
        async.elapse(const Duration(seconds: 5));
        expect(c.state.value, isA<AdFailed>());

        // Second retry after 10s succeeds.
        sdk.alwaysLoadError = null;
        async.elapse(const Duration(seconds: 10));
        expect(c.state.value, const AdLoaded());
        expect(sdk.banners, hasLength(1));

        c.dispose();
      });
    });

    test('after the budget, a cooldown auto re-arms the load (v1 fix #8)', () {
      fakeAsync((async) {
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        final c = controller(
          retryConfig: const RetryConfig(
            maxAttempts: 1,
            cooldown: Duration(minutes: 5),
          ),
        );
        c.load(width: 320);
        async.flushMicrotasks();
        expect(c.state.value, isA<AdFailed>());

        // No retry timer — straight to cooldown.
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(c.state.value, isA<AdFailed>());

        sdk.alwaysLoadError = null;
        async.elapse(const Duration(seconds: 1));
        expect(c.state.value, const AdLoaded());

        c.dispose();
      });
    });

    test('a stale retry timer can never stomp a recovered load (review finding '
        '#3)', () {
      fakeAsync((async) {
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        final c = controller(
          retryConfig: const RetryConfig(
            maxAttempts: 1,
            cooldown: Duration(minutes: 5),
          ),
        );

        // Load #1 fails; a cooldown-timer retry is armed for 5 min.
        c.load(width: 320);
        async.flushMicrotasks();
        expect(c.state.value, isA<AdFailed>());

        // A direct load() call succeeds independently of that timer.
        sdk.alwaysLoadError = null;
        c.load(width: 320);
        async.flushMicrotasks();
        expect(c.state.value, const AdLoaded());
        expect(sdk.banners, hasLength(1));

        // The would-be retry-timer deadline passes. It must not stomp the
        // recovered ad back to AdIdle and force a second, unrelated load —
        // its `state is! AdFailed` guard is what stops it. (Since ADR-041 the
        // client-side refresh is off by default, so no refresh timer replaces
        // that stale one either; the guard is now doing the work alone.)
        async.elapse(const Duration(minutes: 5));
        expect(c.state.value, const AdLoaded());
        expect(sdk.banners, hasLength(1));
        expect(sdk.banners.single.disposed, isFalse);

        c.dispose();
      });
    });
  });

  group('refresh', () {
    test('disposes the old handle and reloads after minRefresh, reusing '
        'the width', () {
      fakeAsync((async) {
        final c = controller(
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
            minRefresh: Duration(seconds: 60),
          ),
        );
        c.load(width: 360);
        async.flushMicrotasks();
        final first = sdk.banners.single;

        async.elapse(const Duration(seconds: 60));
        expect(first.disposed, isTrue);
        expect(sdk.banners, hasLength(2));
        expect(c.state.value, const AdLoaded());
        expect(
          sdk.bannerSpecs.last.size,
          isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 360),
        );

        c.dispose();
      });
    });

    test('minRefresh below the 30s floor is clamped', () {
      fakeAsync((async) {
        final c = controller(
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
            minRefresh: Duration(seconds: 1),
          ),
        );
        c.load(width: 320);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 29));
        expect(sdk.banners, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(sdk.banners, hasLength(2));

        c.dispose();
      });
    });
  });

  group('gate-blocked recovery', () {
    test('a load blocked by a closed gate re-checks and recovers once the '
        'gate reopens (does not die forever)', () {
      fakeAsync((async) {
        final c = controller(
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
            minRefresh: Duration(seconds: 60),
          ),
          retryConfig: const RetryConfig(cooldown: Duration(minutes: 5)),
        );
        c.load(width: 320);
        async.flushMicrotasks();
        expect(c.state.value, const AdLoaded());

        // User buys Remove-Ads right as the refresh timer fires.
        enabled = false;
        async.elapse(const Duration(seconds: 60));
        expect(sdk.banners.single.disposed, isTrue);
        expect(c.state.value, const AdIdle());

        // Ads re-enabled before the next gate recheck fires.
        enabled = true;
        // The gate recheck now backs off from RetryConfig.baseDelay (5s) via
        // RetryPolicy.gateRecheckDelay, instead of reusing the 5-minute
        // failure cooldown. A closed gate is a "not yet", not an error: the
        // common case is consent resolving a second or two after the first
        // frame, and making that cost five blank minutes was costing the first
        // (highest-value) session of every new install.
        async.elapse(const Duration(seconds: 10));

        expect(sdk.banners, hasLength(2)); // recovered, not dead forever
        expect(c.state.value, const AdLoaded());
        c.dispose();
      });
    });

    test('concurrent load() calls produce exactly one handle', () async {
      final c = controller();
      final l1 = c.load(width: 320);
      final l2 = c.load(width: 320);
      await Future.wait([l1, l2]);
      await Future<void>.delayed(Duration.zero);

      expect(sdk.banners, hasLength(1));
      expect(sdk.banners.single.disposed, isFalse);
      c.dispose();
    });
  });

  group('dispose', () {
    test('cancels timers, disposes the handle and stops all work', () {
      fakeAsync((async) {
        final c = controller();
        c.load(width: 320);
        async.flushMicrotasks();
        final handle = sdk.banners.single;

        c.dispose();
        expect(handle.disposed, isTrue);

        async.elapse(const Duration(hours: 1));
        expect(sdk.banners, hasLength(1)); // no refresh, no re-arm
      });
    });

    test('disposing before the gate check resolves never hits the SDK', () {
      fakeAsync((async) {
        final c = controller();
        c.load(width: 320);
        c.dispose(); // dispose before the async gate check resolves
        async.flushMicrotasks();

        expect(sdk.banners, isEmpty);
      });
    });

    test('a load completing after dispose discards the handle', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final c = controller();
        c.load(width: 320);
        async.flushMicrotasks(); // past the gate, load in flight
        c.dispose();
        sdk.loadHold!.complete();
        async.flushMicrotasks();

        expect(sdk.banners.single.disposed, isTrue);
        expect(c.handle, isNull);
      });
    });
  });
}
