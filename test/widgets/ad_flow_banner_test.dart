import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:ad_flow/src/widgets/ad_flow_banner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  BannerAdController controller({BannerConfig? config}) => BannerAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: sdk.canRequestAds,
      isEnabled: () => true,
      caps: StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
      ),
      coordinator: coordinator,
    ),
    config:
        config ??
        const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
    adUnitId: 'unit-b',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
  );

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topCenter, child: child),
  );

  testWidgets('reserves height before load, then hosts the sized ad', (
    tester,
  ) async {
    sdk.bannerSize = const AdDimensions(width: 360, height: 60);
    final c = controller();

    await tester.pumpWidget(
      host(AdFlowBanner(controller: c, ownsController: true)),
    );

    // First frame: placeholder reserved BEFORE any load. Anchored adaptive
    // banners have no pure-width height formula (Google docs: 50–90dp,
    // capped at 15% of device height), so the widget reserves the
    // device-height-aware estimate rather than the controller's 50dp
    // floor (review finding #8) — on the default 800x600 test surface,
    // 15% of 600 is exactly the 90dp ceiling.
    final placeholder = tester.getSize(find.byType(AdFlowBanner));
    expect(placeholder.height, 90);

    await tester.pumpAndSettle();

    final loaded = tester.getSize(find.byType(AdFlowBanner));
    expect(loaded.width, 360);
    expect(loaded.height, 60);
    // Load used the real layout width (800 logical px test surface).
    expect(
      sdk.bannerSpecs.single.size,
      isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 800),
    );

    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets(
    'adaptive placeholder height scales with device height, clamped to '
    'Google\'s documented 50-90dp bounds (review finding #8)',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;

      // A short viewport: 15% of height is below the documented floor.
      tester.view.physicalSize = const Size(400, 200);
      final c1 = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c1, ownsController: true)),
      );
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 50);
      await tester.pumpWidget(host(const SizedBox()));

      // A mid-height viewport: 15% falls between the floor and ceiling.
      tester.view.physicalSize = const Size(400, 400);
      final c2 = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c2, ownsController: true)),
      );
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 60);
      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  testWidgets('fixed-size config reserves the exact height', (tester) async {
    final c = controller(
      config: const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
        kind: BannerKind.fixed,
        fixedSize: FixedBannerSize.mediumRectangle,
      ),
    );
    sdk.alwaysLoadError = const AdFlowError(
      AdFlowErrorKind.loadFailed,
      'never loads',
    );

    await tester.pumpWidget(
      host(AdFlowBanner(controller: c, ownsController: true)),
    );
    expect(tester.getSize(find.byType(AdFlowBanner)).height, 250);

    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('placeholderHeight overrides the reserved estimate', (
    tester,
  ) async {
    sdk.alwaysLoadError = const AdFlowError(
      AdFlowErrorKind.loadFailed,
      'never loads',
    );
    final c = controller();

    await tester.pumpWidget(
      host(
        AdFlowBanner(
          controller: c,
          ownsController: true,
          placeholderHeight: 90,
        ),
      ),
    );
    expect(tester.getSize(find.byType(AdFlowBanner)).height, 90);

    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('unmount with ownsController disposes handle and timers', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(
      host(AdFlowBanner(controller: c, ownsController: true)),
    );
    await tester.pumpAndSettle();
    final handle = sdk.banners.single;

    await tester.pumpWidget(host(const SizedBox()));

    expect(handle.disposed, isTrue);
    // No pending refresh timer — pumpAndSettle would hang/throw otherwise
    // and flutter_test fails the test on leaked timers.
  });

  testWidgets('without ownsController the caller keeps the controller', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(host(AdFlowBanner(controller: c)));
    await tester.pumpAndSettle();
    final handle = sdk.banners.single;

    await tester.pumpWidget(host(const SizedBox()));
    expect(handle.disposed, isFalse);

    c.dispose();
    expect(handle.disposed, isTrue);
  });

  testWidgets('unbounded width (e.g. inside a horizontally-scrolling row) '
      'never loads and stays a placeholder — no crash, no bad ad size', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AdFlowBanner(controller: c, ownsController: true),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // An adaptive banner cannot be sized without a real width — correct
    // behavior is to never call load(), not to guess or crash.
    expect(sdk.banners, isEmpty);
    expect(c.state.value, isA<AdIdle>());

    await tester.pumpWidget(host(const SizedBox()));
  });
}
