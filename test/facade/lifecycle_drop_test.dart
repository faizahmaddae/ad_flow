import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live ads must be DROPPED — not merely no-longer-reloaded — when they stop
/// being permitted (2026-07 audit):
///
/// - `disableAds()` (Remove-Ads purchased): with `minRefresh` off by default
///   (ADR-041) a mounted banner had NO loop that ever re-checked the gate, so
///   a paying user kept seeing (and AdMob kept server-side refreshing) the
///   old ad until the app manually hid the widget.
/// - `dispose()` / re-`initialize()` (ADR-044): widget-owned banner/native
///   controllers minted from the OLD graph kept serving ads wired to a dead
///   graph.
/// - consent withdrawal via the privacy-options form: ads loaded under the
///   old consent stayed on screen / warm, and the withdrawal itself was
///   unobservable to the rest of the graph.
void main() {
  late FakeAdSdk sdk;

  const config = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
      cap: FrequencyCap(),
    ),
    nativeAd: NativeConfig(
      adUnitId: PlatformAdUnitId(android: 'n-a'),
      templateKind: NativeTemplateKind.small,
    ),
  );

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot() async {
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    return ads;
  }

  group('disableAds (Remove-Ads)', () {
    test('drops a LIVE banner, not just future loads', () async {
      final ads = await boot();
      final banner = ads.banner();
      await banner.load(width: 320);
      final live = sdk.banners.single;
      expect(banner.state.value, const AdLoaded());

      ads.disableAds();
      await pumpEventQueue();

      expect(
        banner.state.value,
        const AdIdle(),
        reason:
            'a paying Remove-Ads user must not keep seeing (and AdMob must '
            'not keep server-side refreshing) an already-mounted ad',
      );
      expect(live.disposed, isTrue);
      expect(banner.lastBlockReason, AdBlockReason.adsDisabled);
      banner.dispose();
      ads.dispose();
    });

    test('drops WARM full-screen inventory', () async {
      final ads = await boot();
      await pumpEventQueue(); // let the background preloads land
      expect(ads.interstitial.isReady, isTrue);
      final warm = sdk.interstitials.single;

      ads.disableAds();
      await pumpEventQueue();

      expect(ads.interstitial.isReady, isFalse);
      expect(warm.disposed, isTrue);
      ads.dispose();
    });

    test('enableAds() re-loads promptly (no backoff wait)', () async {
      final ads = await boot();
      final banner = ads.banner();
      await banner.load(width: 320);
      ads.disableAds();
      await pumpEventQueue();
      final loadsWhileDisabled = sdk.loadLog.length;

      ads.enableAds();
      await pumpEventQueue();

      expect(
        sdk.loadLog.length,
        greaterThan(loadsWhileDisabled),
        reason:
            'turning ads back on must re-warm inventory at once, not after '
            'a gate-recheck backoff',
      );
      banner.dispose();
      ads.dispose();
    });
  });

  group('dispose / re-initialize', () {
    test(
      'a widget-owned banner minted from a DISPOSED graph stops serving',
      () async {
        final ads = await boot();
        final banner = ads.banner();
        await banner.load(width: 320);
        final live = sdk.banners.single;

        ads.dispose();
        await pumpEventQueue();

        expect(
          banner.state.value,
          const AdIdle(),
          reason: 'the old graph must not keep a live ad on screen',
        );
        expect(live.disposed, isTrue);

        // And it must not load again through the dead graph's gate — with
        // enforceConsentGate on, a stray load would throw in the fake.
        await banner.load(width: 320);
        await pumpEventQueue();
        expect(banner.state.value, const AdIdle());
        expect(sdk.banners, hasLength(1));
        banner.dispose();
      },
    );

    test('re-initialize (ADR-044) stops the previous graph\'s minted '
        'controllers as part of replacing it', () async {
      final ads1 = await boot();
      final oldBanner = ads1.banner();
      await oldBanner.load(width: 320);
      final oldLive = sdk.banners.single;

      final ads2 = await AdFlow.initialize(
        config,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads2.whenReady;
      await pumpEventQueue();

      expect(oldBanner.state.value, const AdIdle());
      expect(oldLive.disposed, isTrue);
      oldBanner.dispose();
      ads2.dispose();
    });
  });

  group('consent withdrawal (privacy options)', () {
    test('withdrawing consent through ads.consent.showPrivacyOptions() drops '
        'live and warm ads', () async {
      final ads = await boot();
      final banner = ads.banner();
      await banner.load(width: 320);
      final liveBanner = sdk.banners.single;
      final warmInterstitial = sdk.interstitials.single;

      // The user opens Manage Consent and withdraws: from here on the SDK
      // reports ads may no longer be requested.
      sdk.onPrivacyOptionsFormShown = () => sdk.canRequestAdsResult = false;
      await ads.consent.showPrivacyOptions();
      await pumpEventQueue();

      expect(
        banner.state.value,
        const AdIdle(),
        reason: 'an ad loaded under withdrawn consent must not stay mounted',
      );
      expect(liveBanner.disposed, isTrue);
      expect(ads.interstitial.isReady, isFalse);
      expect(warmInterstitial.disposed, isTrue);
      banner.dispose();
      ads.dispose();
    });
  });
}
