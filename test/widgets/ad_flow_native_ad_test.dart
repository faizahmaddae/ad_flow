import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
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
}
