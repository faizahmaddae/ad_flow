import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two weak-network revenue holes, which together decide whether a user on
/// a slow or intermittent connection sees ANY ads at all.
void main() {
  const config = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
    ),
  );

  test(
    'a first-frame banner does not stay blank for 5 minutes while consent is '
    'still resolving',
    () {
      fakeAsync((async) {
        final sdk = FakeAdSdk()
          ..enforceConsentGate = true
          ..canRequestAdsResult = false
          ..consentStatus = AdConsentStatus.required
          ..consentFormAvailable = true
          // An EEA user reading the GDPR form: consent resolves 2s in.
          ..consentUpdateHold = null;

        late AdFlow ads;
        // ignore: discarded_futures
        AdFlow.initialize(
          config,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ).then((f) => ads = f);
        async.flushMicrotasks();

        // The app renders immediately (ADR-032) and mounts its banner on the
        // first frame — the documented, example-app usage.
        final banner = ads.banner();
        // ignore: discarded_futures
        banner.load(width: 320);
        async.elapse(const Duration(milliseconds: 100));

        // Consent opens shortly after (form dismissed).
        sdk.canRequestAdsResult = true;
        async.elapse(const Duration(seconds: 2));

        // Give the graph a beat to notice.
        async.elapse(const Duration(seconds: 10));

        expect(
          sdk.banners,
          isNotEmpty,
          reason: 'the banner must load once the consent gate opens — not sit '
              'blank until RetryConfig.cooldown (5 minutes) elapses. This is '
              'the first session of every new install: the highest-value '
              'window, on every app.',
        );

        banner.dispose();
        ads.dispose();
        async.elapse(const Duration(minutes: 10));
      });
    },
  );

  test(
    'an offline launch still serves ads once the network returns (the consent '
    'flow is retried, not run exactly once per session)',
    () {
      fakeAsync((async) {
        final sdk = FakeAdSdk()
          ..enforceConsentGate = true
          ..canRequestAdsResult = false
          // Airplane mode / dead network at launch: the UMP info update fails,
          // so UMP never determines consent and canRequestAds() stays false.
          ..consentUpdateError = const AdFlowError(
            AdFlowErrorKind.consent,
            'offline',
          );

        late AdFlow ads;
        // ignore: discarded_futures
        AdFlow.initialize(
          config,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ).then((f) => ads = f);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        expect(sdk.consentUpdateCalls, hasLength(1));
        expect(sdk.interstitials, isEmpty, reason: 'gate closed: no ads yet');

        // The network comes back 30s in. A real UMP info update would now
        // succeed and flip canRequestAds() — but only if something calls it
        // again. Before the fix, nothing ever did: the consent flow ran
        // exactly once per session, so an offline launch meant ZERO ads for
        // the entire session even after connectivity returned.
        sdk.consentUpdateError = null;
        sdk.onConsentInfoUpdate = () => sdk.canRequestAdsResult = true;
        async.elapse(const Duration(seconds: 30));

        expect(
          sdk.consentUpdateCalls.length,
          greaterThan(1),
          reason: 'the consent flow must be retried once it has failed',
        );
        expect(
          sdk.interstitials,
          isNotEmpty,
          reason: 'and the ads that were blocked behind it must now load',
        );

        ads.dispose();
        async.elapse(const Duration(minutes: 10));
      });
    },
  );

  test('a user who simply DECLINED consent is not re-prompted in a loop', () {
    fakeAsync((async) {
      final sdk = FakeAdSdk()
        ..enforceConsentGate = true
        // The flow succeeded; the user just said no. lastError stays null.
        ..canRequestAdsResult = false;

      late AdFlow ads;
      // ignore: discarded_futures
      AdFlow.initialize(
        config,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      ).then((f) => ads = f);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 20));

      expect(
        sdk.consentUpdateCalls,
        hasLength(1),
        reason: 'a declined consent is a settled answer, not a failure — '
            're-running the flow would re-prompt the user forever',
      );
      expect(sdk.interstitials, isEmpty);

      ads.dispose();
      async.elapse(const Duration(minutes: 10));
    });
  });
}
