import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/config/ad_platform.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/facade/ad_flow.dart';
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
    gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
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

    // First frame: placeholder reserved BEFORE any load. A large anchored
    // adaptive banner has no pure-width height formula (Google docs: 50–150dp),
    // so the widget reserves the documented 50dp FLOOR — not a speculative
    // upper estimate — and the loaded ad then grows the box to its exact
    // dimensions (5.1.1). The old 15%-of-device-height / 50–90dp estimate is
    // gone.
    final placeholder = tester.getSize(find.byType(AdFlowBanner));
    expect(placeholder.height, 50);

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
    'large anchored adaptive reserves the documented 50dp FLOOR before load, '
    'independent of device height (no 15%/50–90dp estimate — 5.1.1)',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;
      // The old behaviour scaled with device height; a tall viewport used to
      // push this to the 90dp ceiling. It must now be a flat 50dp floor.
      tester.view.physicalSize = const Size(400, 4000);
      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'never loads',
      );
      final c = controller(); // anchoredAdaptive by default
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(AdFlowBanner)).height,
        50,
        reason: 'anchored adaptive pre-load reservation is the 50dp floor',
      );
      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  testWidgets(
    'a loaded anchored adaptive banner larger than the 50dp floor uses its '
    'EXACT resolved height (60/90/100/150…), not the placeholder',
    (tester) async {
      sdk.bannerSize = const AdDimensions(width: 320, height: 100);
      final c = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      // Pre-load: the 50dp floor.
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 50);
      await tester.pumpAndSettle();
      // Loaded: the exact live dimensions, well above the floor.
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 100);
      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  testWidgets(
    'inline adaptive reserves ZERO before load (its real height is unknown '
    'until onAdLoaded) — but an explicit placeholderHeight still reserves',
    (tester) async {
      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'never loads',
      );
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          kind: BannerKind.inlineAdaptive,
          maxInlineHeight: 200,
        ),
      );
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(AdFlowBanner)).height,
        0,
        reason: 'inline adaptive default pre-load reservation is zero',
      );
      await tester.pumpWidget(host(const SizedBox()));

      // An explicit publisher-chosen height is still honoured for inline.
      final c2 = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          kind: BannerKind.inlineAdaptive,
          maxInlineHeight: 200,
        ),
      );
      await tester.pumpWidget(
        host(
          AdFlowBanner(
            controller: c2,
            ownsController: true,
            placeholderHeight: 120,
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 120);
      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  testWidgets(
    'placeholderHeight: 0 opts into fully-collapsed pre-load behaviour',
    (tester) async {
      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'never loads',
      );
      final c = controller(); // anchored — would otherwise reserve 50
      await tester.pumpWidget(
        host(
          AdFlowBanner(
            controller: c,
            ownsController: true,
            placeholderHeight: 0,
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 0);
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

  testWidgets(
    'adopts a different controller passed on rebuild: disposes the old '
    '(when owned) and re-requests the load for the new one',
    (tester) async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      final c1 = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c1, ownsController: true)),
      );
      await tester.pumpAndSettle();
      expect(sdk.banners, hasLength(1));
      final firstHandle = sdk.banners.single;

      // Rebuild the same widget position with a brand-new controller (the
      // anti-pattern of `ads.banner()` inside build()).
      final c2 = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c2, ownsController: true)),
      );
      await tester.pumpAndSettle();

      // Old controller disposed (we owned it); new one loaded.
      expect(firstHandle.disposed, isTrue);
      expect(sdk.banners, hasLength(2));
      expect(sdk.banners.last.disposed, isFalse);

      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  group('orientation / fold: an adaptive banner must follow the width', () {
    // An anchored adaptive banner is requested FOR a specific width. Rotate to
    // landscape and that width roughly doubles: an ad still sized for portrait
    // sits letterboxed in the slot — poor viewability, lost revenue, and the
    // wrong creative size for every subsequent refresh too, because the
    // controller cached the stale width. Google's own guidance is to reload the
    // adaptive banner when the orientation changes.

    testWidgets('rotating reloads the banner at the new width', (tester) async {
      final c = controller();

      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 400,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AdFlowBanner(controller: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        sdk.bannerSpecs.single.size,
        isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 400),
      );

      // Rotate: the same placement is now 800 logical px wide.
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 800,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AdFlowBanner(controller: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        sdk.bannerSpecs,
        hasLength(2),
        reason: 'the banner must be re-requested at the new width on rotation',
      );
      expect(
        sdk.bannerSpecs.last.size,
        isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 800),
      );
      expect(
        sdk.banners.first.disposed,
        isTrue,
        reason: 'the stale-width ad must be released, not leaked',
      );
      c.dispose();
    });

    testWidgets('a rebuild at the SAME width does not re-request (that would '
        'be an ad-request storm / invalid traffic)', (tester) async {
      final c = controller();

      Widget host() => Center(
        child: SizedBox(
          width: 400,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AdFlowBanner(controller: c),
          ),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.pumpWidget(host());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(sdk.bannerSpecs, hasLength(1));
      c.dispose();
    });

    testWidgets('a FIXED-size banner ignores width changes (its size is not '
        'width-derived)', (tester) async {
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          kind: BannerKind.fixed,
        ),
      );

      Widget host(double width) => Center(
        child: SizedBox(
          width: width,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AdFlowBanner(controller: c),
          ),
        ),
      );

      await tester.pumpWidget(host(400));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(800));
      await tester.pumpAndSettle();

      expect(sdk.bannerSpecs, hasLength(1));
      c.dispose();
    });
  });

  testWidgets(
    'a refresh swap REMOUNTS the hosted ad subtree (keyed by handle identity)',
    (tester) async {
      // The plugin's AdWidget has no didUpdateWidget: its platform view
      // captures the ad id at creation, and the framework never recreates a
      // platform view whose viewType is unchanged. So on a handle swap the
      // subtree MUST be unmounted and remounted (a fresh element), or the
      // screen keeps hosting the platform view of the old, disposed ad — a
      // permanently dead slot. Platform-view identity itself is not
      // observable in a widget test; keying the subtree by handle identity is
      // the mechanism that forces the remount, so that is what this pins.
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          minRefresh: Duration(seconds: 60),
        ),
      );
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      await tester.pumpAndSettle();

      final first = sdk.banners.single;
      expect(find.byKey(ObjectKey(first)), findsOneWidget);

      // Fire the opt-in client-side refresh: the controller swaps handles
      // while state stays AdLoaded (only `revision` bumps).
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(sdk.banners, hasLength(2));
      final second = sdk.banners.last;
      expect(
        find.byKey(ObjectKey(second)),
        findsOneWidget,
        reason: 'the NEW handle must be mounted under its own element',
      );
      expect(
        find.byKey(ObjectKey(first)),
        findsNothing,
        reason: 'the old, disposed handle must be fully unmounted',
      );
    },
  );

  testWidgets(
    'the hosted box follows a live size change (server-side auto-refresh of '
    'an inline adaptive banner can resolve a different height)',
    (tester) async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 100);
      final c = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 100);

      // The SAME handle resolves a new creative height on the platform side.
      (sdk.banners.single).simulateResize(
        const AdDimensions(width: 360, height: 150),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(AdFlowBanner)).height,
        150,
        reason:
            'without following handle.dimensions the new creative renders '
            'clipped in the old box',
      );
    },
  );

  group('widget-first creation (3.0)', () {
    testWidgets('AdFlowBanner(adFlow:) creates, loads, hosts and DISPOSES its '
        'own controller — the build()-minted-controller footgun is '
        'unrepresentable', (tester) async {
      final ads = await AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady;

      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
      await tester.pumpAndSettle();

      expect(sdk.banners, hasLength(1));
      final live = sdk.banners.single;
      expect(find.byKey(ObjectKey(live)), findsOneWidget);

      // Rebuilding with the SAME AdFlow must not mint a new controller/load.
      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
      await tester.pumpAndSettle();
      expect(sdk.banners, hasLength(1));

      // Unmount disposes the self-created controller and its ad.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();
      expect(live.disposed, isTrue);
      ads.dispose();
    });

    testWidgets('an EQUAL-but-not-identical inline config on rebuild must '
        'not re-mint the controller (value equality, not identity)', (
      tester,
    ) async {
      final ads = await AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady;

      // Deliberately NON-const, so each build produces a new instance — the
      // realistic shape of `config: BannerConfig(...)` inline in build().
      // ignore: prefer_const_constructors
      BannerConfig makeConfig() => BannerConfig(
        // ignore: prefer_const_constructors
        adUnitId: PlatformAdUnitId(android: 'override'),
      );
      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: ads, config: makeConfig())),
      );
      await tester.pumpAndSettle();
      expect(sdk.banners, hasLength(1));

      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: ads, config: makeConfig())),
      );
      await tester.pumpAndSettle();

      expect(
        sdk.banners,
        hasLength(1),
        reason:
            'identity comparison would re-mint the controller (and '
            're-request an ad) on EVERY rebuild — the exact footgun '
            'widget-first mode exists to remove',
      );
      await tester.pumpWidget(host(const SizedBox()));
      ads.dispose();
    });
  });

  testWidgets('an adopted controller swap remounts the native ad subtree too', (
    tester,
  ) async {
    // Same mechanism as the banner remount test, for AdFlowNativeAd's
    // didUpdateWidget adoption path (ADR-029).
    final c1 = controller();
    await tester.pumpWidget(
      host(AdFlowBanner(controller: c1, ownsController: true)),
    );
    await tester.pumpAndSettle();
    final firstHandle = sdk.banners.single;
    expect(find.byKey(ObjectKey(firstHandle)), findsOneWidget);

    final c2 = controller();
    await tester.pumpWidget(
      host(AdFlowBanner(controller: c2, ownsController: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ObjectKey(firstHandle)), findsNothing);
    expect(find.byKey(ObjectKey(sdk.banners.last)), findsOneWidget);
  });

  group('Remove-Ads collapses the banner to a zero footprint (5.1.1)', () {
    Future<AdFlow> initBannerAdFlow() async {
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

    testWidgets(
      'a loaded banner collapses to height 0 IMMEDIATELY on disableAds(), '
      'drops its handle, and reloads on enableAds()',
      (tester) async {
        sdk.bannerSize = const AdDimensions(width: 360, height: 60);
        final ads = await initBannerAdFlow();
        addTearDown(ads.dispose);

        await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
        await tester.pumpAndSettle();
        expect(sdk.banners, hasLength(1));
        expect(tester.getSize(find.byType(AdFlowBanner)).height, 60);
        final firstHandle = sdk.banners.single;

        // Collapse must be SYNCHRONOUS — a single frame, driven by the
        // adsEnabled notifier, NOT waiting for the async recheckGate() that
        // later drops the handle.
        ads.disableAds();
        await tester.pump();
        expect(
          tester.getSize(find.byType(AdFlowBanner)).height,
          0,
          reason: 'collapse must not wait for the async controller recheck',
        );

        // The handle is still dropped/disposed correctly by recheckGate.
        await tester.pumpAndSettle();
        expect(firstHandle.disposed, isTrue);

        // Re-enable → a valid load/render path again, exactly one new request.
        ads.enableAds();
        await tester.pumpAndSettle();
        expect(
          sdk.banners,
          hasLength(2),
          reason: 'exactly one reload on re-enable, not a request storm',
        );
        expect(sdk.banners.last.disposed, isFalse);
        expect(tester.getSize(find.byType(AdFlowBanner)).height, 60);

        await tester.pumpWidget(host(const SizedBox()));
      },
    );

    testWidgets(
      'rebuilds and adsEnabled toggles never create duplicate banner requests',
      (tester) async {
        final ads = await initBannerAdFlow();
        addTearDown(ads.dispose);

        await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
        await tester.pumpAndSettle();
        expect(sdk.bannerSpecs, hasLength(1));

        // Plain rebuilds with the same AdFlow must not re-request.
        for (var i = 0; i < 5; i++) {
          await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
          await tester.pump();
        }
        expect(sdk.bannerSpecs, hasLength(1));

        // Disable then re-enable → exactly ONE additional request (the reload).
        ads.disableAds();
        await tester.pumpAndSettle();
        ads.enableAds();
        await tester.pumpAndSettle();
        expect(sdk.bannerSpecs, hasLength(2));

        // More rebuilds while enabled — still no extra request.
        await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
        await tester.pumpAndSettle();
        expect(sdk.bannerSpecs, hasLength(2));

        await tester.pumpWidget(host(const SizedBox()));
      },
    );

    testWidgets(
      'adsDisabled overrides a non-zero placeholderHeight (advanced controller '
      'mode) → AdBlocked(adsDisabled) forces zero footprint',
      (tester) async {
        var enabled = true;
        final c = BannerAdController(
          sdk: sdk,
          gate: AdGate(
            canRequestAds: sdk.canRequestAds,
            isEnabled: () => enabled,
          ),
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
          ),
          adUnitId: 'unit-b',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'never loads',
        );

        await tester.pumpWidget(
          host(
            AdFlowBanner(
              controller: c,
              ownsController: true,
              placeholderHeight: 200,
            ),
          ),
        );
        await tester.pump();
        // While enabled and unloaded, the explicit placeholder is honoured.
        expect(tester.getSize(find.byType(AdFlowBanner)).height, 200);

        // Disable and re-check: the controller lands on AdBlocked(adsDisabled),
        // and the widget must collapse regardless of placeholderHeight.
        enabled = false;
        await c.recheckGate();
        await tester.pump();
        expect(c.state.value, isA<AdBlocked>());
        expect((c.state.value as AdBlocked).reason, AdBlockReason.adsDisabled);
        expect(
          tester.getSize(find.byType(AdFlowBanner)).height,
          0,
          reason:
              'adsDisabled must override placeholderHeight — zero footprint',
        );

        await tester.pumpWidget(host(const SizedBox()));
      },
    );
  });

  // A zero-width slot resolves to a VALID adaptive AdSize natively
  // (`AdSize(0, 100)`, not `AdSize.INVALID`), so nothing downstream refuses
  // it: before this guard a 0-width parent dispatched a real request, landed
  // AdLoaded, and rendered a BILLABLE ad in a Size(0, 50) box — an impression
  // the user can never see. Same rule the seam already applies to a
  // zero-height inline adaptive banner.
  group('a slot with no usable width never requests an ad (ADR-073)', () {
    testWidgets('zero width dispatches nothing', (tester) async {
      final c = controller();
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 0,
            child: AdFlowBanner(controller: c, ownsController: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sdk.bannerSpecs, isEmpty);
      expect(c.state.value, isA<AdIdle>());
      expect(c.handle, isNull);

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('a slot that GAINS a width then loads exactly once', (
      tester,
    ) async {
      sdk.bannerSize = const AdDimensions(width: 400, height: 60);
      final c = controller();
      Widget at(double w) => host(
        SizedBox(
          width: w,
          child: AdFlowBanner(controller: c, ownsController: true),
        ),
      );

      await tester.pumpWidget(at(0));
      await tester.pumpAndSettle();
      expect(sdk.bannerSpecs, isEmpty);

      // The collapsed panel opens.
      await tester.pumpWidget(at(400));
      await tester.pumpAndSettle();
      expect(sdk.bannerSpecs, hasLength(1));
      expect(
        sdk.bannerSpecs.single.size,
        isA<AnchoredAdaptiveSizeSpec>().having((s) => s.width, 'width', 400),
      );

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('shrinking to zero and back does NOT re-request', (
      tester,
    ) async {
      sdk.bannerSize = const AdDimensions(width: 400, height: 60);
      final c = controller();
      Widget at(double w) => host(
        SizedBox(
          width: w,
          child: AdFlowBanner(controller: c, ownsController: true),
        ),
      );

      await tester.pumpWidget(at(400));
      await tester.pumpAndSettle();
      expect(sdk.bannerSpecs, hasLength(1));

      await tester.pumpWidget(at(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(at(400));
      await tester.pumpAndSettle();

      expect(
        sdk.bannerSpecs,
        hasLength(1),
        reason: 'a collapse/expand cycle at the same width is not a resize',
      );

      await tester.pumpWidget(host(const SizedBox()));
    });
  });

  // ADR-073 / issue #15. An adaptive slot is anchored to its WIDTH, so a
  // creative smaller than the slot is centred by the SDK and the surround is
  // left unpainted — the app's own surface shows through and the ad reads as a
  // rendering glitch. Google's anchored-adaptive guidance is an opaque ad-view
  // background; the package had no way to supply one.
  group('backgroundColor paints behind the slot (ADR-073)', () {
    const color = Color(0xFF123456);

    ColoredBox? paintedBox(WidgetTester tester) {
      final found = find.descendant(
        of: find.byType(AdFlowBanner),
        matching: find.byType(ColoredBox),
      );
      return found.evaluate().isEmpty
          ? null
          : tester.widget<ColoredBox>(found.first);
    }

    testWidgets('no colour by default — not one extra layer', (tester) async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      final c = controller();
      await tester.pumpWidget(
        host(AdFlowBanner(controller: c, ownsController: true)),
      );
      await tester.pumpAndSettle();

      expect(paintedBox(tester), isNull);
      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('paints behind the loaded ad AND the pre-load placeholder', (
      tester,
    ) async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      final c = controller();
      await tester.pumpWidget(
        host(
          AdFlowBanner(
            controller: c,
            ownsController: true,
            backgroundColor: color,
          ),
        ),
      );

      // Reserved-but-not-loaded frame.
      expect(paintedBox(tester)?.color, color);
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 50);

      await tester.pumpAndSettle();

      // Loaded frame: still painted, and the box is still exactly the ad size
      // — the colour must not add height of its own.
      expect(paintedBox(tester)?.color, color);
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 60);
      expect(tester.getSize(find.byType(AdFlowBanner)).width, 360);

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('paints strictly UNDER the ad, never over it (occluding a '
        'creative is a policy violation)', (tester) async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      final c = controller();
      await tester.pumpWidget(
        host(
          AdFlowBanner(
            controller: c,
            ownsController: true,
            backgroundColor: color,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The ad subtree must be a DESCENDANT of the ColoredBox: a ColoredBox
      // paints itself first, then its child, so the ad is on top. A sibling in
      // a Stack (or any ancestor of the ColoredBox) would paint over the ad.
      final adSubtree = find.descendant(
        of: find.byType(AdFlowBanner),
        matching: find.byType(KeyedSubtree),
      );
      expect(adSubtree, findsOneWidget);
      expect(
        find.ancestor(of: adSubtree, matching: find.byType(ColoredBox)),
        findsOneWidget,
        reason: 'the ad must render on top of the background, not under it',
      );
      expect(
        find.descendant(
          of: find.byType(AdFlowBanner),
          matching: find.byType(Stack),
        ),
        findsNothing,
        reason: 'no overlay layer may exist above a creative',
      );

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('Remove-Ads still reclaims the WHOLE placement — a disabled '
        'banner paints nothing at all', (tester) async {
      final ads = await AdFlow.initialize(
        const AdFlowConfig(
          banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      addTearDown(ads.dispose);
      await ads.whenReady;

      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      await tester.pumpWidget(
        host(AdFlowBanner(adFlow: ads, backgroundColor: color)),
      );
      await tester.pumpAndSettle();
      expect(paintedBox(tester)?.color, color);

      ads.disableAds();
      await tester.pump();
      expect(tester.getSize(find.byType(AdFlowBanner)).height, 0);
      expect(
        paintedBox(tester),
        isNull,
        reason:
            'a Remove-Ads banner must leave no coloured strip behind — the '
            'background is part of the ad slot, not the app chrome',
      );

      await tester.pumpWidget(host(const SizedBox()));
    });
  });
}
