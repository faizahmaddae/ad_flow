import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A widget-first placement whose slot is not configured for the running
/// platform renders nothing (ADR-085) — the way the nullable full-screen
/// getters do — instead of failing its build with an `AdFlowError`, which was
/// a red screen in debug and a grey box in release. A debug build prints why.
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot(AdFlowConfig config) async {
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.ios,
    );
    await ads.whenReady;
    return ads;
  }

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topCenter, child: child),
  );

  /// Runs [body] with `debugPrint` captured, restoring it before the test
  /// ends (the binding checks it was put back).
  Future<List<String>> printsDuring(Future<void> Function() body) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = original;
    }
    return printed;
  }

  testWidgets('AdFlowBanner renders nothing where its slot has no ID for the '
      'platform, and a debug build says why', (tester) async {
    // Android-only banner, running on iOS, test ads automatic (debug).
    final ads = await boot(
      const AdFlowConfig(
        banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      ),
    );

    final printed = await printsDuring(() async {
      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads, safeArea: true)));
      await tester.pumpAndSettle();
    });

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AdFlowBanner)), Size.zero);
    expect(sdk.banners, isEmpty, reason: 'nothing may be requested');
    expect(
      printed,
      anyElement(
        allOf(contains('AdFlowBanner renders nothing'), contains('ios')),
      ),
    );

    // The factory itself still refuses: a direct call is a programming error.
    expect(
      ads.banner,
      throwsA(
        isA<AdFlowError>().having(
          (e) => e.kind,
          'kind',
          AdFlowErrorKind.invalidConfig,
        ),
      ),
    );
    ads.dispose();
  });

  testWidgets('AdFlowBanner renders nothing without any banner config', (
    tester,
  ) async {
    final ads = await boot(const AdFlowConfig(testMode: false));

    await printsDuring(() async {
      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
      await tester.pumpAndSettle();
    });

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AdFlowBanner)), Size.zero);
    ads.dispose();
  });

  testWidgets('AdFlowNativeAd renders nothing where its slot has no ID for '
      'the platform', (tester) async {
    final ads = await boot(
      const AdFlowConfig(
        testMode: false,
        nativeAd: NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'n-a'),
          templateKind: NativeTemplateKind.medium,
        ),
      ),
    );

    final printed = await printsDuring(() async {
      await tester.pumpWidget(host(AdFlowNativeAd(adFlow: ads)));
      await tester.pumpAndSettle();
    });

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AdFlowNativeAd)), Size.zero);
    expect(sdk.natives, isEmpty, reason: 'nothing may be requested');
    expect(printed, anyElement(contains('AdFlowNativeAd renders nothing')));
    ads.dispose();
  });

  testWidgets('an ID-less per-placement config renders nothing in debug too '
      '— debug and release agree; only testMode: true makes it a placeholder', (
    tester,
  ) async {
    const idLess = BannerConfig(adUnitId: PlatformAdUnitId());
    // The automatic default (debug → test ads): the same checks as the
    // global config, so no sample ad in debug that release would not show.
    final auto = await boot(const AdFlowConfig());
    final printed = await printsDuring(() async {
      await tester.pumpWidget(host(AdFlowBanner(adFlow: auto, config: idLess)));
      await tester.pumpAndSettle();
    });
    expect(sdk.banners, isEmpty);
    expect(tester.getSize(find.byType(AdFlowBanner)), Size.zero);
    expect(printed, anyElement(contains('has no platform IDs')));
    await tester.pumpWidget(host(const SizedBox()));
    auto.dispose();

    // An explicit testMode: true: the documented placeholder.
    final explicit = await boot(const AdFlowConfig(testMode: true));
    await printsDuring(() async {
      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: explicit, config: idLess)),
      );
      await tester.pumpAndSettle();
    });
    expect(sdk.bannerSpecs.single.adUnitId, TestAdUnitIds.banner.ios);
    await tester.pumpWidget(host(const SizedBox()));
    explicit.dispose();
  });

  test('a per-placement config gets the global checks: an empty-string ID '
      'is refused by ads.banner() / ads.native()', () async {
    final ads = await boot(const AdFlowConfig());
    final invalid = isA<AdFlowError>().having(
      (e) => e.kind,
      'kind',
      AdFlowErrorKind.invalidConfig,
    );
    expect(
      () =>
          ads.banner(const BannerConfig(adUnitId: PlatformAdUnitId(ios: ' '))),
      throwsA(invalid),
    );
    expect(
      () => ads.native(
        const NativeConfig(
          adUnitId: PlatformAdUnitId(ios: ''),
          templateKind: NativeTemplateKind.small,
        ),
      ),
      throwsA(invalid),
    );
    ads.dispose();
  });

  testWidgets('a placement whose config gains an ID for this platform mounts '
      'and loads; losing it again drops the ad', (tester) async {
    final ads = await boot(const AdFlowConfig(testMode: false));
    const androidOnly = BannerConfig(
      adUnitId: PlatformAdUnitId(android: 'b-a'),
    );
    const both = BannerConfig(
      adUnitId: PlatformAdUnitId(android: 'b-a', ios: 'b-i'),
    );

    await printsDuring(() async {
      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: ads, config: androidOnly)),
      );
      await tester.pumpAndSettle();
      expect(sdk.banners, isEmpty);

      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads, config: both)));
      await tester.pumpAndSettle();
      expect(sdk.banners, hasLength(1));
      expect(sdk.bannerSpecs.single.adUnitId, 'b-i');
      final live = sdk.banners.single;

      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: ads, config: androidOnly)),
      );
      await tester.pumpAndSettle();
      expect(live.disposed, isTrue, reason: 'the owned controller is dropped');
      expect(tester.getSize(find.byType(AdFlowBanner)), Size.zero);
    });

    expect(tester.takeException(), isNull);
    ads.dispose();
  });
}
