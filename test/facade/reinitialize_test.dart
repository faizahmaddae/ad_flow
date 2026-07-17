import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AdFlow.initialize()` is idempotent (ADR-044).
///
/// Apps re-initialize: on login/logout, on a config change, on a hot restart in
/// debug. Every call used to build a WHOLE new graph and simply overwrite the
/// `_instance` pointer — leaving the previous one fully alive, still subscribed
/// to the foreground stream, still preloading, still able to show ads, and
/// coordinating through its own separate FullScreenAdCoordinator (so it could
/// not even see the new graph's ads). This is v1 trap #6 — two lifecycle
/// reactors fighting — reintroduced through the back door.
void main() {
  const config = AdFlowConfig(
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
    ),
    appOpen: AppOpenConfig(adUnitId: PlatformAdUnitId(android: 'ao-a')),
  );

  late FakeAdSdk sdk;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot() async {
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
    );
    await ads.whenReady;
    await Future<void>.delayed(Duration.zero);
    return ads;
  }

  test('a second initialize() tears the previous graph down', () async {
    final first = await boot();
    expect(sdk.hasForegroundListener, isTrue);

    final second = await boot();

    expect(identical(AdFlow.instance, second), isTrue);
    expect(identical(first, second), isFalse);

    // The old graph's controllers are really disposed — a disposed
    // ChangeNotifier throws on addListener, which is the unambiguous proof.
    expect(
      () => first.interstitial.state.addListener(() {}),
      throwsFlutterError,
      reason: 'the previous graph must be torn down, not left running',
    );

    // And the decisive one: no leaked foreground reactor. If the first graph's
    // AppOpenAdManager were still subscribed, disposing the second would leave
    // a listener behind — two reactors on one stream, each with its own
    // coordinator, each able to show an app-open ad the other cannot see.
    second.dispose();
    expect(
      sdk.hasForegroundListener,
      isFalse,
      reason: 'the first graph\'s AppOpenAdManager leaked its subscription',
    );
  });

  test('frequency-cap state SURVIVES a re-initialize when the same store is '
      'injected (2026-07 audit — a reinit must not reset ad pacing)', () async {
    final store = InMemoryKeyValueStore();
    final first = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: store,
      platform: AdPlatform.android,
    );
    await first.whenReady;
    await pumpEventQueue();
    // Show + dismiss an interstitial: its minGap timestamp persists.
    await first.interstitial.show();
    sdk.interstitials.last.simulateDismissed();
    await pumpEventQueue();

    final second = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: store,
      platform: AdPlatform.android,
    );
    await second.whenReady;
    await pumpEventQueue();

    expect(
      await second.interstitial.show(),
      isFalse,
      reason:
          'the 30s default minGap from the impression recorded under the '
          'FIRST graph must still pace the second one',
    );
    second.dispose();
  });

  test('dispose() after a re-initialize does not clear the live instance '
      'pointer', () async {
    final first = await boot();
    final second = await boot();

    // `first` is already disposed by the re-initialize above; calling dispose()
    // on it again must be a no-op and must NOT null out the pointer to the
    // live graph.
    first.dispose();

    expect(identical(AdFlow.instance, second), isTrue);
    second.dispose();
  });
}
