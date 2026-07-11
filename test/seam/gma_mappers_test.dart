import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/gma_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;

void main() {
  group('toGmaAdRequest', () {
    test('maps every field', () {
      const options = AdRequestOptions(
        keywords: ['games'],
        contentUrl: 'https://example.com',
        neighboringContentUrls: ['https://example.com/a'],
        nonPersonalizedAds: true,
        extras: {'k': 'v'},
      );
      final request = toGmaAdRequest(options);
      expect(request.keywords, ['games']);
      expect(request.contentUrl, 'https://example.com');
      expect(request.neighboringContentUrls, ['https://example.com/a']);
      expect(request.nonPersonalizedAds, isTrue);
      expect(request.extras, {'k': 'v'});
    });

    test('explicit extras override the options extras', () {
      const options = AdRequestOptions(extras: {'k': 'v'});
      final request = toGmaAdRequest(options, extras: {'merged': '1'});
      expect(request.extras, {'merged': '1'});
    });
  });

  group('mergeCollapsibleExtras', () {
    test('null collapsible passes extras through unchanged', () {
      expect(mergeCollapsibleExtras(null, null), isNull);
      expect(mergeCollapsibleExtras({'a': 'b'}, null), {'a': 'b'});
    });

    test('collapsible placement is merged into extras', () {
      expect(
        mergeCollapsibleExtras(null, CollapsiblePlacement.bottom),
        {'collapsible': 'bottom'},
      );
      expect(
        mergeCollapsibleExtras({'a': 'b'}, CollapsiblePlacement.top),
        {'a': 'b', 'collapsible': 'top'},
      );
    });
  });

  group('toGmaRequestConfiguration', () {
    test('maps ratings and int-encodes tags', () {
      const config = AdRequestConfig(
        testDeviceIds: ['dev-1'],
        maxAdContentRating: MaxContentRating.pg,
        tagForChildDirectedTreatment: true,
        tagForUnderAgeOfConsent: false,
      );
      final mapped = toGmaRequestConfiguration(config);
      expect(mapped.testDeviceIds, ['dev-1']);
      expect(mapped.maxAdContentRating, gma.MaxAdContentRating.pg);
      expect(mapped.tagForChildDirectedTreatment, 1);
      expect(mapped.tagForUnderAgeOfConsent, 0);
    });

    test('null tags stay unspecified', () {
      final mapped = toGmaRequestConfiguration(const AdRequestConfig());
      expect(mapped.tagForChildDirectedTreatment, isNull);
      expect(mapped.tagForUnderAgeOfConsent, isNull);
      expect(mapped.maxAdContentRating, isNull);
      expect(mapped.testDeviceIds, isNull);
    });

    test('rating covers all values', () {
      expect(toGmaMaxContentRating(MaxContentRating.g), 'G');
      expect(toGmaMaxContentRating(MaxContentRating.pg), 'PG');
      expect(toGmaMaxContentRating(MaxContentRating.t), 'T');
      expect(toGmaMaxContentRating(MaxContentRating.ma), 'MA');
    });
  });

  group('size and template mapping', () {
    test('fixed sizes map to the plugin constants', () {
      expect(toGmaFixedAdSize(FixedBannerSize.banner), gma.AdSize.banner);
      expect(
        toGmaFixedAdSize(FixedBannerSize.largeBanner),
        gma.AdSize.largeBanner,
      );
      expect(
        toGmaFixedAdSize(FixedBannerSize.mediumRectangle),
        gma.AdSize.mediumRectangle,
      );
      expect(
        toGmaFixedAdSize(FixedBannerSize.fullBanner),
        gma.AdSize.fullBanner,
      );
      expect(
        toGmaFixedAdSize(FixedBannerSize.leaderboard),
        gma.AdSize.leaderboard,
      );
    });

    test('template kinds map to the plugin enum', () {
      expect(
        toGmaTemplateType(NativeTemplateKind.small),
        gma.TemplateType.small,
      );
      expect(
        toGmaTemplateType(NativeTemplateKind.medium),
        gma.TemplateType.medium,
      );
    });
  });

  group('status and error mapping', () {
    test('revenue precision maps one-to-one', () {
      expect(
        revenuePrecisionFrom(gma.PrecisionType.unknown),
        AdRevenuePrecision.unknown,
      );
      expect(
        revenuePrecisionFrom(gma.PrecisionType.estimated),
        AdRevenuePrecision.estimated,
      );
      expect(
        revenuePrecisionFrom(gma.PrecisionType.publisherProvided),
        AdRevenuePrecision.publisherProvided,
      );
      expect(
        revenuePrecisionFrom(gma.PrecisionType.precise),
        AdRevenuePrecision.precise,
      );
    });

    test('consent status maps one-to-one', () {
      expect(
        consentStatusFrom(gma.ConsentStatus.unknown),
        AdConsentStatus.unknown,
      );
      expect(
        consentStatusFrom(gma.ConsentStatus.required),
        AdConsentStatus.required,
      );
      expect(
        consentStatusFrom(gma.ConsentStatus.notRequired),
        AdConsentStatus.notRequired,
      );
      expect(
        consentStatusFrom(gma.ConsentStatus.obtained),
        AdConsentStatus.obtained,
      );
    });

    test('privacy requirement maps one-to-one', () {
      expect(
        privacyRequirementFrom(gma.PrivacyOptionsRequirementStatus.unknown),
        PrivacyOptionsRequirement.unknown,
      );
      expect(
        privacyRequirementFrom(gma.PrivacyOptionsRequirementStatus.required),
        PrivacyOptionsRequirement.required,
      );
      expect(
        privacyRequirementFrom(
          gma.PrivacyOptionsRequirementStatus.notRequired,
        ),
        PrivacyOptionsRequirement.notRequired,
      );
    });

    test('debug geography maps one-to-one', () {
      expect(
        toGmaDebugGeography(ConsentDebugGeography.disabled),
        gma.DebugGeography.debugGeographyDisabled,
      );
      expect(
        toGmaDebugGeography(ConsentDebugGeography.eea),
        gma.DebugGeography.debugGeographyEea,
      );
      expect(
        toGmaDebugGeography(ConsentDebugGeography.regulatedUsState),
        gma.DebugGeography.debugGeographyRegulatedUsState,
      );
      expect(
        toGmaDebugGeography(ConsentDebugGeography.other),
        gma.DebugGeography.debugGeographyOther,
      );
    });

    test('load, show and consent errors carry code/domain/kind', () {
      final load = loadErrorFrom(gma.LoadAdError(3, 'admob', 'no fill', null));
      expect(load.kind, AdFlowErrorKind.loadFailed);
      expect(load.code, 3);
      expect(load.domain, 'admob');
      expect(load.message, contains('no fill'));

      final show = showErrorFrom(gma.AdError(1, 'admob', 'not ready'));
      expect(show.kind, AdFlowErrorKind.showFailed);
      expect(show.code, 1);

      final consent = consentErrorFrom(
        gma.FormError(errorCode: 7, message: 'timeout'),
      );
      expect(consent.kind, AdFlowErrorKind.consent);
      expect(consent.code, 7);
      expect(consent.message, 'timeout');
    });
  });
}
