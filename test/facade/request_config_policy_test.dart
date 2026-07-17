import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// RequestConfigFailurePolicy (4.0 audit): request configuration is a
/// retried PROCESS, and its failure is either honestly blocking (policy-
/// critical fields) or honestly degrading (vacuous config) — never a silent
/// loss of COPPA tags / content rating / test-device registration.
void main() {
  late FakeAdSdk sdk;

  const sensitiveConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    tagForChildDirectedTreatment: true,
  );

  const vacuousConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
  );

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
  );

  group('auto policy', () {
    test('child-directed + failing config apply → loads BLOCK visibly, then '
        'recover on the slot\'s own backoff once the apply succeeds', () {
      fakeAsync((async) {
        sdk.updateRequestConfigurationError = const AdFlowError(
          AdFlowErrorKind.unknown,
          'config boom',
        );
        AdFlow? ads;
        unawaited(boot(sensitiveConfig).then((f) => ads = f));
        async.flushMicrotasks();

        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(seconds: 1));

        expect(
          sdk.bannerSpecs,
          isEmpty,
          reason:
              'a child-directed app must never send an untagged ad request '
              'because a config call failed — that is a COPPA violation, '
              'not a degradation',
        );
        expect(banner.state.value, isA<AdBlocked>());
        expect(banner.lastBlockReason, AdBlockReason.requestConfigNotApplied);

        // The channel heals: the rate-limited retry re-applies, and the
        // slot's own gate-recheck backoff picks it up — no app code needed.
        sdk.updateRequestConfigurationError = null;
        async.elapse(const Duration(minutes: 3));
        async.flushMicrotasks();
        expect(sdk.requestConfigs, isNotEmpty);
        expect(sdk.bannerSpecs, isNotEmpty);
        banner.dispose();
        ads!.dispose();
      });
    });

    test('vacuous config + failing apply → loads proceed (nothing of policy '
        'value was lost)', () async {
      sdk.updateRequestConfigurationError = const AdFlowError(
        AdFlowErrorKind.unknown,
        'config boom',
      );
      final ads = await boot(vacuousConfig);
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.bannerSpecs, hasLength(1));
      banner.dispose();
      ads.dispose();
    });
  });

  group('explicit policies', () {
    test('failOpen: even a child-directed config failure lets loads proceed '
        '(the publisher explicitly chose revenue over the tag)', () async {
      sdk.updateRequestConfigurationError = const AdFlowError(
        AdFlowErrorKind.unknown,
        'config boom',
      );
      final ads = await boot(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
          tagForChildDirectedTreatment: true,
          requestConfigPolicy: RequestConfigFailurePolicy.failOpen,
        ),
      );
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.bannerSpecs, hasLength(1));
      banner.dispose();
      ads.dispose();
    });

    test('failClosed: a vacuous config failure still blocks loads', () async {
      sdk.updateRequestConfigurationError = const AdFlowError(
        AdFlowErrorKind.unknown,
        'config boom',
      );
      final ads = await boot(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
          requestConfigPolicy: RequestConfigFailurePolicy.failClosed,
        ),
      );
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.bannerSpecs, isEmpty);
      expect(banner.lastBlockReason, AdBlockReason.requestConfigNotApplied);
      banner.dispose();
      ads.dispose();
    });
  });

  group('ADR-028 hardening: config is NEVER dispatched while init is in '
      'flight', () {
    test('a timed-out init does not trigger a config dispatch — the call '
        'waits for the REAL init completion', () {
      fakeAsync((async) {
        sdk.initializeHold = Completer<void>(); // native init never returns…
        AdFlow? ads;
        unawaited(boot(sensitiveConfig).then((f) => ads = f));
        async.flushMicrotasks();

        // Past the bounded init wait: the OLD code dispatched
        // updateRequestConfiguration right here — while the native init may
        // still be mid-bootstrap on the platform thread, which is exactly
        // the ADR-028 deadlock window on slow devices.
        async.elapse(const Duration(seconds: 45));
        async.flushMicrotasks();
        expect(
          sdk.updateRequestConfigurationCalls,
          0,
          reason:
              'updateRequestConfiguration must never race a live '
              'initialize() — the plugin services it synchronously on the '
              'platform thread (ADR-028)',
        );

        // …init finally lands: the completion hook applies config now.
        sdk.initializeHold!.complete();
        sdk.initializeHold = null;
        async.flushMicrotasks();
        expect(sdk.updateRequestConfigurationCalls, greaterThan(0));
        expect(sdk.requestConfigs, hasLength(1));
        ads?.dispose();
      });
    });

    test('loads under a never-completing init resolve to AdBlocked (bounded), '
        'never park forever', () {
      fakeAsync((async) {
        sdk.initializeHold = Completer<void>();
        AdFlow? ads;
        unawaited(boot(sensitiveConfig).then((f) => ads = f));
        async.flushMicrotasks();

        final banner = ads!.banner();
        unawaited(banner.load(width: 320));
        async.elapse(const Duration(seconds: 65));
        async.flushMicrotasks();

        expect(banner.state.value, isNot(isA<AdLoading>()));
        expect(banner.lastBlockReason, AdBlockReason.requestConfigNotApplied);
        expect(sdk.bannerSpecs, isEmpty);
        banner.dispose();
        ads!.dispose();
      });
    });
  });
}
