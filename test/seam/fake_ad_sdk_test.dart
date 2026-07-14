import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;

  setUp(() => sdk = FakeAdSdk());
  tearDown(() => sdk.dispose());

  group('initialization and configuration', () {
    test('initialize is recorded', () async {
      await sdk.initialize();
      await sdk.initialize();
      expect(sdk.initializeCalls, 2);
    });

    test('updateRequestConfiguration records the config', () async {
      const config = AdRequestConfig(
        testDeviceIds: ['abc'],
        maxAdContentRating: MaxContentRating.pg,
        tagForChildDirectedTreatment: false,
        tagForUnderAgeOfConsent: true,
      );
      await sdk.updateRequestConfiguration(config);
      expect(sdk.requestConfigs, [config]);
    });
  });

  group('full-screen loads', () {
    test('each load returns a fresh recorded handle', () async {
      final a = await sdk.loadInterstitial('unit-a', const AdRequestOptions());
      final b = await sdk.loadInterstitial('unit-b', const AdRequestOptions());
      expect(a, isNot(same(b)));
      expect(sdk.interstitials, [a, b]);
      expect(sdk.loadLog, ['interstitial:unit-a', 'interstitial:unit-b']);
    });

    test('all four formats load and are recorded separately', () async {
      await sdk.loadInterstitial('i', const AdRequestOptions());
      await sdk.loadRewarded('r', const AdRequestOptions());
      await sdk.loadRewardedInterstitial('ri', const AdRequestOptions());
      await sdk.loadAppOpen('ao', const AdRequestOptions());
      expect(sdk.interstitials, hasLength(1));
      expect(sdk.rewardeds, hasLength(1));
      expect(sdk.rewardedInterstitials, hasLength(1));
      expect(sdk.appOpens, hasLength(1));
      expect(sdk.loadLog, [
        'interstitial:i',
        'rewarded:r',
        'rewarded_interstitial:ri',
        'app_open:ao',
      ]);
    });

    test('nextLoadError throws once then clears', () async {
      const error = AdFlowError(AdFlowErrorKind.loadFailed, 'no fill');
      sdk.nextLoadError = error;
      await expectLater(
        sdk.loadRewarded('r', const AdRequestOptions()),
        throwsA(same(error)),
      );
      final handle = await sdk.loadRewarded('r', const AdRequestOptions());
      expect(handle, isA<RewardedHandle>());
    });

    test('alwaysLoadError keeps throwing', () async {
      const error = AdFlowError(AdFlowErrorKind.loadFailed, 'network down');
      sdk.alwaysLoadError = error;
      await expectLater(
        sdk.loadAppOpen('ao', const AdRequestOptions()),
        throwsA(same(error)),
      );
      await expectLater(
        sdk.loadAppOpen('ao', const AdRequestOptions()),
        throwsA(same(error)),
      );
    });

    test('enforceConsentGate trips on load without consent', () async {
      sdk.enforceConsentGate = true;
      await expectLater(
        sdk.loadInterstitial('i', const AdRequestOptions()),
        throwsStateError,
      );
      sdk.canRequestAdsResult = true;
      final handle = await sdk.loadInterstitial('i', const AdRequestOptions());
      expect(handle, isA<InterstitialHandle>());
    });
  });

  group('FakeFullScreenAdHandle', () {
    test('show emits AdShowedEvent and records the reward callback', () async {
      final handle =
          await sdk.loadRewarded('r', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      final events = <FullScreenAdEvent>[];
      handle.contentEvents.listen(events.add);

      RewardEarned? earned;
      await handle.show(onUserEarnedReward: (r) => earned = r);
      handle.simulateReward(const RewardEarned(amount: 5, type: 'coins'));
      handle.simulateDismissed();

      expect(handle.showCalls, 1);
      expect(earned, const RewardEarned(amount: 5, type: 'coins'));
      expect(events, [isA<AdShowedEvent>(), isA<AdDismissedEvent>()]);
    });

    test('showError surfaces as AdFailedToShowEvent, not a throw', () async {
      final handle =
          await sdk.loadInterstitial('i', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      const error = AdFlowError(AdFlowErrorKind.showFailed, 'not ready');
      handle.showError = error;

      final events = <FullScreenAdEvent>[];
      handle.contentEvents.listen(events.add);
      await handle.show();

      expect(events, hasLength(1));
      expect((events.single as AdFailedToShowEvent).error, same(error));
    });

    test('a rejected showRejectsWith throws instead of completing '
        '(review finding #1\'s premise)', () async {
      final handle =
          await sdk.loadInterstitial('i', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      handle.showRejectsWith = Exception('ad already released');

      await expectLater(handle.show(), throwsA(isA<Exception>()));
      expect(handle.showCalls, 1);
    });

    test('a SECOND show() call fails via AdFailedToShowEvent, not a silent '
        'repeat (review finding #10: the real SDK is single-use)', () async {
      final handle =
          await sdk.loadInterstitial('i', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      final events = <FullScreenAdEvent>[];
      handle.contentEvents.listen(events.add);

      await handle.show();
      await handle.show();

      expect(handle.showCalls, 2);
      expect(events, [isA<AdShowedEvent>(), isA<AdFailedToShowEvent>()]);
    });

    test('simulateDismissed before show() throws (review finding #10: '
        'impossible event ordering)', () async {
      final handle =
          await sdk.loadInterstitial('i', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      expect(handle.simulateDismissed, throwsStateError);
    });

    test('simulateReward after simulateDismissed throws (review finding #10: '
        'impossible event ordering)', () async {
      final handle =
          await sdk.loadRewarded('r', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      await handle.show(onUserEarnedReward: (_) {});
      handle.simulateDismissed();

      expect(
        () =>
            handle.simulateReward(const RewardEarned(amount: 1, type: 'coins')),
        throwsStateError,
      );
    });

    test('paid events are delivered', () async {
      final handle =
          await sdk.loadInterstitial('i', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      const paid = AdPaidEvent(
        adUnitId: 'i',
        valueMicros: 12345,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.estimated,
      );
      final events = <AdPaidEvent>[];
      handle.paidEvents.listen(events.add);
      handle.simulatePaid(paid);
      expect(events, [paid]);
    });

    test('dispose marks the handle and closes its streams', () async {
      final handle =
          await sdk.loadAppOpen('ao', const AdRequestOptions())
              as FakeFullScreenAdHandle;
      await handle.dispose();
      expect(handle.disposed, isTrue);
      await expectLater(handle.contentEvents, emitsDone);
    });
  });

  group('banner and native', () {
    test('loadBanner records the spec and honors size knobs', () async {
      sdk.bannerSize = const AdDimensions(width: 360, height: 60);
      sdk.bannerIsCollapsible = true;
      const spec = BannerLoadSpec(
        adUnitId: 'b',
        size: AnchoredAdaptiveSizeSpec(width: 360),
        collapsible: CollapsiblePlacement.bottom,
      );

      final handle = await sdk.loadBanner(spec);

      expect(sdk.bannerSpecs, [spec]);
      expect(handle.size, const AdDimensions(width: 360, height: 60));
      expect(handle.isCollapsible, isTrue);
    });

    test('loadNative records the spec', () async {
      const spec = NativeLoadSpec(
        adUnitId: 'n',
        templateKind: NativeTemplateKind.medium,
      );
      await sdk.loadNative(spec);
      expect(sdk.nativeSpecs, [spec]);
      expect(sdk.natives, hasLength(1));
    });

    test('NativeLoadSpec requires exactly one of template or factory', () {
      expect(() => NativeLoadSpec(adUnitId: 'n'), throwsAssertionError);
      expect(
        () => NativeLoadSpec(
          adUnitId: 'n',
          templateKind: NativeTemplateKind.small,
          factoryId: 'f',
        ),
        throwsAssertionError,
      );
    });

    testWidgets('fake banner buildWidget renders a box of the ad size', (
      tester,
    ) async {
      final handle = await sdk.loadBanner(
        const BannerLoadSpec(
          adUnitId: 'b',
          size: FixedSizeSpec(FixedBannerSize.banner),
        ),
      );
      await tester.pumpWidget(Center(child: handle.buildWidget()));
      final box = tester.getSize(find.byType(SizedBox));
      expect(box.width, 320);
      expect(box.height, 50);
    });
  });

  group('consent primitives', () {
    test('requestConsentInfoUpdate records arguments', () async {
      const debug = ConsentDebugOptions(
        geography: ConsentDebugGeography.eea,
        testIdentifiers: ['HASH'],
      );
      await sdk.requestConsentInfoUpdate(
        tagForUnderAgeOfConsent: true,
        debug: debug,
      );
      expect(sdk.consentUpdateCalls, hasLength(1));
      expect(sdk.consentUpdateCalls.single.tagForUnderAgeOfConsent, isTrue);
      expect(sdk.consentUpdateCalls.single.debug, same(debug));
    });

    test('consentUpdateError makes the update throw', () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'network');
      sdk.consentUpdateError = error;
      await expectLater(sdk.requestConsentInfoUpdate(), throwsA(same(error)));
    });

    test('form flow can flip the gate via onConsentFormShown', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };

      expect(await sdk.canRequestAds(), isFalse);
      await sdk.loadAndShowConsentFormIfRequired();

      expect(sdk.loadAndShowConsentFormCalls, 1);
      expect(await sdk.canRequestAds(), isTrue);
      expect(await sdk.getConsentStatus(), AdConsentStatus.obtained);
    });

    test('consentFormError makes the form call throw', () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'form failed');
      sdk.consentFormError = error;
      await expectLater(
        sdk.loadAndShowConsentFormIfRequired(),
        throwsA(same(error)),
      );
    });

    test('privacy options requirement and form are drivable', () async {
      sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
      expect(
        await sdk.getPrivacyOptionsRequirementStatus(),
        PrivacyOptionsRequirement.required,
      );
      await sdk.showPrivacyOptionsForm();
      expect(sdk.showPrivacyOptionsFormCalls, 1);
    });
  });

  group('lifecycle and inspector', () {
    test('emitAppForeground drives appForegroundEvents', () async {
      final events = <AppForegroundEvent>[];
      sdk.appForegroundEvents.listen(events.add);
      sdk.emitAppForeground();
      sdk.emitAppForeground();
      expect(events, hasLength(2));
    });

    test('openAdInspector returns the configured result', () async {
      const failed = AdInspectorResult(
        error: AdFlowError(AdFlowErrorKind.unknown, 'not a test device'),
      );
      sdk.inspectorResult = failed;
      final result = await sdk.openAdInspector();
      expect(result.isSuccess, isFalse);
      expect(sdk.adInspectorCalls, 1);
    });
  });

  group('ATT', () {
    test(
      'getTrackingAuthorizationStatus returns the settable status',
      () async {
        expect(
          await sdk.getTrackingAuthorizationStatus(),
          AttStatus.notSupported,
        );
        sdk.attStatus = AttStatus.notDetermined;
        expect(
          await sdk.getTrackingAuthorizationStatus(),
          AttStatus.notDetermined,
        );
      },
    );

    test(
      'requestTrackingAuthorization records the call, returns the configured '
      'result, and updates the status',
      () async {
        sdk.attStatus = AttStatus.notDetermined;
        sdk.attRequestResult = AttStatus.denied;

        final result = await sdk.requestTrackingAuthorization();

        expect(result, AttStatus.denied);
        expect(sdk.requestTrackingAuthorizationCalls, 1);
        // The status now reflects the prompt result.
        expect(await sdk.getTrackingAuthorizationStatus(), AttStatus.denied);
      },
    );
  });
}
