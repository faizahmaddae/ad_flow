import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:ad_flow_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// E12: Remove-Ads must remove the COMPLETE ad surfaces in the example — not
// just blank the ads. The banner's SafeArea bar and the native ad's decorated
// Card (title, padding, border) are conditionally hidden, so a disabled state
// leaves no empty inset bar and no blank bordered card behind.
void main() {
  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> initAds() async {
    final ads = await AdFlow.initialize(
      AdFlowConfig.test(),
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
      // test() configures the rewarded interstitial, whose intro is mandatory.
      rewardedIntroPresenter: (_) async => false,
    );
    await ads.whenReady;
    return ads;
  }

  testWidgets(
    'disabling ads removes the whole banner + native surfaces; the Remove-Ads '
    'switch stays accessible; re-enabling brings both back',
    (tester) async {
      final ads = await initAds();

      // A tall viewport so the whole scrolling body (including the native Card
      // near the bottom) is built — a ListView otherwise lazily skips
      // off-screen children and the native widget would never mount.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 3000);

      await tester.pumpWidget(MaterialApp(home: HomeScreen(ads: ads)));
      await tester.pumpAndSettle();

      // Enabled: both surfaces present.
      expect(find.byType(AdFlowBanner), findsOneWidget);
      expect(find.byType(AdFlowNativeAd), findsOneWidget);
      expect(find.text('Native (medium template)'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Disable via the real facade toggle the switch drives.
      ads.disableAds();
      await tester.pumpAndSettle();

      // The COMPLETE surfaces are gone — banner (and its SafeArea bar), native
      // widget, and the native Card's title/decoration.
      expect(find.byType(AdFlowBanner), findsNothing);
      expect(find.byType(AdFlowNativeAd), findsNothing);
      expect(find.text('Native (medium template)'), findsNothing);
      // The Remove-Ads switch remains accessible so ads can be re-enabled.
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Re-enable: both placements reconstruct.
      ads.enableAds();
      await tester.pumpAndSettle();
      expect(find.byType(AdFlowBanner), findsOneWidget);
      expect(find.byType(AdFlowNativeAd), findsOneWidget);
      expect(find.text('Native (medium template)'), findsOneWidget);

      // Tear the tree down and dispose in-body (not via addTearDown, which runs
      // AFTER the pending-timer invariant check): disposing cancels the
      // full-screen formats' expiry timers armed by the preloads.
      await tester.pumpWidget(const SizedBox());
      ads.dispose();
      // The fake full-screen handles defer their stream-close by one
      // microtask/zero-duration timer; settle so none is left pending.
      await tester.pumpAndSettle();
    },
  );
}
