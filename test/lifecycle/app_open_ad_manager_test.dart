import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/lifecycle/app_open_ad_manager.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
    now = DateTime(2026, 7, 11, 12);
    coordinator = FullScreenAdCoordinator(now: () => now);
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AppOpenAdController controller({AppOpenConfig? config}) =>
      AppOpenAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: () async => consented && sdk.canRequestAdsResult,
          isEnabled: () => true,
          caps: caps,
          coordinator: coordinator,
        ),
        caps: caps,
        coordinator: coordinator,
        config:
            config ??
            const AppOpenConfig(
              adUnitId: PlatformAdUnitId(android: 'unit-ao'),
              cap: FrequencyCap(),
            ),
        adUnitId: 'unit-ao',
        now: () => now,
      );

  AppOpenAdManager manager(
    AppOpenAdController c, {
    AppOpenConfig? config,
    bool withCoordinator = true,
  }) => AppOpenAdManager(
    controller: c,
    sdk: sdk,
    config:
        config ??
        const AppOpenConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ao'),
          cap: FrequencyCap(),
        ),
    coordinator: withCoordinator ? coordinator : null,
    now: () => now,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('no load while consent is closed (invariant 1)', () async {
    consented = false;
    sdk.canRequestAdsResult = false;
    final c = controller();
    await c.load();
    expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
    c.dispose();
  });

  group('controller expiry (4h rule)', () {
    test('a fresh ad shows; a stale ad is discarded and reloaded', () async {
      final c = controller();
      await c.load();
      expect(c.isExpired, isFalse);

      now = now.add(const Duration(hours: 4));
      expect(c.isExpired, isTrue);

      final shown = await c.show();
      await settle();

      expect(shown, isFalse);
      expect(sdk.appOpens.first.showCalls, 0);
      expect(sdk.appOpens.first.disposed, isTrue);
      expect(sdk.appOpens, hasLength(2)); // fresh one warmed
      expect(c.state.value, const AdLoaded());
      expect(c.isExpired, isFalse); // new timestamp
      c.dispose();
    });

    test('just under the expiry still shows', () async {
      final c = controller();
      await c.load();
      now = now.add(const Duration(hours: 3, minutes: 59));
      expect(await c.show(), isTrue);
      c.dispose();
    });
  });

  group('manager lifecycle', () {
    test(
      'start warms a preload; the FIRST foreground event is a genuine warm '
      'return and DOES show (ADR-043)',
      () async {
        final c = controller();
        final m = manager(c);
        m.start();
        await settle();
        expect(sdk.appOpens, hasLength(1)); // preload only, nothing shown

        // AppStateEventNotifier does not replay the cold-launch foreground
        // (the seam only calls startListening() once the app is already
        // foregrounded), so this first event IS a real background→return.
        // Suppressing it cost one impression in every single session.
        sdk.emitAppForeground();
        await settle();
        expect(sdk.appOpens.single.showCalls, 1);

        m.dispose();
        c.dispose();
      },
    );

    test(
      'a TRUE cold start cannot show, because nothing is loaded yet — that is '
      'the structural guard for invariant 3, not a latch (ADR-043)',
      () async {
        // No ad can be warm at the instant of a cold launch.
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'still loading',
        );
        final c = controller();
        final m = manager(c);
        m.start();
        await settle();

        sdk.emitAppForeground();
        await settle();

        expect(sdk.appOpens, isEmpty);

        m.dispose();
        c.dispose();
      },
    );

    test('suppressed while another full-screen ad is visible', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      coordinator.enter(); // e.g. an interstitial is showing
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);

      coordinator.exit();
      // Immediately after the OTHER ad exits is still within the
      // post-dismiss suppression window (review finding #7) — must not
      // show yet, even though the coordinator itself is clear again.
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);

      now = now.add(const Duration(seconds: 1));
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 1);

      m.dispose();
      c.dispose();
    });

    test(
      'never shows immediately behind ANOTHER format\'s dismiss, even '
      'with no global frequency-cap minGap configured (review finding #7)',
      () async {
        final c = controller();
        final m = manager(c);
        m.start();
        await settle();
        // A completely unrelated interstitial (or any other format)
        // shows and dismisses, touching only the shared coordinator —
        // this manager never sees it directly.
        coordinator.enter();
        coordinator.exit();

        // The warm-start signal arrives right on its heels.
        sdk.emitAppForeground();
        await settle();
        expect(sdk.appOpens.single.showCalls, 0); // suppressed
        expect(coordinator.isFullScreenAdVisible, isFalse); // not "busy"

        now = now.add(const Duration(seconds: 1));
        sdk.emitAppForeground();
        await settle();
        expect(sdk.appOpens.single.showCalls, 1); // allowed once past it

        m.dispose();
        c.dispose();
      },
    );

    test('without a coordinator wired in, no suppression applies (documents '
        'why the facade always passes one — see AdFlow._appOpen)', () async {
      final c = controller();
      final m = manager(c, withCoordinator: false);
      m.start();
      await settle();
      coordinator.enter();
      coordinator.exit();

      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 1); // no suppression signal

      m.dispose();
      c.dispose();
    });

    test('expired ad on foreground is discarded, not shown', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      now = now.add(const Duration(hours: 5));
      sdk.emitAppForeground();
      await settle();

      expect(sdk.appOpens.first.showCalls, 0);
      expect(sdk.appOpens.first.disposed, isTrue);
      expect(sdk.appOpens, hasLength(2));

      m.dispose();
      c.dispose();
    });

    test('frequency cap paces foreground shows', () async {
      caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: {
          'app_open': const FrequencyCap(minGap: Duration(minutes: 4)),
        },
        globalCap: const FrequencyCap(),
        now: () => now,
      );
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.first.showCalls, 1);
      sdk.appOpens.first.simulateDismissed();
      await settle();

      sdk.emitAppForeground(); // 0s later: capped
      await settle();
      expect(sdk.appOpens.last.showCalls, 0);

      now = now.add(const Duration(minutes: 4));
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.last.showCalls, 1);

      m.dispose();
      c.dispose();
    });

    test('start is idempotent; stop unsubscribes', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      m.start();
      await settle();
      expect(m.isStarted, isTrue);

      m.stop();
      expect(m.isStarted, isFalse);
      sdk.emitAppForeground();
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);

      c.dispose();
    });
  });
}
