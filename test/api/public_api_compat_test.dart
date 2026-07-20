// Public-API / semver compatibility guard.
//
// This file imports ONLY the public barrels — no `src/` paths — so it compiles
// exactly what an external consumer can. `FullScreenAdControllerBase` is
// exported, and `onLoaded()` is a non-underscore member, so it is PUBLIC API
// (@protected does not make it private). Renaming/removing it is breaking; this
// pins it in place and pins its post-publish semantics.
import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// An external-style full-screen controller built against the public API only,
/// overriding the legacy [FullScreenAdControllerBase.onLoaded] hook.
class _ExternalController extends FullScreenAdControllerBase {
  _ExternalController({
    required super.sdk,
    required super.gate,
    required super.caps,
    required super.coordinator,
    required super.adUnitId,
  }) : super(slot: 'external');

  final List<AdLoadState> onLoadedSaw = [];

  @override
  void onLoaded() => onLoadedSaw.add(state.value);

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadInterstitial(adUnitId, const AdRequestOptions());
}

void main() {
  test(
    'an external subclass overriding onLoaded() still compiles against '
    'package:ad_flow/ad_flow.dart and onLoaded runs AFTER AdLoaded',
    () async {
      final sdk = FakeAdSdk()..canRequestAdsResult = true;
      addTearDown(sdk.dispose);
      final coordinator = FullScreenAdCoordinator();
      addTearDown(coordinator.dispose);

      final c = _ExternalController(
        sdk: sdk,
        gate: AdGate(canRequestAds: () async => true, isEnabled: () => true),
        caps: StoredFrequencyCapPolicy(
          store: InMemoryKeyValueStore(),
          slotCaps: const {},
          globalCap: const FrequencyCap(),
        ),
        coordinator: coordinator,
        adUnitId: 'unit-x',
      );

      await c.load();

      expect(c.state.value, isA<AdLoaded>());
      expect(
        c.onLoadedSaw,
        hasLength(1),
        reason: 'onLoaded fires exactly once per successful load',
      );
      expect(
        c.onLoadedSaw.single,
        isA<AdLoaded>(),
        reason:
            'onLoaded keeps its post-publish semantics (AdLoaded already set)',
      );
      c.dispose();
    },
  );
}
