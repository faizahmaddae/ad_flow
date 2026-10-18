import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Far above the 121 blocked loads that two minutes at the one-second floor
/// make.
const _spinCeiling = 300;

/// `AdFlowConfig.validate()` rejects a zero `RetryConfig.baseDelay`, but not a
/// sub-millisecond one: both durations below are positive, and `maxDelay` is
/// not shorter than `baseDelay`. `RetryPolicy` reads them in whole
/// milliseconds, so every delay was 0 ms, and a banner under Remove-Ads
/// re-checked the gate on a zero-delay timer from its first re-check on: a
/// busy loop, with an `onAdBlocked` per spin (ADR-076). Like
/// `closed_gate_recheck_test.dart`, the test counts `onAdBlocked` and, at
/// [_spinCeiling], enables ads, so a spin fails the test instead of hanging it.
void main() {
  test('a sub-millisecond RetryConfig passes validation, and a banner under '
      'Remove-Ads is still re-checked at most once a second', () {
    fakeAsync((async) {
      final sdk = FakeAdSdk()
        ..enforceConsentGate = true
        ..canRequestAdsResult = true;
      late AdFlow ads;
      // ignore: discarded_futures
      AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
          retry: RetryConfig(
            baseDelay: Duration(microseconds: 500),
            maxDelay: Duration(microseconds: 500),
          ),
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      ).then((f) => ads = f);
      async.flushMicrotasks();
      var ready = false;
      // ignore: discarded_futures
      ads.whenReady.then((_) => ready = true);
      async.elapse(const Duration(seconds: 1));
      expect(ready, isTrue);

      var blocked = 0;
      ads.onAdBlocked = (slot, reason) {
        blocked++;
        // The re-check is spinning: end it with a load, and let the counts
        // below fail.
        if (blocked >= _spinCeiling) ads.enableAds();
      };
      ads.disableAds(); // Remove-Ads bought
      final banner = ads.banner();
      // ignore: discarded_futures
      banner.load(width: 320);
      async.flushMicrotasks();
      expect(blocked, 1);
      expect(banner.state.value, const AdBlocked(AdBlockReason.adsDisabled));

      final perMinute = <int>[];
      for (var minute = 0; minute < 2; minute++) {
        final before = blocked;
        async.elapse(const Duration(minutes: 1));
        perMinute.add(blocked - before);
      }
      expect(perMinute, [60, 60]);
      expect(banner.state.value, const AdBlocked(AdBlockReason.adsDisabled));
      expect(sdk.banners, isEmpty);

      ads.enableAds(); // re-warms at once, no re-check wait
      async.flushMicrotasks();
      expect(banner.state.value, const AdLoaded());
      expect(sdk.banners, hasLength(1));

      banner.dispose();
      ads.dispose();
      async.elapse(const Duration(minutes: 1));
    });
  });
}
