import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/config/ad_platform.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/facade/ad_flow.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:ad_flow/src/widgets/ad_flow_native_ad.dart';
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

  NativeAdController controller({NativeConfig? config}) => NativeAdController(
    sdk: sdk,
    gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
    config:
        config ??
        const NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-n'),
          templateKind: NativeTemplateKind.medium,
        ),
    adUnitId: 'unit-n',
  );

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topCenter, child: child),
  );

  testWidgets('reserves the template height and hosts the loaded ad', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(
      host(AdFlowNativeAd(controller: c, ownsController: true)),
    );

    expect(tester.getSize(find.byType(AdFlowNativeAd)).height, 320);

    await tester.pumpAndSettle();
    // The fake native handle renders a SizedBox child once loaded.
    expect(sdk.natives, hasLength(1));
    expect(sdk.natives.single.buildWidgetCalls, greaterThan(0));

    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('placeholderHeight override wins', (tester) async {
    sdk.alwaysLoadError = const AdFlowError(
      AdFlowErrorKind.loadFailed,
      'never loads',
    );
    final c = controller();
    await tester.pumpWidget(
      host(
        AdFlowNativeAd(
          controller: c,
          ownsController: true,
          placeholderHeight: 200,
        ),
      ),
    );
    expect(tester.getSize(find.byType(AdFlowNativeAd)).height, 200);

    await tester.pumpWidget(host(const SizedBox()));
  });

  testWidgets('unmount with ownsController disposes the handle', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(
      host(AdFlowNativeAd(controller: c, ownsController: true)),
    );
    await tester.pumpAndSettle();
    final handle = sdk.natives.single;

    await tester.pumpWidget(host(const SizedBox()));
    expect(handle.disposed, isTrue);
  });

  testWidgets(
    'adopts a different controller passed on rebuild: disposes the old '
    '(when owned) and loads + renders the new one — guards against the '
    'permanent-blank-and-leak that a controller built inside build() '
    'would otherwise cause on every setState',
    (tester) async {
      final c1 = controller();
      await tester.pumpWidget(
        host(AdFlowNativeAd(controller: c1, ownsController: true)),
      );
      await tester.pumpAndSettle();
      expect(sdk.natives, hasLength(1));
      final firstHandle = sdk.natives.single;
      expect(find.byKey(ObjectKey(firstHandle)), findsOneWidget);

      // Rebuild the SAME widget position with a brand-new controller (the
      // anti-pattern of `ads.native()` inside build()).
      final c2 = controller();
      await tester.pumpWidget(
        host(AdFlowNativeAd(controller: c2, ownsController: true)),
      );
      await tester.pumpAndSettle();

      // Old controller disposed (we owned it); new one loaded and rendered.
      expect(firstHandle.disposed, isTrue);
      expect(sdk.natives, hasLength(2));
      expect(sdk.natives.last.disposed, isFalse);
      expect(sdk.natives.last.buildWidgetCalls, greaterThan(0));
      // Hosted under its OWN key, so the plugin's AdWidget is remounted for
      // the new ad rather than updated in place (ADR-047).
      expect(find.byKey(ObjectKey(firstHandle)), findsNothing);
      expect(find.byKey(ObjectKey(sdk.natives.last)), findsOneWidget);

      await tester.pumpWidget(host(const SizedBox()));
    },
  );

  testWidgets('Remove-Ads collapses the native ad to height 0 IMMEDIATELY on '
      'disableAds() (drops its handle) and recovers on enableAds() (5.1.1)', (
    tester,
  ) async {
    final ads = await AdFlow.initialize(
      const AdFlowConfig(
        nativeAd: NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'n-a'),
          templateKind: NativeTemplateKind.medium,
        ),
      ),
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    addTearDown(ads.dispose);
    await ads.whenReady;

    await tester.pumpWidget(host(AdFlowNativeAd(adFlow: ads)));
    await tester.pumpAndSettle();
    expect(sdk.natives, hasLength(1));
    expect(tester.getSize(find.byType(AdFlowNativeAd)).height, 320);
    final firstHandle = sdk.natives.single;

    // Synchronous collapse via the adsEnabled notifier (one frame) — width
    // too: the slot fills its width in every other state.
    ads.disableAds();
    await tester.pump();
    expect(
      tester.getSize(find.byType(AdFlowNativeAd)),
      Size.zero,
      reason: 'collapse must not wait for the async controller recheck',
    );

    // recheckGate drops the handle.
    await tester.pumpAndSettle();
    expect(firstHandle.disposed, isTrue);

    // Recover on re-enable — a fresh load and full-height render.
    ads.enableAds();
    await tester.pumpAndSettle();
    expect(sdk.natives, hasLength(2));
    expect(sdk.natives.last.disposed, isFalse);
    expect(tester.getSize(find.byType(AdFlowNativeAd)).height, 320);

    await tester.pumpWidget(host(const SizedBox()));
  });

  group('the slot is as wide before its ad comes as once it has (5.3.1)', () {
    // The loaded ad is a platform view, and a platform view takes the BIGGEST
    // size its constraints allow: the slot's full width. Under a loose parent
    // (Center, Align, a centred Column, a padded card) a placeholder with no
    // width of its own was 0 wide, so the slot jumped from 0 — or just a
    // card's padding — to full width when the ad came. The fake handle renders
    // a fixed 320x90 box instead of a platform view, so these tests pin the
    // SLOT, which the widget sizes itself in every state.

    Future<void> completeLoad(WidgetTester tester) async {
      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await tester.pumpAndSettle();
    }

    testWidgets('inside a Center: maxWidth x placeholderHeight while the load '
        'is in flight, and the same rect once the ad is in', (tester) async {
      sdk.loadHold = Completer<void>(); // keep the load in flight
      final c = controller();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AdFlowNativeAd(
              controller: c,
              ownsController: true,
              placeholderHeight: 360,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(c.state.value, isA<AdLoading>());
      final before = tester.getRect(find.byType(AdFlowNativeAd));
      expect(before.size, const Size(800, 360));

      await completeLoad(tester);
      expect(c.state.value, isA<AdLoaded>());
      expect(tester.getRect(find.byType(AdFlowNativeAd)), before);
      // The ad is hosted in that whole box, not in a box of its own size.
      expect(tester.getRect(find.byKey(ObjectKey(sdk.natives.single))), before);

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('a padded card in a Center has its full width from the first '
        'frame, not just its padding', (tester) async {
      sdk.loadHold = Completer<void>();
      final c = controller(); // medium template: 320 reserved
      const card = Key('card');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 416),
              child: Padding(
                key: card,
                padding: const EdgeInsets.all(8),
                child: AdFlowNativeAd(controller: c, ownsController: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(c.state.value, isA<AdLoading>());
      final before = tester.getRect(find.byKey(card));
      expect(before.size, const Size(416, 336));
      expect(tester.getSize(find.byType(AdFlowNativeAd)), const Size(400, 320));

      await completeLoad(tester);
      expect(c.state.value, isA<AdLoaded>());
      expect(tester.getRect(find.byKey(card)), before);
      expect(tester.getSize(find.byType(AdFlowNativeAd)), const Size(400, 320));

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('unbounded width (a Row child without Expanded) does not throw '
        'and keeps one box, loading or loaded: the least width it is allowed, '
        'as AdFlowBanner does', (tester) async {
      sdk.loadHold = Completer<void>();
      final c = controller();
      await tester.pumpWidget(
        host(
          Row(children: [AdFlowNativeAd(controller: c, ownsController: true)]),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.state.value, isA<AdLoading>());
      expect(tester.getSize(find.byType(AdFlowNativeAd)), const Size(0, 320));

      await completeLoad(tester);
      expect(tester.takeException(), isNull);
      expect(c.state.value, isA<AdLoaded>());
      expect(tester.getSize(find.byType(AdFlowNativeAd)), const Size(0, 320));

      await tester.pumpWidget(host(const SizedBox()));
    });

    testWidgets('under IntrinsicWidth — what AlertDialog wraps its content in, '
        'so a native ad in an exit dialog — it lays out without error, as '
        'wide as the dialog', (tester) async {
      sdk.loadHold = Completer<void>();
      final c = controller();
      await tester.pumpWidget(
        host(
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The dialog's title, wider than the fake ad's own 320 (a
                // platform view reports no intrinsic width at all).
                const SizedBox(width: 360, height: 40),
                AdFlowNativeAd(controller: c, ownsController: true),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final before = tester.getRect(find.byType(AdFlowNativeAd));
      expect(before.size, const Size(360, 320));

      await completeLoad(tester);
      expect(tester.takeException(), isNull);
      expect(c.state.value, isA<AdLoaded>());
      expect(tester.getRect(find.byType(AdFlowNativeAd)), before);

      await tester.pumpWidget(host(const SizedBox()));
    });
  });
}
