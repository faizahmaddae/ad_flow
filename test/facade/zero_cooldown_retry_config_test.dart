import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Far above the 122 banner loads that two minutes at the one-second floor
/// make.
const _spinCeiling = 300;

/// Counts every banner load request, failed or not, and stops failing them
/// at [_spinCeiling]: the count runs inside the re-arm loop, so a spin ends in
/// a successful load and the test fails instead of hanging.
class _CountingSdk extends FakeAdSdk {
  int bannerLoads = 0;

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) {
    bannerLoads++;
    if (bannerLoads >= _spinCeiling) alwaysLoadError = null;
    return super.loadBanner(spec);
  }
}

/// `AdFlowConfig.validate()` rejects a negative `RetryConfig.cooldown`, not a
/// zero one. With no retries (`maxAttempts: 0`) a banner whose loads kept
/// failing waited only the cooldown between loads: 0 ms, so it re-armed on a
/// zero-delay timer, a busy loop of load requests (ADR-077). The config still
/// validates; the re-arm now waits at least a second.
void main() {
  test('a zero cooldown passes validation, and a banner whose loads keep '
      'failing still loads at most once a second', () {
    fakeAsync((async) {
      final sdk = _CountingSdk()
        ..enforceConsentGate = true
        ..canRequestAdsResult = true;
      late AdFlow ads;
      // ignore: discarded_futures
      AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
          retry: RetryConfig(maxAttempts: 0, cooldown: Duration.zero),
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

      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'no fill',
      );
      final banner = ads.banner();
      // The first load, then each of two minutes.
      final counts = <int>[];
      var before = 0;
      void count() {
        counts.add(sdk.bannerLoads - before);
        before = sdk.bannerLoads;
      }

      // ignore: discarded_futures
      banner.load(width: 320);
      async.elapse(Duration.zero);
      count();
      for (var minute = 0; minute < 2; minute++) {
        async.elapse(const Duration(minutes: 1));
        count();
      }
      expect(counts, [1, 60, 60]);
      expect(banner.state.value, isA<AdFailed>());
      expect(sdk.banners, isEmpty);

      sdk.alwaysLoadError = null; // the network is back
      async.elapse(const Duration(seconds: 1));
      expect(banner.state.value, const AdLoaded());
      expect(sdk.banners, hasLength(1));

      banner.dispose();
      ads.dispose();
      async.elapse(const Duration(minutes: 1));
    });
  });
}
