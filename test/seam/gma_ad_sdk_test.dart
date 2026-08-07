import 'dart:async';

import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/gma_ad_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_containers.dart'
    show AdSize, LoadAdError, RewardItem;
import 'package:google_mobile_ads/src/ad_instance_manager.dart';

/// Drives the real `google_mobile_ads` plugin's platform channel against
/// [GmaAdSdk] — the seam file NOTHING else in ad_flow can import (invariant
/// 8), and therefore the only place these bugs can be caught. `FakeAdSdk`
/// intentionally does not model the plugin's actual channel/listener wiring,
/// so it cannot see bugs that live purely in that wiring (review findings
/// #1's seam half, #2, and the general "GmaAdSdk is essentially untested"
/// gap, review finding #9).
///
/// Pattern mirrors the plugin's own `test/banner_ad_test.dart` /
/// `test/test_util.dart` (reachable in the pub cache but not importable
/// across packages, so the minimal pieces are reproduced here): a fresh
/// [AdInstanceManager] per test (so ad ids reset to 0), a mock method-call
/// handler answering outgoing `invokeMethod` calls, and
/// [_sendAdEvent] to simulate the platform's incoming `onAdEvent` calls
/// that the plugin normally sends after native SDK callbacks fire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  /// If set, the mock handler throws this instead of answering
  /// `'showAdWithoutView'` — simulates the plugin's show() Future
  /// rejecting (review finding #1's premise, verified here at the real
  /// seam instead of assumed).
  Object? showRejectsWith;

  /// If set, the mock handler throws this on any `load*Ad` call —
  /// simulates a raw platform-channel failure of the load DISPATCH itself
  /// (as opposed to the SDK's own onAdFailedToLoad callback).
  Object? loadDispatchRejectsWith;

  /// What the mock handler answers for `getAdSize` (an adaptive banner's
  /// post-load platform size query). Null simulates the query failing to
  /// produce a size.
  Object? platformAdSizeResult;

  /// If set, the mock handler throws this on `getAdSize` — simulates the
  /// post-load size query rejecting at the channel rather than answering null.
  Object? platformAdSizeRejectsWith;

  /// What the mock handler answers for the pre-load
  /// `AdSize#getLargeAnchoredAdaptiveBannerAdSize` height query (the number
  /// Dart resolves the anchored slot from). Null makes the resolver fail.
  Object? anchoredAdaptiveHeight;

  /// If set, the mock handler throws this on `setServerSideVerificationOptions`
  /// — simulates the one SSV-attach failure the plugin can actually surface
  /// (a channel-level error; the native handlers ack success unconditionally).
  Object? ssvAttachRejectsWith;

  setUp(() {
    log = <MethodCall>[];
    showRejectsWith = null;
    loadDispatchRejectsWith = null;
    platformAdSizeResult = null;
    platformAdSizeRejectsWith = null;
    anchoredAdaptiveHeight = null;
    ssvAttachRejectsWith = null;
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          log.add(call);
          switch (call.method) {
            case 'showAdWithoutView':
              final rejectsWith = showRejectsWith;
              if (rejectsWith != null) throw rejectsWith;
              return null;
            case 'loadBannerAd' || 'loadInterstitialAd'
                when loadDispatchRejectsWith != null:
              throw loadDispatchRejectsWith!;
            case 'getAdSize':
              if (platformAdSizeRejectsWith != null) {
                throw platformAdSizeRejectsWith!;
              }
              return platformAdSizeResult;
            case 'AdSize#getLargeAnchoredAdaptiveBannerAdSize':
              return anchoredAdaptiveHeight;
            case 'setServerSideVerificationOptions'
                when ssvAttachRejectsWith != null:
              throw ssvAttachRejectsWith!;
            case 'loadBannerAd':
            case 'loadInterstitialAd':
            case 'loadRewardedAd':
            case 'loadRewardedInterstitialAd':
            case 'loadAppOpenAd':
            case 'loadNativeAd':
            case 'setServerSideVerificationOptions':
            case 'disposeAd':
              return null;
            default:
              throw UnimplementedError(
                'gma_ad_sdk_test does not mock ${call.method}',
              );
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, null);
  });

  /// Simulates the platform sending an `onAdEvent` call for [adId], exactly
  /// as `test/test_util.dart` does in the plugin's own suite.
  Future<void> sendAdEvent(
    int adId,
    String eventName, [
    Map<String, dynamic>? additionalArgs,
  ]) async {
    final args = <String, dynamic>{'adId': adId, 'eventName': eventName};
    additionalArgs?.forEach((k, v) => args[k] = v);
    final data = instanceManager.channel.codec.encodeMethodCall(
      MethodCall('onAdEvent', args),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'plugins.flutter.io/google_mobile_ads',
          data,
          (data) {},
        );
  }

  group('banner load (review finding #2)', () {
    test('a single load completes the handle exactly once', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'unit-b',
          size: FixedSizeSpec(FixedBannerSize.banner),
        ),
      );
      // sdk.loadBanner suspends at its own internal awaits (resolving the
      // size, then ad.load()'s channel round trip) before the ad is
      // registered with instanceManager — flush those first, otherwise
      // sendAdEvent below dispatches to an adId that isn't tracked yet.
      await pumpEventQueue();

      await sendAdEvent(0, 'onAdLoaded');
      final handle = await future;

      expect(handle.adUnitId, 'unit-b');
      expect(handle.size, const AdDimensions(width: 320, height: 50));
      expect(log.map((c) => c.method), contains('loadBannerAd'));
    });

    test('a SECOND onAdLoaded firing (AdMob auto-refresh) does not throw '
        '"Future already completed" — the whole point of finding #2', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'unit-b',
          size: FixedSizeSpec(FixedBannerSize.banner),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      await future; // first (real) load completes normally

      // BannerAdListener.onAdLoaded fires on every AdMob-driven refresh
      // of the SAME BannerAd/adId, not just the first load — this must
      // not crash as an unhandled async error.
      await sendAdEvent(0, 'onAdLoaded');
    });

    test('a FAILED AdMob auto-refresh must not destroy the live banner, close '
        'its streams, or double-complete the load Future', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'unit-b',
          size: FixedSizeSpec(FixedBannerSize.banner),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      final handle = await future; // the banner is live and mounted

      final paid = <AdPaidEvent>[];
      var paidClosed = false;
      handle.paidEvents.listen(paid.add, onDone: () => paidClosed = true);
      await pumpEventQueue();

      // The SAME BannerAd's onAdFailedToLoad ALSO fires on a failed
      // AdMob-driven auto-refresh — routine on a weak network. Before the
      // fix this disposed the live, mounted ad, closed both of the handle's
      // stream controllers, and called completeError() on an
      // already-completed Completer ("Bad state: Future already completed",
      // an unhandled async error). The symmetric hole to finding #2.
      // ignore: invalid_use_of_protected_member
      final loadAdError = LoadAdError(2, 'admob', 'network error', null);
      await sendAdEvent(0, 'onAdFailedToLoad', {'loadAdError': loadAdError});
      await pumpEventQueue();

      expect(
        log.map((c) => c.method),
        isNot(contains('disposeAd')),
        reason:
            'the live banner must survive a failed refresh — the SDK '
            'keeps showing the previous creative and retries on its own',
      );
      expect(
        paidClosed,
        isFalse,
        reason:
            'closing the paid stream would silently stop all revenue '
            'reporting for this placement for the rest of the session',
      );
    });
  });

  // ADR-073 / issue #15. google_mobile_ads 9.0.0 cannot round-trip the "large"
  // bit of an anchored adaptive size: `AnchoredAdaptiveBannerAdSize` has no
  // `isLarge` field, the Dart encoder writes only (orientation, width), and
  // both native decoders rebuild it with `isLarge = false`. So Dart holds the
  // LARGE height while the AdView the ad renders in is the CLASSIC one — on a
  // 426x952dp phone, 67dp of ad inside a 133dp box, with the remainder showing
  // the app's own surface through the transparent platform view. The seam must
  // size the handle from the platform's own post-load answer, not from the
  // AdSize it asked for.
  group('anchored adaptive size reconciliation (ADR-073)', () {
    Future<BannerHandle> loadAnchored(GmaAdSdk sdk, {int width = 426}) async {
      final future = sdk.loadBanner(
        BannerLoadSpec(
          adUnitId: 'unit-b',
          size: AnchoredAdaptiveSizeSpec(width: width),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      await pumpEventQueue();
      return future;
    }

    test('the handle follows the PLATFORM size, not the requested one — the '
        'phantom band in issue #15', () async {
      final sdk = GmaAdSdk();
      // What Dart resolves through the large-anchored query...
      anchoredAdaptiveHeight = 133;
      // ...versus what the native AdView was actually constructed with,
      // because the codec dropped the large bit.
      platformAdSizeResult = AdSize(width: 426, height: 67);

      final handle = await loadAnchored(sdk);

      expect(
        handle.size,
        const AdDimensions(width: 426, height: 67),
        reason:
            'a 133dp box around a 67dp ad is 66dp of app background showing '
            'through the slot',
      );
      expect(log.map((c) => c.method), contains('getAdSize'));
    });

    test('a platform size query that answers nothing keeps the requested size '
        'and still COMPLETES the load (never fails a billable ad)', () async {
      final sdk = GmaAdSdk();
      anchoredAdaptiveHeight = 133;
      platformAdSizeResult = null;

      final handle = await loadAnchored(sdk);

      expect(
        handle.size,
        const AdDimensions(width: 426, height: 133),
        reason: 'anchored HAS a usable requested height to fall back on',
      );
      expect(
        log.map((c) => c.method),
        isNot(contains('disposeAd')),
        reason:
            'unlike inline adaptive, a failed query costs only the correction '
            '— it must never throw away a renderable ad',
      );
    });

    test('a platform size query that THROWS is equally non-fatal', () async {
      final sdk = GmaAdSdk();
      anchoredAdaptiveHeight = 133;
      platformAdSizeRejectsWith = PlatformException(code: 'boom');

      final handle = await loadAnchored(sdk);

      expect(handle.size, const AdDimensions(width: 426, height: 133));
      expect(log.map((c) => c.method), isNot(contains('disposeAd')));
    });

    test('a zero platform height is rejected as a size, not adopted', () async {
      final sdk = GmaAdSdk();
      anchoredAdaptiveHeight = 133;
      platformAdSizeResult = AdSize(width: 426, height: 0);

      final handle = await loadAnchored(sdk);

      expect(
        handle.size,
        const AdDimensions(width: 426, height: 133),
        reason: 'a zero-height box is a billable impression nobody can see',
      );
    });

    test('an auto-refresh that resolves a new platform size resizes the live '
        'handle and notifies listeners', () async {
      final sdk = GmaAdSdk();
      anchoredAdaptiveHeight = 133;
      platformAdSizeResult = AdSize(width: 426, height: 67);
      final handle = await loadAnchored(sdk);

      var notified = 0;
      handle.dimensions.addListener(() => notified++);

      platformAdSizeResult = AdSize(width: 426, height: 100);
      await sendAdEvent(0, 'onAdLoaded');
      await pumpEventQueue();

      expect(handle.size, const AdDimensions(width: 426, height: 100));
      expect(notified, 1);
      expect(log.map((c) => c.method), isNot(contains('disposeAd')));
    });

    test(
      'a fixed banner never pays for the platform size round trip',
      () async {
        final sdk = GmaAdSdk();
        final future = sdk.loadBanner(
          const BannerLoadSpec(
            adUnitId: 'unit-b',
            size: FixedSizeSpec(FixedBannerSize.banner),
          ),
        );
        await pumpEventQueue();
        await sendAdEvent(0, 'onAdLoaded');
        final handle = await future;

        expect(handle.size, const AdDimensions(width: 320, height: 50));
        expect(log.map((c) => c.method), isNot(contains('getAdSize')));
      },
    );
  });

  group('inline adaptive refresh (2026-07 audit)', () {
    Future<BannerHandle> loadInline(GmaAdSdk sdk) async {
      final future = sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'unit-b',
          size: InlineAdaptiveSizeSpec(width: 320, maxHeight: 200),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      await pumpEventQueue();
      return future;
    }

    test('a refresh whose getPlatformAdSize fails must NOT tear down the '
        'live banner (symmetric to review finding #2)', () async {
      final sdk = GmaAdSdk();
      platformAdSizeResult = AdSize(width: 320, height: 100);
      final handle = await loadInline(sdk);
      expect(handle.size, const AdDimensions(width: 320, height: 100));

      // AdMob auto-refresh re-fires onAdLoaded for the SAME ad; this time
      // the platform size query produces nothing. On the initial load that
      // is rightly a failed load — but on a refresh the ad on screen is
      // live, mounted and earning: destroying it (and closing the handle's
      // streams) turns one failed size query into a permanently dead slot.
      platformAdSizeResult = null;
      await sendAdEvent(0, 'onAdLoaded');
      await pumpEventQueue();

      expect(
        log.map((c) => c.method),
        isNot(contains('disposeAd')),
        reason: 'the live banner must survive a refresh size-query failure',
      );
      expect(
        handle.size,
        const AdDimensions(width: 320, height: 100),
        reason: 'keep the last known size when the query fails',
      );
    });

    test('the FIRST load still fails cleanly when no platform size resolves '
        '(zero-height box = a billable impression nobody can see)', () async {
      final sdk = GmaAdSdk();
      platformAdSizeResult = null;
      final future = sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'unit-b',
          size: InlineAdaptiveSizeSpec(width: 320, maxHeight: 200),
        ),
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.loadFailed,
          ),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      await expectation;
      expect(log.map((c) => c.method), contains('disposeAd'));
    });

    test('a refresh that resolves a NEW size updates the handle and '
        'notifies dimensions listeners', () async {
      final sdk = GmaAdSdk();
      platformAdSizeResult = AdSize(width: 320, height: 100);
      final handle = await loadInline(sdk);

      var notified = 0;
      handle.dimensions.addListener(() => notified++);

      // Inline adaptive creatives legitimately vary in height per refresh;
      // the widget sizes its box from the handle, so it must be told.
      platformAdSizeResult = AdSize(width: 320, height: 150);
      await sendAdEvent(0, 'onAdLoaded');
      await pumpEventQueue();

      expect(handle.size, const AdDimensions(width: 320, height: 150));
      expect(notified, 1);
    });
  });

  group('remaining formats through the REAL plugin channel (2026-07 audit — '
      'gma_ad_sdk was the least-covered file in the package)', () {
    test('rewarded: SSV is attached BEFORE the load completes, and the '
        'reward callback maps through', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadRewarded(
        'unit-r',
        const AdRequestOptions(),
        ssv: const ServerSideVerification(userId: 'u-1', customData: 'm-7'),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      final handle = await future;
      await pumpEventQueue();

      final methods = log.map((c) => c.method).toList();
      expect(methods, contains('setServerSideVerificationOptions'));
      expect(
        methods.indexOf('setServerSideVerificationOptions'),
        greaterThan(methods.indexOf('loadRewardedAd')),
        reason: 'SSV attaches to the LOADED ad, before any show',
      );

      final rewards = <RewardEarned>[];
      unawaited(handle.show(onUserEarnedReward: rewards.add));
      await pumpEventQueue();
      // The codec expects a real RewardItem, mirroring the plugin's own
      // onRewardedAdUserEarnedReward test.
      await sendAdEvent(0, 'onRewardedAdUserEarnedReward', {
        'rewardItem': RewardItem(10, 'coins'),
      });
      await pumpEventQueue();
      expect(rewards, [const RewardEarned(amount: 10, type: 'coins')]);
    });

    test('SSV attach failure FAILS the load and releases the ad — never a '
        '"ready" ad that silently lost its server-side verification '
        '(4.0 audit)', () async {
      ssvAttachRejectsWith = PlatformException(code: 'ssv-attach');
      final sdk = GmaAdSdk();
      final future = sdk.loadRewarded(
        'unit-r',
        const AdRequestOptions(),
        ssv: const ServerSideVerification(userId: 'u-1'),
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<AdFlowError>().having((e) => e.kind, 'kind', AdFlowErrorKind.ssv),
        ),
      );
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      await expectation;
      await pumpEventQueue();
      expect(
        log.map((c) => c.method),
        contains('disposeAd'),
        reason: 'the un-verifiable ad must be released, not leaked',
      );
    });

    test(
      'rewarded interstitial: SSV attach failure fails the load too',
      () async {
        ssvAttachRejectsWith = PlatformException(code: 'ssv-attach');
        final sdk = GmaAdSdk();
        final future = sdk.loadRewardedInterstitial(
          'unit-ri',
          const AdRequestOptions(),
          ssv: const ServerSideVerification(userId: 'u-1'),
        );
        final expectation = expectLater(
          future,
          throwsA(
            isA<AdFlowError>().having(
              (e) => e.kind,
              'kind',
              AdFlowErrorKind.ssv,
            ),
          ),
        );
        await pumpEventQueue();
        await sendAdEvent(0, 'onAdLoaded');
        await expectation;
      },
    );

    test('no SSV configured: an SSV-channel fault cannot fail the load '
        '(nothing to attach)', () async {
      ssvAttachRejectsWith = PlatformException(code: 'ssv-attach');
      final sdk = GmaAdSdk();
      final future = sdk.loadRewarded('unit-r', const AdRequestOptions());
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      expect(await future, isA<RewardedHandle>());
    });

    test('runtime SSV update reaches the channel', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadRewarded('unit-r', const AdRequestOptions());
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      final handle = await future;

      await handle.updateServerSideVerification(
        const ServerSideVerification(userId: 'late-user'),
      );
      expect(
        log.map((c) => c.method),
        contains('setServerSideVerificationOptions'),
      );
    });

    test(
      'rewarded interstitial: loads and dismisses through the channel',
      () async {
        final sdk = GmaAdSdk();
        final future = sdk.loadRewardedInterstitial(
          'unit-ri',
          const AdRequestOptions(),
        );
        await pumpEventQueue();
        await sendAdEvent(0, 'onAdLoaded');
        final handle = await future;

        final events = <FullScreenAdEvent>[];
        handle.contentEvents.listen(events.add);
        await pumpEventQueue();
        await sendAdEvent(0, 'onAdDismissedFullScreenContent');
        await pumpEventQueue();
        expect(events.single, isA<AdDismissedEvent>());
      },
    );

    test('app open: loads through the channel', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadAppOpen('unit-ao', const AdRequestOptions());
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      final handle = await future;
      expect(handle.adUnitId, 'unit-ao');
      expect(log.map((c) => c.method), contains('loadAppOpenAd'));
    });

    test('native: loads, and a load FAILURE maps to AdFlowError', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadNative(
        const NativeLoadSpec(adUnitId: 'unit-n', factoryId: 'f'),
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.loadFailed,
          ),
        ),
      );
      await pumpEventQueue();
      // ignore: invalid_use_of_protected_member
      final loadAdError = LoadAdError(3, 'admob', 'no fill', null);
      await sendAdEvent(0, 'onAdFailedToLoad', {'loadAdError': loadAdError});
      await expectation;
      expect(log.map((c) => c.method), contains('disposeAd'));
    });
  });

  group('load-dispatch failures are normalized (2026-07 audit)', () {
    test('a raw platform throw from the banner load dispatch surfaces as '
        'AdFlowError, upholding the seam contract', () async {
      final sdk = GmaAdSdk();
      loadDispatchRejectsWith = PlatformException(
        code: 'channel-error',
        message: 'native failure constructing the ad',
      );
      await expectLater(
        sdk.loadBanner(
          const BannerLoadSpec(
            adUnitId: 'unit-b',
            size: FixedSizeSpec(FixedBannerSize.banner),
          ),
        ),
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.loadFailed,
          ),
        ),
      );
    });

    test('a raw platform throw from the interstitial load dispatch surfaces '
        'as AdFlowError', () async {
      final sdk = GmaAdSdk();
      loadDispatchRejectsWith = PlatformException(code: 'channel-error');
      await expectLater(
        sdk.loadInterstitial('unit-i', const AdRequestOptions()),
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.loadFailed,
          ),
        ),
      );
    });
  });

  group('interstitial (review finding #9 checklist)', () {
    Future<InterstitialHandle> loadInterstitial(GmaAdSdk sdk) async {
      final future = sdk.loadInterstitial('unit-i', const AdRequestOptions());
      await pumpEventQueue();
      await sendAdEvent(0, 'onAdLoaded');
      return future;
    }

    test('load-success completes the Future with a handle', () async {
      final sdk = GmaAdSdk();
      final handle = await loadInterstitial(sdk);
      expect(handle.adUnitId, 'unit-i');
      expect(log.map((c) => c.method), contains('loadInterstitialAd'));
    });

    test('a simulated dismiss emits exactly one AdDismissedEvent', () async {
      final sdk = GmaAdSdk();
      final handle = await loadInterstitial(sdk);
      final events = <FullScreenAdEvent>[];
      handle.contentEvents.listen(events.add);

      await sendAdEvent(0, 'onAdDismissedFullScreenContent');

      expect(events, hasLength(1));
      expect(events.single, isA<AdDismissedEvent>());
    });

    test('onAdFailedToLoad throws the mapped AdFlowError', () async {
      final sdk = GmaAdSdk();
      final future = sdk.loadInterstitial('unit-i', const AdRequestOptions());
      await pumpEventQueue();

      // Attach the expectation's listener to `future` BEFORE triggering
      // the error below — otherwise the completeError() inside
      // sendAdEvent races ahead with no listener attached yet, and Dart
      // reports it as an unhandled async error instead of surfacing it
      // through this expectation.
      final expectation = expectLater(
        future,
        throwsA(
          isA<AdFlowError>()
              .having((e) => e.kind, 'kind', AdFlowErrorKind.loadFailed)
              .having((e) => e.code, 'code', 3)
              .having((e) => e.domain, 'domain', 'admob')
              .having((e) => e.message, 'message', 'no fill'),
        ),
      );

      // LoadAdError's constructor is @protected (subclass-only by
      // convention) inside the plugin; the plugin's own test suite
      // constructs it directly from test code the same way (see
      // test/banner_ad_test.dart), so this mirrors an authoritative
      // pattern rather than fabricating one.
      // ignore: invalid_use_of_protected_member
      final loadAdError = LoadAdError(3, 'admob', 'no fill', null);
      await sendAdEvent(0, 'onAdFailedToLoad', {'loadAdError': loadAdError});

      await expectation;
    });

    test('a rejected show() (finding #1\'s premise) throws rather than '
        'silently no-oping — confirms the controller-level try/catch fix '
        'guards a real, not just hypothetical, plugin failure mode', () async {
      final sdk = GmaAdSdk();
      final handle = await loadInterstitial(sdk);
      showRejectsWith = PlatformException(
        code: 'ad_already_released',
        message: 'This ad has already been shown or disposed.',
      );

      await expectLater(handle.show(), throwsA(isA<PlatformException>()));
    });
  });

  group('appForegroundEvents (review finding #9 checklist)', () {
    test('the first subscription triggers startListening', () async {
      final appStateLog = <MethodCall>[];
      const appStateChannel = MethodChannel(
        'plugins.flutter.io/google_mobile_ads/app_state_method',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appStateChannel, (call) async {
            appStateLog.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(appStateChannel, null),
      );

      final sdk = GmaAdSdk();
      expect(appStateLog, isEmpty); // not yet accessed

      final stream = sdk.appForegroundEvents;
      final subscription = stream.listen((_) {});
      await pumpEventQueue();

      expect(appStateLog.map((c) => c.method), contains('start'));
      await subscription.cancel();
    });
  });

  group('ATT platform guard', () {
    // On any non-iOS platform both ATT methods must short-circuit to
    // notSupported WITHOUT touching the app_tracking_transparency channel.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('getTrackingAuthorizationStatus → notSupported off iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sdk = GmaAdSdk();
      expect(
        await sdk.getTrackingAuthorizationStatus(),
        AttStatus.notSupported,
      );
    });

    test('requestTrackingAuthorization → notSupported off iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sdk = GmaAdSdk();
      expect(await sdk.requestTrackingAuthorization(), AttStatus.notSupported);
    });
  });
}
