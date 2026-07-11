import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  NativeAdController controller({
    NativeConfig? config,
    RetryConfig retryConfig = const RetryConfig(),
  }) => NativeAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => consented && sdk.canRequestAdsResult,
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
        const NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-n'),
          templateKind: NativeTemplateKind.medium,
        ),
    adUnitId: 'unit-n',
    retry: RetryPolicy(retryConfig, random: () => 0.5),
  );

  test('no load while consent is closed (invariant 1)', () async {
    consented = false;
    sdk.canRequestAdsResult = false;
    final c = controller();
    await c.load();
    expect(sdk.loadLog, isEmpty);
    expect(c.state.value, const AdIdle());
    c.dispose();
  });

  test('template path passes the template kind through the spec', () async {
    final c = controller();
    await c.load();
    expect(c.state.value, const AdLoaded());
    expect(c.handle, same(sdk.natives.single));
    expect(sdk.nativeSpecs.single.templateKind, NativeTemplateKind.medium);
    expect(sdk.nativeSpecs.single.factoryId, isNull);
    c.dispose();
  });

  test('factory path passes factoryId and extras through the spec', () async {
    final c = controller(
      config: const NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-n'),
        factoryId: 'newsFeedTile',
        factoryExtras: {'accent': 'blue'},
      ),
    );
    await c.load();
    expect(sdk.nativeSpecs.single.factoryId, 'newsFeedTile');
    expect(sdk.nativeSpecs.single.factoryExtras, {'accent': 'blue'});
    expect(sdk.nativeSpecs.single.templateKind, isNull);
    c.dispose();
  });

  test('reservedHeight follows the rendering path', () {
    expect(controller().reservedHeight, 320); // medium template
    expect(
      controller(
        config: const NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-n'),
          templateKind: NativeTemplateKind.small,
        ),
      ).reservedHeight,
      90,
    );
    expect(
      controller(
        config: const NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-n'),
          factoryId: 'f',
        ),
      ).reservedHeight,
      100,
    );
  });

  test('reload disposes the old ad and loads a fresh one', () async {
    final c = controller();
    await c.load();
    final first = sdk.natives.single;

    await c.reload();

    expect(first.disposed, isTrue);
    expect(sdk.natives, hasLength(2));
    expect(c.state.value, const AdLoaded());
    c.dispose();
  });

  test('failure retries with backoff then cooldown re-arms', () {
    fakeAsync((async) {
      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'no fill',
      );
      final c = controller(
        retryConfig: const RetryConfig(
          maxAttempts: 1,
          cooldown: Duration(minutes: 5),
        ),
      );
      c.load();
      async.flushMicrotasks();
      expect(c.state.value, isA<AdFailed>());

      sdk.alwaysLoadError = null;
      async.elapse(const Duration(minutes: 5));
      expect(c.state.value, const AdLoaded());
      c.dispose();
    });
  });

  test('forwards paid events', () async {
    final paid = <AdPaidEvent>[];
    final c = NativeAdController(
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
      config: const NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-n'),
        templateKind: NativeTemplateKind.small,
      ),
      adUnitId: 'unit-n',
      onPaid: paid.add,
    );
    await c.load();

    const event = AdPaidEvent(
      adUnitId: 'unit-n',
      valueMicros: 2500,
      currencyCode: 'USD',
      precision: AdRevenuePrecision.estimated,
    );
    sdk.natives.single.simulatePaid(event);
    expect(paid, [event]);
    c.dispose();
  });

  test('dispose cancels retries and disposes the handle', () {
    fakeAsync((async) {
      final c = controller();
      c.load();
      async.flushMicrotasks();
      final handle = sdk.natives.single;

      c.dispose();
      expect(handle.disposed, isTrue);
      async.elapse(const Duration(hours: 1));
      expect(sdk.natives, hasLength(1));
    });
  });
}
