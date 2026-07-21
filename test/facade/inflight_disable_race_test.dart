import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `disableAds()` in-flight-load race (5.1.2).
///
/// `recheckGate()` cannot drop inventory while a controller is still
/// `AdLoading` — it has no handle yet. So a `disableAds()` (Remove-Ads
/// purchased) that lands AFTER a load has passed the gate but BEFORE the SDK
/// returns its handle used to end with the late handle published as
/// `AdLoaded` / kept warm, even though ads are now disabled. The fix
/// re-validates the cheap, current permission synchronously, immediately
/// before publishing the freshly-loaded handle, and drops it if ads are no
/// longer enabled.
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot(AdFlowConfig config) async {
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    return ads;
  }

  test('a BANNER load in flight when disableAds() fires is dropped, never '
      'published as AdLoaded, and recovers on enableAds()', () async {
    final ads = await boot(
      const AdFlowConfig(
        banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      ),
    );
    final banner = ads.banner();

    // Hold the SDK load so it is in flight (past the gate) when we disable.
    sdk.loadHold = Completer<void>();
    final loadFuture = banner.load(width: 320);
    await pumpEventQueue(); // drain to the held loadBanner (past the gate)
    expect(banner.state.value, isA<AdLoading>());

    // Remove-Ads is bought while the request is in flight.
    ads.disableAds();

    // The SDK finally returns a handle.
    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await loadFuture; // deterministic: the load resolves here

    expect(
      banner.state.value,
      const AdBlocked(AdBlockReason.adsDisabled),
      reason:
          'a load that completes after Remove-Ads must not publish AdLoaded',
    );
    expect(
      sdk.banners.single.disposed,
      isTrue,
      reason: 'the late handle must be disposed, never installed',
    );
    expect(banner.handle, isNull);
    expect(banner.lastBlockReason, AdBlockReason.adsDisabled);

    // Turning ads back on re-warms inventory (automatic recovery).
    ads.enableAds();
    await pumpEventQueue();
    expect(banner.state.value, isA<AdLoaded>());
    expect(sdk.banners, hasLength(2));

    banner.dispose();
    ads.dispose();
  });

  test('a NATIVE load in flight when disableAds() fires is dropped, never '
      'published as AdLoaded, and recovers on enableAds()', () async {
    final ads = await boot(
      const AdFlowConfig(
        nativeAd: NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'n-a'),
          templateKind: NativeTemplateKind.small,
        ),
      ),
    );
    final native = ads.native();

    sdk.loadHold = Completer<void>();
    final loadFuture = native.load();
    await pumpEventQueue();
    expect(native.state.value, isA<AdLoading>());

    ads.disableAds();

    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await loadFuture;

    expect(native.state.value, const AdBlocked(AdBlockReason.adsDisabled));
    expect(sdk.natives.single.disposed, isTrue);
    expect(native.handle, isNull);
    expect(native.lastBlockReason, AdBlockReason.adsDisabled);

    ads.enableAds();
    await pumpEventQueue();
    expect(native.state.value, isA<AdLoaded>());
    expect(sdk.natives, hasLength(2));

    native.dispose();
    ads.dispose();
  });
}
