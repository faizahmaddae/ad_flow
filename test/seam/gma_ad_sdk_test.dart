import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/gma_ad_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_containers.dart' show LoadAdError;
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

  setUp(() {
    log = <MethodCall>[];
    showRejectsWith = null;
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          log.add(call);
          switch (call.method) {
            case 'showAdWithoutView':
              final rejectsWith = showRejectsWith;
              if (rejectsWith != null) throw rejectsWith;
              return Future<void>.value();
            case 'loadBannerAd':
            case 'loadInterstitialAd':
            case 'disposeAd':
              return Future<void>.value();
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
      expect(
        log.map((c) => c.method),
        contains('loadBannerAd'),
      );
    });

    test(
      'a SECOND onAdLoaded firing (AdMob auto-refresh) does not throw '
      '"Future already completed" — the whole point of finding #2',
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
        await future; // first (real) load completes normally

        // BannerAdListener.onAdLoaded fires on every AdMob-driven refresh
        // of the SAME BannerAd/adId, not just the first load — this must
        // not crash as an unhandled async error.
        await sendAdEvent(0, 'onAdLoaded');
      },
    );
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

    test(
      'a rejected show() (finding #1\'s premise) throws rather than '
      'silently no-oping — confirms the controller-level try/catch fix '
      'guards a real, not just hypothetical, plugin failure mode',
      () async {
        final sdk = GmaAdSdk();
        final handle = await loadInterstitial(sdk);
        showRejectsWith = PlatformException(
          code: 'ad_already_released',
          message: 'This ad has already been shown or disposed.',
        );

        await expectLater(handle.show(), throwsA(isA<PlatformException>()));
      },
    );
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
}
