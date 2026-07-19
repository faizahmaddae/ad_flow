import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Async rejection containment through the ACTUAL public callback types
/// (release gate). Every app-facing callback is declared `void Function(...)`,
/// but Dart's return-type covariance to `void` lets an `async` closure be
/// assigned to it — the closure returns a `Future` at runtime. If any wrapper
/// on the dispatch path (e.g. the facade's `_dispatchPaid => onPaidEvent?.call`)
/// swallowed that `Future` behind its `void` return, a later rejection would
/// escape as an unhandled zone error. These tests drive the REAL dispatch
/// chain and prove the rejection is observed (reported) instead.
///
/// Detection: in `flutter_test`, an unhandled async error inside the test zone
/// FAILS the test. So "the test completes AND the error was reported to
/// FlutterError.onError" is proof the Future was observed, not discarded.
void main() {
  late FakeAdSdk sdk;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previousOnError;

  setUp(() {
    sdk = FakeAdSdk()
      ..consentStatus = AdConsentStatus.notRequired
      ..canRequestAdsResult = true;
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });
  tearDown(() {
    FlutterError.onError = previousOnError;
    sdk.dispose();
  });

  Future<AdFlow> boot(AdFlowConfig config) => AdFlow.initialize(
    config,
    sdk: sdk,
    store: InMemoryKeyValueStore(),
    platform: AdPlatform.android,
    rewardedIntroPresenter: (_) async => true,
  );

  const interstitialCfg = AdFlowConfig(
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
    ),
  );

  test('an ASYNC-rejecting onPaidEvent (void Function(AdPaidEvent)) is '
      'contained through the controller→facade dispatch, not discarded by the '
      'void wrapper', () async {
    final ads = await boot(interstitialCfg);
    await ads.whenReady;
    // Assigned to the void-typed public field — an async closure.
    ads.onPaidEvent = (event) async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('analytics async bug');
    };

    await ads.interstitial.load();
    await pumpEventQueue();
    sdk.interstitials.last.simulatePaid(
      const AdPaidEvent(
        adUnitId: 'i-a',
        valueMicros: 1000,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.estimated,
      ),
    );
    await pumpEventQueue();

    expect(
      reported.where((r) => r.exception is StateError),
      isNotEmpty,
      reason:
          'the async paid-event callback rejection must be reported, proving '
          'its Future was observed and not dropped by the void wrapper',
    );
    ads.dispose();
  });

  test('an ASYNC-rejecting onAdBlocked (void Function(String, AdBlockReason)) '
      'is contained through the dispatch chain', () async {
    final ads = await boot(interstitialCfg);
    await ads.whenReady;
    ads.onAdBlocked = (slot, reason) async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('logging async bug');
    };

    // Force a block: Remove-Ads on, then load.
    ads.disableAds();
    await ads.interstitial.load();
    await pumpEventQueue();

    expect(
      reported.where((r) => r.exception is StateError),
      isNotEmpty,
      reason: 'the async onAdBlocked rejection must be reported',
    );
    ads.dispose();
  });

  test('an ASYNC-rejecting onConsentChanged is contained on a MUTATION (the '
      'real dispatch, not guardedCallback in isolation)', () async {
    final ads = await boot(interstitialCfg);
    await ads.whenReady;
    ads.onConsentChanged = () async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('forward async bug');
    };

    await ads.consent.showPrivacyOptions(); // a mutation → _dispatchConsentChanged
    await pumpEventQueue();

    expect(
      reported.where((r) => r.exception is StateError),
      isNotEmpty,
      reason: 'the async onConsentChanged rejection must be reported',
    );
    ads.dispose();
  });

  test('an ASYNC-rejecting onReward is contained through show()', () async {
    final ads = await boot(
      const AdFlowConfig(
        rewarded: RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r-a')),
      ),
    );
    await ads.whenReady;
    await ads.rewarded.load();
    await pumpEventQueue();
    await ads.rewarded.show(
      onReward: (reward) async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('grant async bug');
      },
    );
    sdk.rewardeds.last.simulateReward(
      const RewardEarned(amount: 10, type: 'coins'),
    );
    await pumpEventQueue();

    expect(
      reported.where((r) => r.exception is StateError),
      isNotEmpty,
      reason: 'the async reward-grant rejection must be reported',
    );
    ads.dispose();
  });

  test('a normally-completing async callback reports NOTHING (non-vacuity: the '
      'above are not just reporting everything)', () async {
    final ads = await boot(interstitialCfg);
    await ads.whenReady;
    ads.onPaidEvent = (event) async => Future<void>.delayed(Duration.zero);
    await ads.interstitial.load();
    await pumpEventQueue();
    sdk.interstitials.last.simulatePaid(
      const AdPaidEvent(
        adUnitId: 'i-a',
        valueMicros: 1,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.estimated,
      ),
    );
    await pumpEventQueue();
    expect(reported, isEmpty);
    ads.dispose();
  });
}
