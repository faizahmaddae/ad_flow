import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/gma_ad_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    log = <MethodCall>[];
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          log.add(call);
          switch (call.method) {
            case 'loadBannerAd':
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
}
