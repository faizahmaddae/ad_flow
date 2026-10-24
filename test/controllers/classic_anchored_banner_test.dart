import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/config/ad_platform.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
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

// ADR-081. `BannerConfig.anchoredSize` opts a placement into the classic
// anchored adaptive banner (full width, ~60dp) instead of Google's large one;
// the default stays large. These tests pin that the choice reaches every
// request the slot makes, and that the large and classic heights are
// remembered apart (ADR-079).
void main() {
  late FakeAdSdk sdk;

  setUp(() => sdk = FakeAdSdk()..canRequestAdsResult = true);
  tearDown(() => sdk.dispose());

  const classic = BannerConfig(
    adUnitId: PlatformAdUnitId(android: 'unit-b'),
    anchoredSize: AnchoredBannerSize.classic,
  );

  BannerAdController controller({
    BannerConfig config = const BannerConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-b'),
    ),
    BannerHeightMemory? memory,
  }) => BannerAdController(
    sdk: sdk,
    gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
    config: config,
    adUnitId: 'unit-b',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
    heightMemory: memory,
  );

  AnchoredBannerSize requested(int i) =>
      (sdk.bannerSpecs[i].size as AnchoredAdaptiveSizeSpec).size;

  test('large stays the default — in the config and on the request', () async {
    expect(
      const BannerConfig(adUnitId: PlatformAdUnitId(android: 'u')).anchoredSize,
      AnchoredBannerSize.large,
    );
    final c = controller();
    await c.load(width: 402);
    expect(requested(0), AnchoredBannerSize.large);
    c.dispose();
  });

  test('a classic placement requests the classic size', () async {
    final c = controller(config: classic);
    await c.load(width: 402);
    expect(requested(0), AnchoredBannerSize.classic);
    c.dispose();
  });

  test('a client-side refresh of a classic placement stays classic', () {
    fakeAsync((async) {
      final c = controller(
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
          anchoredSize: AnchoredBannerSize.classic,
          minRefresh: Duration(seconds: 60),
        ),
      );
      unawaited(c.load(width: 402));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 61));
      expect(sdk.bannerSpecs, hasLength(2), reason: 'the refresh ran');
      expect(requested(1), AnchoredBannerSize.classic);
      c.dispose();
    });
  });

  test(
    'the large and classic heights of one width are remembered apart',
    () async {
      final memory = BannerHeightMemory();

      sdk.bannerSize = const AdDimensions(width: 402, height: 126);
      final large = controller(memory: memory);
      await large.load(width: 402);
      large.dispose();

      final hold = Completer<void>();
      sdk.loadHold = hold;
      final firstClassic = controller(config: classic, memory: memory);
      unawaited(firstClassic.load(width: 402));
      expect(
        firstClassic.reservedHeight,
        50,
        reason: 'no classic banner has rendered at 402 yet — not the large 126',
      );
      sdk.bannerSize = const AdDimensions(width: 402, height: 63);
      hold.complete();
      await pumpEventQueue();
      firstClassic.dispose();
      sdk.loadHold = null;

      expect(memory.heightFor(402), 126);
      expect(memory.heightFor(402, size: AnchoredBannerSize.classic), 63);

      final held = Completer<void>();
      sdk.loadHold = held;
      final nextClassic = controller(config: classic, memory: memory);
      final nextLarge = controller(memory: memory);
      unawaited(nextClassic.load(width: 402));
      unawaited(nextLarge.load(width: 402));
      expect(nextClassic.reservedHeight, 63);
      expect(nextLarge.reservedHeight, 126);
      held.complete();
      await pumpEventQueue();
      nextClassic.dispose();
      nextLarge.dispose();
    },
  );

  test('BannerConfig equality includes anchoredSize', () {
    const large = BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b'));
    expect(classic == large, isFalse);
    expect(
      classic,
      const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
        anchoredSize: AnchoredBannerSize.classic,
      ),
    );
    expect(
      classic.hashCode,
      const BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-b'),
        anchoredSize: AnchoredBannerSize.classic,
      ).hashCode,
    );
  });

  testWidgets('switching a placement to classic re-requests it at the classic '
      'size', (tester) async {
    final ads = await AdFlow.initialize(
      const AdFlowConfig(
        banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
      ),
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    Widget host(BannerConfig config) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AdFlowBanner(adFlow: ads, config: config),
      ),
    );

    // Two explicit configs, so the switch depends on BannerConfig equality
    // seeing anchoredSize (a null -> config change would re-mint regardless).
    await tester.pumpWidget(
      host(const BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a'))),
    );
    await tester.pumpAndSettle();
    expect(requested(0), AnchoredBannerSize.large);

    await tester.pumpWidget(
      host(
        const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'b-a'),
          anchoredSize: AnchoredBannerSize.classic,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sdk.bannerSpecs, hasLength(2));
    expect(requested(1), AnchoredBannerSize.classic);

    await tester.pumpWidget(const SizedBox());
    ads.dispose();
  });
}
