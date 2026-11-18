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

  BannerAdController controller({
    BannerConfig? config,
    void Function(AdPaidEvent)? onPaid,
  }) => BannerAdController(
    sdk: sdk,
    gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
    config:
        config ??
        const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
    adUnitId: 'unit-b',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
    onPaid: onPaid,
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

  group('refresh/resize interleaving (2026-07 audit)', () {
    BannerAdController refreshing() => controller(
      config: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
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
  });
}
