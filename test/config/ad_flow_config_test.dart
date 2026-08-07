import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/config/ad_platform.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdPlatform', () {
    test('maps android and ios', () {
      expect(adPlatformOf(TargetPlatform.android), AdPlatform.android);
      expect(adPlatformOf(TargetPlatform.iOS), AdPlatform.ios);
    });

    test('throws invalidConfig on unsupported platforms', () {
      expect(
        () => adPlatformOf(TargetPlatform.macOS),
        throwsA(
          isA<AdFlowError>().having(
            (e) => e.kind,
            'kind',
            AdFlowErrorKind.invalidConfig,
          ),
        ),
      );
    });

    test('currentAdPlatform honors the debug override', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(currentAdPlatform(), AdPlatform.ios);
    });
  });

  group('PlatformAdUnitId', () {
    test('resolves per platform and supports missing platforms', () {
      const id = PlatformAdUnitId(android: 'a-1', ios: 'i-1');
      expect(id.resolve(AdPlatform.android), 'a-1');
      expect(id.resolve(AdPlatform.ios), 'i-1');

      const androidOnly = PlatformAdUnitId(android: 'a-2');
      expect(androidOnly.resolve(AdPlatform.ios), isNull);
    });
  });

  group('ad unit resolution', () {
    const config = AdFlowConfig(
      banner: BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'prod-banner-a'),
      ),
      interstitial: InterstitialConfig(
        adUnitId: PlatformAdUnitId(
          android: 'prod-inter-a',
          ios: 'prod-inter-i',
        ),
      ),
      // rewarded, rewardedInterstitial, nativeAd, appOpen: unconfigured.
    );

    test('configured slots resolve their production IDs', () {
      expect(config.bannerAdUnitId(AdPlatform.android), 'prod-banner-a');
      expect(config.interstitialAdUnitId(AdPlatform.ios), 'prod-inter-i');
    });

    test('a configured slot missing one platform resolves null there', () {
      expect(config.bannerAdUnitId(AdPlatform.ios), isNull);
    });

    test('unconfigured slots resolve null', () {
      expect(config.rewardedAdUnitId(AdPlatform.android), isNull);
      expect(config.rewardedInterstitialAdUnitId(AdPlatform.android), isNull);
      expect(config.nativeAdUnitId(AdPlatform.android), isNull);
      expect(config.appOpenAdUnitId(AdPlatform.android), isNull);
    });
  });

  group('testMode (ADR-012: flag, never derived from IDs)', () {
    test('testMode swaps configured slots to Google sample IDs', () {
      const config = AdFlowConfig(
        banner: BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'prod-banner-a'),
        ),
        testMode: true,
      );
      expect(
        config.bannerAdUnitId(AdPlatform.android),
        TestAdUnitIds.banner.android,
      );
      expect(config.bannerAdUnitId(AdPlatform.ios), TestAdUnitIds.banner.ios);
    });

    // ADR-073 / issue #15: Google publishes a different sample banner unit per
    // FORMAT. Serving an adaptive request from the fixed-size unit only ever
    // returns fixed IAB creatives (320x50, 320x100, 468x60), which cannot fill
    // an adaptive slot — the ad renders narrow and short inside it with the
    // app's own surface showing around it. The sample unit must follow `kind`.
    test('testMode picks the sample unit matching the banner kind', () {
      const prod = PlatformAdUnitId(android: 'prod-banner-a', ios: 'prod-b-i');
      for (final kind in [
        BannerKind.anchoredAdaptive,
        BannerKind.inlineAdaptive,
      ]) {
        final config = AdFlowConfig(
          banner: BannerConfig(adUnitId: prod, kind: kind),
          testMode: true,
        );
        expect(
          config.bannerAdUnitId(AdPlatform.android),
          TestAdUnitIds.adaptiveBanner.android,
          reason: '$kind must use the adaptive sample unit',
        );
        expect(
          config.bannerAdUnitId(AdPlatform.ios),
          TestAdUnitIds.adaptiveBanner.ios,
          reason: '$kind must use the adaptive sample unit',
        );
      }

      const fixed = AdFlowConfig(
        banner: BannerConfig(adUnitId: prod, kind: BannerKind.fixed),
        testMode: true,
      );
      expect(
        fixed.bannerAdUnitId(AdPlatform.android),
        TestAdUnitIds.fixedBanner.android,
      );
      expect(
        fixed.bannerAdUnitId(AdPlatform.ios),
        TestAdUnitIds.fixedBanner.ios,
      );
    });

    test('the sample banner units are Google\'s documented per-format IDs', () {
      // Pinned deliberately: a wrong unit here is invisible in unit tests and
      // only shows up as a badly-fitted banner on a real device.
      expect(
        TestAdUnitIds.adaptiveBanner.android,
        'ca-app-pub-3940256099942544/9214589741',
      );
      expect(
        TestAdUnitIds.adaptiveBanner.ios,
        'ca-app-pub-3940256099942544/2435281174',
      );
      expect(
        TestAdUnitIds.fixedBanner.android,
        'ca-app-pub-3940256099942544/6300978111',
      );
      expect(
        TestAdUnitIds.fixedBanner.ios,
        'ca-app-pub-3940256099942544/2934735716',
      );
      // The legacy alias keeps pointing at the default kind's unit.
      expect(TestAdUnitIds.banner, same(TestAdUnitIds.adaptiveBanner));
    });

    test('a per-placement kind overrides the global config kind', () {
      const config = AdFlowConfig(
        banner: BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'prod-banner-a'),
          kind: BannerKind.fixed,
        ),
        testMode: true,
      );
      expect(
        config.bannerAdUnitId(AdPlatform.android),
        TestAdUnitIds.fixedBanner.android,
      );
      expect(
        config.bannerAdUnitId(
          AdPlatform.android,
          kind: BannerKind.inlineAdaptive,
        ),
        TestAdUnitIds.adaptiveBanner.android,
      );
    });

    test('testMode does NOT enable unconfigured slots (v1 regression)', () {
      const config = AdFlowConfig(testMode: true);
      expect(config.bannerAdUnitId(AdPlatform.android), isNull);
      expect(config.appOpenAdUnitId(AdPlatform.android), isNull);
    });

    test('production IDs containing the test publisher do not flip the '
        'flag — testMode is storage, not inference', () {
      final config = AdFlowConfig(
        banner: BannerConfig(adUnitId: TestAdUnitIds.banner),
      );
      expect(config.testMode, isFalse);
    });

    test('AdFlowConfig.test enables every format with sample IDs', () {
      final config = AdFlowConfig.test();
      expect(config.testMode, isTrue);
      // The ADAPTIVE sample unit — AdFlowConfig.test's banner uses the default
      // anchoredAdaptive kind, and the fixed-size unit only serves fixed IAB
      // creatives that cannot fill an adaptive slot (ADR-073 / issue #15).
      expect(
        config.bannerAdUnitId(AdPlatform.android),
        'ca-app-pub-3940256099942544/9214589741',
      );
      expect(
        config.interstitialAdUnitId(AdPlatform.ios),
        'ca-app-pub-3940256099942544/4411468910',
      );
      expect(
        config.rewardedAdUnitId(AdPlatform.android),
        'ca-app-pub-3940256099942544/5224354917',
      );
      expect(
        config.rewardedInterstitialAdUnitId(AdPlatform.android),
        'ca-app-pub-3940256099942544/5354046379',
      );
      expect(
        config.nativeAdUnitId(AdPlatform.ios),
        'ca-app-pub-3940256099942544/3986624511',
      );
      expect(
        config.appOpenAdUnitId(AdPlatform.android),
        'ca-app-pub-3940256099942544/9257395921',
      );
    });
  });

  group('defaults and validation', () {
    test('global defaults follow policy-safe values', () {
      const config = AdFlowConfig();
      expect(config.globalFrequencyCap.maxPerSession, 100);
      expect(config.globalFrequencyCap.minGap, const Duration(seconds: 15));
      expect(config.retry.maxAttempts, 3);
      expect(config.retry.baseDelay, const Duration(seconds: 5));
      expect(config.retry.cooldown, const Duration(minutes: 5));
      expect(config.testMode, isFalse);
    });

    test('per-format defaults', () {
      const banner = BannerConfig(adUnitId: PlatformAdUnitId(android: 'a'));
      expect(banner.kind, BannerKind.anchoredAdaptive);
      // The client-side refresh is OFF by default (ADR-041): AdMob already
      // auto-refreshes banner ad units server-side, from the console.
      expect(banner.minRefresh, isNull);

      const interstitial = InterstitialConfig(
        adUnitId: PlatformAdUnitId(android: 'a'),
      );
      expect(interstitial.cap.minGap, const Duration(seconds: 30));
      expect(interstitial.minActionsBetween, 2);

      const appOpen = AppOpenConfig(adUnitId: PlatformAdUnitId(android: 'a'));
      expect(appOpen.expiry, const Duration(hours: 4));
    });

    test('NativeConfig requires exactly one rendering path', () {
      expect(
        () => NativeConfig(adUnitId: const PlatformAdUnitId(android: 'a')),
        throwsAssertionError,
      );
      expect(
        () => NativeConfig(
          adUnitId: const PlatformAdUnitId(android: 'a'),
          templateKind: NativeTemplateKind.small,
          factoryId: 'f',
        ),
        throwsAssertionError,
      );
    });

    test('NativeConfig maxAdAge defaults to 55 minutes and participates in '
        'equality + hashCode (5.1)', () {
      const base = NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'a'),
        templateKind: NativeTemplateKind.small,
      );
      expect(base.maxAdAge, const Duration(minutes: 55));

      const sameAge = NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'a'),
        templateKind: NativeTemplateKind.small,
        maxAdAge: Duration(minutes: 55),
      );
      const differentAge = NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'a'),
        templateKind: NativeTemplateKind.small,
        maxAdAge: Duration(minutes: 30),
      );
      const disabledAge = NativeConfig(
        adUnitId: PlatformAdUnitId(android: 'a'),
        templateKind: NativeTemplateKind.small,
        maxAdAge: null,
      );

      expect(base, sameAge);
      expect(base.hashCode, sameAge.hashCode);
      expect(base, isNot(differentAge));
      expect(base, isNot(disabledAge));
      // A widget compares configs to decide whether to re-mint its controller
      // (ADR-029); maxAdAge must therefore change equality or a maxAdAge-only
      // config swap would be silently ignored.
      expect(base == differentAge, isFalse);
    });

    test('toRequestConfig maps config to seam AdRequestConfig', () {
      const config = AdFlowConfig(
        testDeviceIds: ['dev-1'],
        maxAdContentRating: MaxContentRating.t,
        tagForChildDirectedTreatment: false,
        tagForUnderAgeOfConsent: true,
      );
      final rc = config.toRequestConfig();
      expect(rc.testDeviceIds, ['dev-1']);
      expect(rc.maxAdContentRating, MaxContentRating.t);
      expect(rc.tagForChildDirectedTreatment, isFalse);
      expect(rc.tagForUnderAgeOfConsent, isTrue);
    });

    test('empty testDeviceIds maps to null (leave SDK default untouched)', () {
      expect(const AdFlowConfig().toRequestConfig().testDeviceIds, isNull);
    });
  });

  group(
    'validate() (2026-07 audit — fail fast at init, not silent no-fill)',
    () {
      final throwsInvalidConfig = throwsA(
        isA<AdFlowError>().having(
          (e) => e.kind,
          'kind',
          AdFlowErrorKind.invalidConfig,
        ),
      );

      test('a healthy config (and the test config) validates clean', () {
        const AdFlowConfig().validate();
        AdFlowConfig.test().validate();
      });

      test('an EMPTY ad unit string is rejected (it would silently no-fill '
          'forever in production)', () {
        expect(
          () => const AdFlowConfig(
            banner: BannerConfig(adUnitId: PlatformAdUnitId(android: '')),
          ).validate(),
          throwsInvalidConfig,
        );
      });

      test('a slot with NO platform IDs at all is rejected', () {
        expect(
          () => const AdFlowConfig(
            interstitial: InterstitialConfig(adUnitId: PlatformAdUnitId()),
          ).validate(),
          throwsInvalidConfig,
        );
      });

      test('negative durations are rejected', () {
        expect(
          () => const AdFlowConfig(
            globalFrequencyCap: FrequencyCap(minGap: Duration(seconds: -1)),
          ).validate(),
          throwsInvalidConfig,
        );
        expect(
          () => const AdFlowConfig(
            rewarded: RewardedConfig(
              adUnitId: PlatformAdUnitId(android: 'r'),
              maxAdAge: Duration.zero,
            ),
          ).validate(),
          throwsInvalidConfig,
        );
        expect(
          () => const AdFlowConfig(
            nativeAd: NativeConfig(
              adUnitId: PlatformAdUnitId(android: 'n'),
              templateKind: NativeTemplateKind.small,
              maxAdAge: Duration.zero,
            ),
          ).validate(),
          throwsInvalidConfig,
        );
        expect(
          () => const AdFlowConfig(
            retry: RetryConfig(baseDelay: Duration.zero),
          ).validate(),
          throwsInvalidConfig,
        );
      });

      test('a non-positive maxInlineHeight is rejected', () {
        expect(
          () => const AdFlowConfig(
            banner: BannerConfig(
              adUnitId: PlatformAdUnitId(android: 'b'),
              kind: BannerKind.inlineAdaptive,
              maxInlineHeight: 0,
            ),
          ).validate(),
          throwsInvalidConfig,
        );
      });
    },
  );
}
