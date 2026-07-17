import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ADR-042(a) click latch WIRING: a click/open on a banner or native ad
/// must reach the shared coordinator, and its close must start the grace
/// clock — previously untested at the controller link (2026-07 audit test
/// gap; the coordinator's own semantics are covered in
/// full_screen_ad_coordinator_test.dart).
void main() {
  late FakeAdSdk sdk;
  late DateTime now;
  late FullScreenAdCoordinator coordinator;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    now = DateTime(2026, 7, 17, 12);
    coordinator = FullScreenAdCoordinator(now: () => now);
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() =>
      AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true);

  test('a banner CLICK arms the latch; the next foreground consume is '
      'suppressed exactly once', () async {
    final c = BannerAdController(
      sdk: sdk,
      gate: gate(),
      config: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b')),
      adUnitId: 'b',
      coordinator: coordinator,
    );
    await c.load(width: 320);

    sdk.banners.single.simulateEvent(ViewAdEvent.clicked);
    expect(coordinator.consumeViewAdOpened(), isTrue);
    expect(coordinator.consumeViewAdOpened(), isFalse);
    c.dispose();
  });

  test('a native OPEN arms the latch too', () async {
    final c = NativeAdController(
      sdk: sdk,
      gate: gate(),
      config: const NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'n'),
        templateKind: NativeTemplateKind.small,
      ),
      adUnitId: 'n',
      coordinator: coordinator,
    );
    await c.load();

    sdk.natives.single.simulateEvent(ViewAdEvent.opened);
    expect(coordinator.consumeViewAdOpened(), isTrue);
    c.dispose();
  });

  test('a banner CLOSE starts the grace clock: a much-later consume finds '
      'the latch expired (iOS in-app overlay — no foreground event ever '
      'fires, and the latch must not eat the next real warm return)', () async {
    final c = BannerAdController(
      sdk: sdk,
      gate: gate(),
      config: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b')),
      adUnitId: 'b',
      coordinator: coordinator,
    );
    await c.load(width: 320);

    sdk.banners.single.simulateEvent(ViewAdEvent.clicked);
    sdk.banners.single.simulateEvent(ViewAdEvent.closed);
    now = now.add(const Duration(minutes: 3));

    expect(coordinator.consumeViewAdOpened(), isFalse);
    c.dispose();
  });
}
