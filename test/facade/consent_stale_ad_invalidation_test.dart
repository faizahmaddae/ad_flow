import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// After a consent / privacy-options mutation, an ad ALREADY loaded under the
/// previous consent is privacy-stale: showing/rendering it makes no new ad
/// request, but its impression and measurement still reflect the old choice.
/// So warm (not-yet-shown) full-screen ads and visible banner/native ads are
/// dropped and reloaded under the fresh gate; a full-screen ad already ON
/// SCREEN is not interrupted (release gate).
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..consentStatus = AdConsentStatus.notRequired
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot(AdFlowConfig config) => AdFlow.initialize(
    config,
    sdk: sdk,
    store: InMemoryKeyValueStore(),
    platform: AdPlatform.android,
    rewardedIntroPresenter: (_) async => true,
  );

  test('a WARM (not-yet-shown) interstitial loaded under old consent is '
      'DROPPED and reloaded after a privacy-options change', () async {
    final ads = await boot(
      const AdFlowConfig(
        interstitial: InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'i-a'),
        ),
      ),
    );
    await ads.whenReady;
    await ads.interstitial.load();
    await pumpEventQueue();
    final stale = sdk.interstitials.single;
    expect(ads.interstitial.state.value, isA<AdLoaded>());

    // The user changes consent in the privacy-options form.
    await ads.consent.showPrivacyOptions();
    await pumpEventQueue();

    expect(
      stale.disposed,
      isTrue,
      reason:
          'the warm ad was requested under the previous consent — it must not '
          'remain showable and fire a stale-consent impression',
    );
    expect(
      sdk.interstitials.length,
      greaterThan(1),
      reason: 'a fresh ad is reloaded under the new consent',
    );
    ads.dispose();
  });

  test('a SHOWING interstitial is NOT interrupted by a consent change — its '
      'impression already fired', () async {
    final ads = await boot(
      const AdFlowConfig(
        interstitial: InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'i-a'),
        ),
      ),
    );
    await ads.whenReady;
    await ads.interstitial.load();
    await pumpEventQueue();
    final showing = sdk.interstitials.single;
    await ads.interstitial.show();
    showing.simulateShowed();
    expect(ads.interstitial.state.value, isA<AdShowing>());

    await ads.consent.showPrivacyOptions();
    await pumpEventQueue();

    expect(
      showing.disposed,
      isFalse,
      reason: 'an ad on screen must not be torn out from under the user',
    );
    expect(ads.interstitial.state.value, isA<AdShowing>());
    ads.dispose();
  });

  test('a visible banner loaded under old consent is dropped and re-requested '
      'after a consent change', () async {
    final ads = await boot(
      const AdFlowConfig(
        banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      ),
    );
    await ads.whenReady;
    final banner = ads.banner();
    await banner.load(width: 320);
    await pumpEventQueue();
    final stale = sdk.banners.single;
    expect(banner.state.value, isA<AdLoaded>());

    await ads.consent.showPrivacyOptions();
    await pumpEventQueue();

    expect(
      stale.disposed,
      isTrue,
      reason:
          'the visible banner renders/measures under the old consent — drop '
          'and re-request under the fresh one',
    );
    expect(sdk.banners.length, greaterThan(1));
    banner.dispose();
    ads.dispose();
  });

  test('a visible native ad loaded under old consent is dropped and '
      're-requested after a consent change', () async {
    final ads = await boot(
      const AdFlowConfig(
        nativeAd: NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'n-a'),
          templateKind: NativeTemplateKind.small,
        ),
      ),
    );
    await ads.whenReady;
    final native = ads.native();
    await native.load();
    await pumpEventQueue();
    final stale = sdk.natives.single;
    expect(native.state.value, isA<AdLoaded>());

    await ads.consent.showPrivacyOptions();
    await pumpEventQueue();

    expect(stale.disposed, isTrue);
    expect(sdk.natives.length, greaterThan(1));
    native.dispose();
    ads.dispose();
  });

  // The MID-LOAD window (release gate #2): a consent mutation lands AFTER a
  // load passed its gate (state AdLoading) but BEFORE its SDK callback. The
  // in-flight load stamps its consent generation and drops-and-reloads itself
  // on completion if the generation advanced, so it never installs a
  // stale-consent ad. Tested at the controller level for precision.
  group('mid-load consent mutation (AdLoading window)', () {
    late FullScreenAdCoordinator coordinator;
    late StoredFrequencyCapPolicy caps;
    late int generation;

    setUp(() {
      coordinator = FullScreenAdCoordinator();
      caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
      );
      generation = 0;
    });
    tearDown(() => coordinator.dispose());

    AdGate gate() => AdGate(
      canRequestAds: () async => true,
      isEnabled: () => true,
      consentGeneration: () => generation,
    );

    test(
      'interstitial: an ad requested under gen N, mutated to N+1 while '
      'loading, is DROPPED on completion and reloaded — never installed',
      () async {
        final c = InterstitialAdController(
          sdk: sdk,
          gate: gate(),
          caps: caps,
          coordinator: coordinator,
          config: const InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'i-a'),
          ),
          adUnitId: 'i-a',
        );
        sdk.loadHold = Completer<void>();
        unawaited(c.load());
        await pumpEventQueue(); // parked AdLoading, past the gate
        expect(c.state.value, isA<AdLoading>());

        generation++; // a consent mutation lands mid-load
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        await pumpEventQueue();

        expect(
          sdk.interstitials.first.disposed,
          isTrue,
          reason:
              'the ad requested under the old consent must be dropped unshown, '
              'not installed as AdLoaded and later shown under stale forwarding',
        );
        expect(
          sdk.interstitials.length,
          2,
          reason: 'a fresh ad is reloaded under the new generation',
        );
        c.dispose();
      },
    );

    test(
      'banner: mid-load mutation drops the stale ad on completion',
      () async {
        final c = BannerAdController(
          sdk: sdk,
          gate: gate(),
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'b-a'),
          ),
          adUnitId: 'b-a',
        );
        sdk.loadHold = Completer<void>();
        unawaited(c.load(width: 320));
        await pumpEventQueue();
        expect(c.state.value, isA<AdLoading>());

        generation++;
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        await pumpEventQueue();

        expect(sdk.banners.first.disposed, isTrue);
        expect(sdk.banners.length, 2);
        c.dispose();
      },
    );

    test(
      'native: mid-load mutation drops the stale ad on completion',
      () async {
        final c = NativeAdController(
          sdk: sdk,
          gate: gate(),
          config: const NativeConfig(
            adUnitId: PlatformAdUnitId(android: 'n-a'),
            templateKind: NativeTemplateKind.small,
          ),
          adUnitId: 'n-a',
        );
        sdk.loadHold = Completer<void>();
        unawaited(c.load());
        await pumpEventQueue();
        expect(c.state.value, isA<AdLoading>());

        generation++;
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        await pumpEventQueue();

        expect(sdk.natives.first.disposed, isTrue);
        expect(sdk.natives.length, 2);
        c.dispose();
      },
    );

    test('NO mutation → the ad installs normally (non-vacuity)', () async {
      final c = InterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'i-a'),
        ),
        adUnitId: 'i-a',
      );
      sdk.loadHold = Completer<void>();
      unawaited(c.load());
      await pumpEventQueue();
      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await pumpEventQueue();

      expect(sdk.interstitials.single.disposed, isFalse);
      expect(c.state.value, isA<AdLoaded>());
      c.dispose();
    });
  });
}
