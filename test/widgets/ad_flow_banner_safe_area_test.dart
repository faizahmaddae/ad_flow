import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/config/ad_platform.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/facade/ad_flow.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:ad_flow/src/widgets/ad_flow_banner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// AdFlowBanner(safeArea: true) replaces the bottom-bar idiom every app had to
// get right by hand: a SafeArea around the banner that is itself removed when
// ads are disabled, or Remove-Ads leaves an empty strip the height of the
// home indicator behind.
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()..canRequestAdsResult = true;
    sdk.bannerSize = const AdDimensions(width: 800, height: 100);
  });
  tearDown(() => sdk.dispose());

  // The 800x600 test surface, with optional system insets.
  Widget host(Widget child, {EdgeInsets? padding}) {
    final aligned = Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.bottomCenter, child: child),
    );
    if (padding == null) return aligned; // no MediaQuery at all
    return MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), padding: padding),
      child: aligned,
    );
  }

  Size bannerSize(WidgetTester tester) =>
      tester.getSize(find.byType(AdFlowBanner));

  Future<AdFlow> boot() async {
    final ads = await AdFlow.initialize(
      const AdFlowConfig(
        banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      ),
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    return ads;
  }

  testWidgets('keeps the loaded banner clear of the bottom inset', (
    tester,
  ) async {
    final ads = await boot();
    await tester.pumpWidget(
      host(
        AdFlowBanner(adFlow: ads, safeArea: true),
        padding: const EdgeInsets.only(bottom: 34),
      ),
    );
    await tester.pumpAndSettle();

    expect(bannerSize(tester), const Size(800, 134));
    final ad = tester.getRect(find.byKey(ObjectKey(sdk.banners.single)));
    expect(ad.bottom, 600 - 34, reason: 'the ad sits above the inset');

    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });

  testWidgets('requests the ad at the width left between the side insets', (
    tester,
  ) async {
    sdk.bannerSize = const AdDimensions(width: 712, height: 100);
    final ads = await boot();
    await tester.pumpWidget(
      host(
        AdFlowBanner(adFlow: ads, safeArea: true),
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      sdk.bannerSpecs.single.size,
      isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 712),
      reason: 'a landscape notch must not get an ad wider than its slot',
    );
    expect(bannerSize(tester), const Size(800, 121));

    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });

  testWidgets('Remove-Ads takes the inset away with the banner: zero '
      'footprint, and it all comes back on enableAds()', (tester) async {
    final ads = await boot();
    await tester.pumpWidget(
      host(
        AdFlowBanner(adFlow: ads, safeArea: true),
        padding: const EdgeInsets.only(bottom: 34),
      ),
    );
    await tester.pumpAndSettle();
    expect(bannerSize(tester).height, 134);

    ads.disableAds();
    await tester.pump();
    expect(
      bannerSize(tester).height,
      0,
      reason: 'a SafeArea around the banner would still reserve 34dp here',
    );

    ads.enableAds();
    await tester.pumpAndSettle();
    expect(bannerSize(tester).height, 134);

    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });

  testWidgets('advanced controller mode: AdBlocked(adsDisabled) also '
      'collapses the inset', (tester) async {
    final controller = BannerAdController(
      sdk: sdk,
      gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => false),
      config: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      adUnitId: 'b-a',
      retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
    );
    await tester.pumpWidget(
      host(
        AdFlowBanner(
          controller: controller,
          ownsController: true,
          safeArea: true,
        ),
        padding: const EdgeInsets.only(bottom: 34),
      ),
    );
    await tester.pump();
    expect(
      controller.state.value,
      isA<AdBlocked>().having(
        (s) => s.reason,
        'reason',
        AdBlockReason.adsDisabled,
      ),
    );
    expect(bannerSize(tester).height, 0);
    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('off by default: the banner ignores the insets', (tester) async {
    final ads = await boot();
    await tester.pumpWidget(
      host(
        AdFlowBanner(adFlow: ads),
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 34),
      ),
    );
    await tester.pumpAndSettle();
    expect(bannerSize(tester), const Size(800, 100));
    expect(
      sdk.bannerSpecs.single.size,
      isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 800),
    );
    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });

  testWidgets('no MediaQuery above it: safeArea simply has no inset to '
      'apply, and nothing throws', (tester) async {
    final ads = await boot();
    await tester.pumpWidget(host(AdFlowBanner(adFlow: ads, safeArea: true)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(bannerSize(tester), const Size(800, 100));
    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });

  testWidgets('toggling safeArea on a loaded banner keeps the SAME hosted ad '
      'element (no re-inflation)', (tester) async {
    final ads = await boot();
    Widget banner({required bool safeArea}) => host(
      AdFlowBanner(adFlow: ads, safeArea: safeArea),
      padding: const EdgeInsets.only(bottom: 34),
    );
    await tester.pumpWidget(banner(safeArea: false));
    await tester.pumpAndSettle();
    final live = sdk.banners.single;
    final before = tester.element(find.byKey(ObjectKey(live)));

    await tester.pumpWidget(banner(safeArea: true));
    await tester.pumpAndSettle();
    expect(bannerSize(tester).height, 134);
    expect(
      identical(tester.element(find.byKey(ObjectKey(live))), before),
      isTrue,
    );

    await tester.pumpWidget(banner(safeArea: false));
    await tester.pumpAndSettle();
    expect(bannerSize(tester).height, 100);
    expect(
      identical(tester.element(find.byKey(ObjectKey(live))), before),
      isTrue,
    );
    expect(sdk.banners, hasLength(1), reason: 'no reload either');

    await tester.pumpWidget(host(const SizedBox()));
    ads.dispose();
  });
}
