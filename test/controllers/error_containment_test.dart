import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cap policy whose store/clock machinery blows up with a NON-[AdFlowError]
/// — exactly what a corrupt `shared_preferences` backend (PlatformException)
/// does on a real device.
class _ThrowingCaps implements FrequencyCapPolicy {
  bool throwOnCanShow = false;
  bool throwOnRecord = false;

  @override
  Future<bool> canShow(String slot) async {
    if (throwOnCanShow) throw const FormatException('corrupt store');
    return true;
  }

  @override
  Future<void> recordImpression(String slot) async {
    if (throwOnRecord) throw const FormatException('corrupt store');
  }
}

/// A seam whose `load*` calls throw a raw platform-style error rather than the
/// documented [AdFlowError] — models `MissingPluginException` /
/// `PlatformException`, and the plugin's own `canRequestAds()` force-unwrap.
class _ThrowingSdk extends FakeAdSdk {
  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) async => throw const FormatException('MissingPluginException');

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) async =>
      throw const FormatException('MissingPluginException');

  @override
  Future<NativeHandle> loadNative(NativeLoadSpec spec) async =>
      throw const FormatException('MissingPluginException');
}

void main() {
  group('show() never wedges the coordinator on a throwing collaborator', () {
    late FakeAdSdk sdk;
    late FullScreenAdCoordinator coordinator;
    late _ThrowingCaps caps;

    setUp(() {
      sdk = FakeAdSdk()
        ..enforceConsentGate = true
        ..canRequestAdsResult = true;
      coordinator = FullScreenAdCoordinator();
      caps = _ThrowingCaps();
    });
    tearDown(() {
      coordinator.dispose();
      sdk.dispose();
    });

    InterstitialAdController build({bool Function()? gateThrows}) =>
        InterstitialAdController(
          sdk: sdk,
          gate: AdGate(
            canRequestAds: () async {
              if (gateThrows?.call() ?? false) {
                throw const FormatException('channel error');
              }
              return true;
            },
            isEnabled: () => true,
          ),
          caps: caps,
          coordinator: coordinator,
          config: const InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-i'),
          ),
          adUnitId: 'unit-i',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );

    test(
      'a throwing frequency-cap store leaves the coordinator free',
      () async {
        final controller = build();
        await controller.load();
        expect(controller.state.value, isA<AdLoaded>());

        caps.throwOnCanShow = true;
        final shown = await controller.show();

        expect(shown, isFalse);
        expect(
          coordinator.isFullScreenAdVisible,
          isFalse,
          reason:
              'a throwing caps check must not leave the coordinator claimed '
              '— otherwise EVERY full-screen format is dead for the session',
        );
        expect(controller.state.value, isNot(isA<AdShowing>()));
        controller.dispose();
      },
    );

    test('a throwing gate leaves the coordinator free', () async {
      var boom = false;
      final controller = build(gateThrows: () => boom);
      await controller.load();
      expect(controller.state.value, isA<AdLoaded>());

      boom = true;
      final shown = await controller.show();

      expect(shown, isFalse);
      expect(coordinator.isFullScreenAdVisible, isFalse);
      controller.dispose();
    });

    test('after a throwing show(), a later show() still works', () async {
      final controller = build();
      await controller.load();
      caps.throwOnCanShow = true;
      await controller.show();

      caps.throwOnCanShow = false;
      final shown = await controller.show();
      expect(
        shown,
        isTrue,
        reason: 'the slot must recover, not stay wedged for the session',
      );
      controller.dispose();
    });
  });

  group('load() contains a non-AdFlowError from the seam', () {
    late _ThrowingSdk sdk;
    late FullScreenAdCoordinator coordinator;
    late StoredFrequencyCapPolicy caps;

    setUp(() {
      sdk = _ThrowingSdk()..canRequestAdsResult = true;
      coordinator = FullScreenAdCoordinator();
      caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
      );
    });
    tearDown(() {
      coordinator.dispose();
      sdk.dispose();
    });

    AdGate gate() =>
        AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true);

    test('full-screen: lands in AdFailed and retries, not stuck AdLoading', () {
      fakeAsync((async) {
        final controller = InterstitialAdController(
          sdk: sdk,
          gate: gate(),
          caps: caps,
          coordinator: coordinator,
          config: const InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-i'),
          ),
          adUnitId: 'unit-i',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        unawaited(controller.load());
        async.elapse(const Duration(seconds: 1));

        expect(
          controller.state.value,
          isA<AdFailed>(),
          reason:
              'a PlatformException must not leave the slot stuck at '
              'AdLoading forever with no retry armed',
        );
        controller.dispose();
      });
    });

    test('banner: lands in AdFailed and retries, not stuck AdLoading', () {
      fakeAsync((async) {
        final controller = BannerAdController(
          sdk: sdk,
          gate: gate(),
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
          ),
          adUnitId: 'unit-b',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        unawaited(controller.load(width: 320));
        async.elapse(const Duration(seconds: 1));

        expect(controller.state.value, isA<AdFailed>());
        controller.dispose();
      });
    });

    test('native: lands in AdFailed and retries, not stuck AdLoading', () {
      fakeAsync((async) {
        final controller = NativeAdController(
          sdk: sdk,
          gate: gate(),
          config: const NativeConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-n'),
            templateKind: NativeTemplateKind.small,
          ),
          adUnitId: 'unit-n',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        unawaited(controller.load());
        async.elapse(const Duration(seconds: 1));

        expect(controller.state.value, isA<AdFailed>());
        controller.dispose();
      });
    });
  });
}
