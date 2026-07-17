import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revenue/mediation observability (2026-07 audit): a paid event must carry
/// enough context to log a standard analytics `ad_impression` (format +
/// winning ad source), and the mediation fill info must be reachable.
void main() {
  late FakeAdSdk sdk;

  const config = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
      cap: FrequencyCap(),
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
    await pumpEventQueue();
    return ads;
  }

  test('paid events arrive tagged with the SLOT that earned them', () async {
    final ads = await boot();
    final events = <AdPaidEvent>[];
    ads.onPaidEvent = events.add;

    final banner = ads.banner();
    await banner.load(width: 320);

    sdk.interstitials.single.simulatePaid(
      const AdPaidEvent(
        adUnitId: 'i-a',
        valueMicros: 12345,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.precise,
      ),
    );
    sdk.banners.single.simulatePaid(
      const AdPaidEvent(
        adUnitId: 'b-a',
        valueMicros: 678,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.estimated,
        adSourceName: 'AdMob Network',
      ),
    );

    expect(events, hasLength(2));
    expect(events.first.slot, 'interstitial');
    expect(events.last.slot, 'banner');
    expect(
      events.last.adSourceName,
      'AdMob Network',
      reason: 'the winning mediation source must ride along',
    );
    banner.dispose();
    ads.dispose();
  });

  test('controller.response surfaces the mediation fill summary', () async {
    final ads = await boot();
    const summary = AdResponseSummary(
      responseId: 'resp-1',
      adSourceName: 'Partner X',
      adSourceInstanceName: 'waterfall-3',
      mediationAdapterClassName: 'com.partner.Adapter',
    );
    sdk.interstitials.single.responseSummary = summary;

    expect(ads.interstitial.response, summary);
    ads.dispose();
  });
}
