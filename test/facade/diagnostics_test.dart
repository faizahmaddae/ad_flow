import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Why aren't my ads loading?" must be answerable (ADR-045).
///
/// A gate-blocked load reported plain `AdIdle` — indistinguishable from
/// "nothing has been requested yet". Consent never gathered, Remove-Ads left on,
/// a frequency cap doing its job: all three looked identical, and there was no
/// logging anywhere in the package (avoid_print is on). An integrator rolling
/// this out across many apps could not tell a bug from correct behaviour.
void main() {
  late FakeAdSdk sdk;

  const config = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
      cap: FrequencyCap(minGap: Duration(minutes: 5)),
    ),
  );

  setUp(() => sdk = FakeAdSdk()..enforceConsentGate = true);
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot({List<(String, AdBlockReason)>? log}) async {
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    if (log != null) {
      ads.onAdBlocked = (slot, reason) => log.add((slot, reason));
    }
    await ads.whenReady;
    await Future<void>.delayed(Duration.zero);
    return ads;
  }

  test('a load blocked because consent was never granted says so', () async {
    sdk.canRequestAdsResult = false; // the user declined, or never answered
    final log = <(String, AdBlockReason)>[];
    final ads = await boot(log: log);

    final banner = ads.banner();
    await banner.load(width: 320);

    // 3.0: the refused load is a first-class STATE, carrying its reason —
    // the AdIdle ambiguity ADR-045 documented (and could not fix in 2.x
    // without breaking exhaustive switches) is gone.
    expect(
      banner.state.value,
      const AdBlocked(AdBlockReason.consentNotGranted),
    );
    expect(banner.lastBlockReason, AdBlockReason.consentNotGranted);
    expect(log, contains(('banner', AdBlockReason.consentNotGranted)));

    banner.dispose();
    ads.dispose();
  });

  test('a load blocked by Remove-Ads says so', () async {
    sdk.canRequestAdsResult = true;
    final log = <(String, AdBlockReason)>[];
    final ads = await boot(log: log);
    ads.disableAds();

    final banner = ads.banner();
    await banner.load(width: 320);

    expect(banner.lastBlockReason, AdBlockReason.adsDisabled);
    expect(log, contains(('banner', AdBlockReason.adsDisabled)));

    banner.dispose();
    ads.dispose();
  });

  test('a show blocked by a frequency cap says so', () async {
    sdk.canRequestAdsResult = true;
    final log = <(String, AdBlockReason)>[];
    final ads = await boot(log: log);

    expect(await ads.interstitial.show(), isTrue);
    sdk.interstitials.single.simulateShowed();
    sdk.interstitials.single.simulateDismissed();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // A second show, well inside the 5-minute cap.
    expect(await ads.interstitial.show(), isFalse);

    expect(ads.interstitial.lastBlockReason, AdBlockReason.frequencyCapped);
    expect(log, contains(('interstitial', AdBlockReason.frequencyCapped)));
    ads.dispose();
  });

  test('a show with nothing warm says notReady, and a success clears the '
      'reason', () async {
    sdk.canRequestAdsResult = true;
    sdk.alwaysLoadError = const AdFlowError(
      AdFlowErrorKind.loadFailed,
      'no fill',
    );
    final ads = await boot();

    expect(await ads.interstitial.show(), isFalse);
    expect(ads.interstitial.lastBlockReason, AdBlockReason.notReady);

    // show() kicks a warm-up load; let it finish failing before asking again,
    // or load()'s re-entry guard just bails on the in-flight one.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(ads.interstitial.state.value, isA<AdFailed>());

    // Fill returns and the ad loads: the stale reason must not linger.
    sdk.alwaysLoadError = null;
    await ads.interstitial.load();
    expect(
      ads.interstitial.lastBlockReason,
      isNull,
      reason: 'a successful load means nothing is blocking this slot any more',
    );
    ads.dispose();
  });
}
