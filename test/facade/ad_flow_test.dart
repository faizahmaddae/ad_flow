import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;

  const fullConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
      cap: FrequencyCap(),
    ),
    rewarded: RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r-a')),
    rewardedInterstitial: RewardedInterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'ri-a'),
    ),
    nativeAd: NativeConfig(
      adUnitId: PlatformAdUnitId(android: 'n-a'),
      templateKind: NativeTemplateKind.small,
    ),
    appOpen: AppOpenConfig(
      adUnitId: PlatformAdUnitId(android: 'ao-a'),
      cap: FrequencyCap(),
    ),
    testDeviceIds: ['dev-1'],
  );

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot({
    AdFlowConfig config = fullConfig,
    bool consentOpens = true,
  }) {
    if (consentOpens) {
      // EEA-style: the gate opens when the form is dismissed.
      sdk.consentStatus = AdConsentStatus.required;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };
    }
    return AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
      rewardedIntroPresenter: (_) async => true,
    );
  }

  group('initialize', () {
    test('end to end: init ∥ consent → request config → preloads → show → '
        'revenue callback', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero); // let preloads land

      // Init and consent both ran; config pushed after the gate opened.
      expect(sdk.initializeCalls, 1);
      expect(sdk.consentUpdateCalls, hasLength(1));
      expect(sdk.requestConfigs.single.testDeviceIds, ['dev-1']);

      // Every configured full-screen format preloaded exactly once.
      expect(sdk.interstitials, hasLength(1));
      expect(sdk.rewardeds, hasLength(1));
      expect(sdk.rewardedInterstitials, hasLength(1));
      expect(sdk.appOpens, hasLength(1)); // via the app-open manager

      // Show an interstitial and collect revenue.
      final paid = <AdPaidEvent>[];
      ads.onPaidEvent = paid.add;
      expect(await ads.interstitial.show(), isTrue);
      const event = AdPaidEvent(
        adUnitId: 'i-a',
        valueMicros: 5000,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.precise,
      );
      sdk.interstitials.single.simulatePaid(event);
      expect(paid, [event]);

      ads.dispose();
    });

    test('closed consent gate: nothing loads, nothing crashes', () async {
      final ads = await boot(consentOpens: false);
      await Future<void>.delayed(Duration.zero);

      expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
      ads.dispose();
    });

    test('unconfigured slots build no controllers and throw on access',
        () async {
      final ads = await boot(
        config: const AdFlowConfig(
          interstitial: InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'i-a'),
            cap: FrequencyCap(),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sdk.loadLog, ['interstitial:i-a']);
      expect(
        () => ads.rewarded,
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.invalidConfig,
          ),
        ),
      );
      expect(() => ads.appOpen, throwsA(isA<AdFlowError>()));
      ads.dispose();
    });

    test('rewardedInterstitial without a presenter fails fast', () async {
      sdk.canRequestAdsResult = true;
      await expectLater(
        AdFlow.initialize(
          const AdFlowConfig(
            rewardedInterstitial: RewardedInterstitialConfig(
              adUnitId: PlatformAdUnitId(android: 'ri-a'),
            ),
          ),
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ),
        throwsA(isA<AdFlowError>()),
      );
    });

    test('instance points at the latest initialize and clears on dispose',
        () async {
      final ads = await boot();
      expect(AdFlow.instance, same(ads));
      ads.dispose();
      expect(() => AdFlow.instance, throwsStateError);
    });
  });

  group('remove-ads (enable/disableAds)', () {
    test('disableAds blocks loads and shows; enableAds restores', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero);
      final loadsAfterBoot = sdk.loadLog.length;

      ads.disableAds();
      expect(ads.adsEnabled.value, isFalse);
      expect(await ads.interstitial.show(), isFalse);

      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.loadLog.length, loadsAfterBoot); // nothing new loaded
      banner.dispose();

      ads.enableAds();
      expect(await ads.interstitial.show(), isTrue);
      ads.dispose();
    });
  });

  group('banner()/native() factories', () {
    test('mint independent controllers with resolved ids', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero);

      final b1 = ads.banner();
      final b2 = ads.banner();
      expect(b1, isNot(same(b2)));
      await b1.load(width: 320);
      expect(sdk.bannerSpecs.last.adUnitId, 'b-a');
      b1.dispose();
      b2.dispose();

      final n = ads.native();
      await n.load();
      expect(sdk.nativeSpecs.last.adUnitId, 'n-a');
      n.dispose();
      ads.dispose();
    });

    test('testMode swaps factory-built controllers to sample IDs', () async {
      sdk.canRequestAdsResult = true;
      final ads = await AdFlow.initialize(
        AdFlowConfig(
          banner: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'prod-b'),
          ),
          testMode: true,
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.bannerSpecs.single.adUnitId, TestAdUnitIds.banner.android);
      banner.dispose();
      ads.dispose();
    });

    test('missing slot config throws invalidConfig', () async {
      final ads = await boot(
        config: const AdFlowConfig(
          interstitial: InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'i-a'),
            cap: FrequencyCap(),
          ),
        ),
      );
      expect(() => ads.banner(), throwsA(isA<AdFlowError>()));
      expect(() => ads.native(), throwsA(isA<AdFlowError>()));
      ads.dispose();
    });
  });

  test('global frequency cap spans formats through the facade graph',
      () async {
    final ads = await AdFlow.initialize(
      const AdFlowConfig(
        interstitial: InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'i-a'),
          cap: FrequencyCap(),
        ),
        rewarded: RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r-a')),
        globalFrequencyCap: FrequencyCap(minGap: Duration(minutes: 10)),
      ),
      sdk: sdk..canRequestAdsResult = true,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await Future<void>.delayed(Duration.zero);

    expect(await ads.interstitial.show(), isTrue);
    // Dismiss it so the coordinator is clear — only the cap remains.
    sdk.interstitials.single.simulateDismissed();
    await Future<void>.delayed(Duration.zero);
    // The rewarded ad is warm but the GLOBAL cap blocks back-to-back shows.
    expect(ads.rewarded.isReady, isTrue);
    expect(await ads.rewarded.show(onReward: (_) {}), isFalse);
    ads.dispose();
  });

  test('openAdInspector delegates to the seam', () async {
    final ads = await boot();
    final result = await ads.openAdInspector();
    expect(result.isSuccess, isTrue);
    expect(sdk.adInspectorCalls, 1);
    ads.dispose();
  });
}
