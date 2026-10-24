import 'dart:async';

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
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// ADR-079. Since google_mobile_ads 9.2.0 an anchored adaptive banner renders
// at Google's LARGE size (ADR-078) — about 100–150dp on a phone — but nothing
// can know that height before the first ad has loaded, so a fresh slot
// reserves the 50dp floor and grows. These tests pin that the jump happens
// once per width, not once per screen: later banners of the same width
// reserve the height an earlier one rendered at.
void main() {
  group('BannerHeightMemory', () {
    test('remembers per width, latest wins, ignores non-positive heights', () {
      final memory = BannerHeightMemory();
      expect(memory.heightFor(400), isNull);

      memory.remember(400, 133);
      memory.remember(600, 0);
      memory.remember(700, -1);
      expect(memory.heightFor(400), 133);
      expect(memory.heightFor(600), isNull);
      expect(memory.heightFor(700), isNull);

      memory.remember(400, 128);
      expect(memory.heightFor(400), 128);
    });
  });

  group('BannerAdController.reservedHeight', () {
    late FakeAdSdk sdk;

    setUp(() => sdk = FakeAdSdk()..canRequestAdsResult = true);
    tearDown(() => sdk.dispose());

    BannerAdController controller({
      BannerConfig config = const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
      ),
      BannerHeightMemory? memory,
      bool Function()? isEnabled,
    }) => BannerAdController(
      sdk: sdk,
      gate: AdGate(
        canRequestAds: sdk.canRequestAds,
        isEnabled: isEnabled ?? () => true,
      ),
      config: config,
      adUnitId: 'unit-b',
      retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
      heightMemory: memory,
    );

    test('a banner reserves the height an earlier banner of its width '
        'rendered at; other widths keep the floor', () async {
      final memory = BannerHeightMemory();
      sdk.bannerSize = const AdDimensions(width: 400, height: 133);

      final first = controller(memory: memory);
      expect(first.reservedHeight, 50, reason: 'nothing has loaded yet');
      await first.load(width: 400);
      expect(first.state.value, isA<AdLoaded>());
      first.dispose();

      final hold = Completer<void>();
      sdk.loadHold = hold;
      final second = controller(memory: memory);
      unawaited(second.load(width: 400));
      expect(
        second.reservedHeight,
        133,
        reason: 'the first banner taught the height: no 50 → 133 jump',
      );
      final other = controller(memory: memory);
      unawaited(other.load(width: 600));
      expect(
        other.reservedHeight,
        50,
        reason: 'nothing has rendered at 600 yet',
      );

      hold.complete();
      await pumpEventQueue();
      second.dispose();
      other.dispose();
    });

    test('without a shared memory a controller still remembers its own ad '
        'after it is dropped (the slot keeps its real height)', () async {
      sdk.bannerSize = const AdDimensions(width: 400, height: 133);
      final c = controller();
      await c.load(width: 400);
      expect(c.state.value, isA<AdLoaded>());

      sdk.canRequestAdsResult = false; // consent no longer permits ads
      await c.recheckGate();
      expect(
        c.state.value,
        isA<AdBlocked>().having(
          (s) => s.reason,
          'reason',
          AdBlockReason.consentNotGranted,
        ),
      );
      expect(c.handle, isNull, reason: 'the ad was dropped');
      expect(c.reservedHeight, 133);
      c.dispose();
    });

    test('fixed and inline adaptive slots neither read nor teach it', () async {
      final memory = BannerHeightMemory()..remember(400, 133);

      final fixed = controller(
        memory: memory,
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          kind: BannerKind.fixed,
          fixedSize: FixedBannerSize.mediumRectangle,
        ),
      );
      unawaited(fixed.load(width: 400));
      expect(fixed.reservedHeight, 250, reason: 'a fixed size is exact');
      await pumpEventQueue();
      fixed.dispose();

      sdk.bannerSize = const AdDimensions(width: 400, height: 90);
      final inline = controller(
        memory: memory,
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          kind: BannerKind.inlineAdaptive,
        ),
      );
      unawaited(inline.load(width: 400));
      expect(inline.reservedHeight, 50);
      await pumpEventQueue();
      expect(inline.state.value, isA<AdLoaded>());
      expect(
        memory.heightFor(400),
        133,
        reason:
            'an inline height varies per creative — remembering it would '
            'be a guess (ADR-070)',
      );
      inline.dispose();
    });

    test('a client-side refresh that swaps in a different size updates it', () {
      fakeAsync((async) {
        final memory = BannerHeightMemory();
        sdk.bannerSize = const AdDimensions(width: 400, height: 133);
        final c = controller(
          memory: memory,
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
            minRefresh: Duration(seconds: 60),
          ),
        );
        unawaited(c.load(width: 400));
        async.flushMicrotasks();
        expect(memory.heightFor(400), 133);

        sdk.bannerSize = const AdDimensions(width: 400, height: 120);
        async.elapse(const Duration(seconds: 61));
        expect(sdk.banners, hasLength(2), reason: 'the refresh swapped');
        expect(memory.heightFor(400), 120);
        c.dispose();
      });
    });
  });

  group('AdFlowBanner(adFlow:) across screens', () {
    late FakeAdSdk sdk;

    setUp(() => sdk = FakeAdSdk()..canRequestAdsResult = true);
    tearDown(() => sdk.dispose());

    Widget host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topCenter, child: child),
    );

    double bannerHeight(WidgetTester tester) =>
        tester.getSize(find.byType(AdFlowBanner)).height;

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

    testWidgets('the banner on the next screen starts at the height the '
        'previous one rendered at, and its ad lands without a shift', (
      tester,
    ) async {
      // The 800-wide test surface; a large anchored banner of that width.
      sdk.bannerSize = const AdDimensions(width: 800, height: 133);
      final ads = await boot();

      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
      expect(bannerHeight(tester), 50, reason: 'first banner: the floor');
      await tester.pumpAndSettle();
      expect(bannerHeight(tester), 133);

      // Navigate away, then to a screen with its own banner: a new widget, a
      // new controller, a new load.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();
      final hold = Completer<void>();
      sdk.loadHold = hold;
      await tester.pumpWidget(host(AdFlowBanner(adFlow: ads)));
      await tester.pump();
      expect(
        bannerHeight(tester),
        133,
        reason: 'reserved before its own ad has arrived',
      );

      hold.complete();
      await tester.pumpAndSettle();
      expect(sdk.banners, hasLength(2));
      expect(bannerHeight(tester), 133, reason: 'the ad fills the same box');

      await tester.pumpWidget(host(const SizedBox()));
      ads.dispose();
    });

    testWidgets('a re-initialized AdFlow starts from the floor again (the '
        'memory belongs to one graph)', (tester) async {
      sdk.bannerSize = const AdDimensions(width: 800, height: 133);
      final first = await boot();
      await tester.pumpWidget(host(AdFlowBanner(adFlow: first)));
      await tester.pumpAndSettle();
      expect(bannerHeight(tester), 133);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpAndSettle();

      final second = await boot(); // disposes `first` (ADR-044)
      final hold = Completer<void>();
      sdk.loadHold = hold;
      await tester.pumpWidget(host(AdFlowBanner(adFlow: second)));
      await tester.pump();
      expect(bannerHeight(tester), 50);

      hold.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(const SizedBox()));
      second.dispose();
    });
  });
}
