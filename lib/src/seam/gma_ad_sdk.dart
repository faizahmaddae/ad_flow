import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;

import '../core/ad_flow_error.dart';
import 'ad_sdk.dart';
import 'ad_sdk_types.dart';

/// The production [AdSdk]: maps the seam onto `google_mobile_ads`.
///
/// This file (plus the widgets that must host an `AdWidget`) is the ONLY
/// place in ad_flow that imports the plugin. Whether the legacy or Next-Gen
/// native SDK runs underneath is invisible here — the plugin's Dart API is
/// identical either way.
class GmaAdSdk implements AdSdk {
  bool _appStateListening = false;

  @override
  Future<void> initialize() async {
    // Completes on init or the SDK's internal ~30s timeout; sends no ad
    // request, so it is safe to run in parallel with consent gathering.
    await gma.MobileAds.instance.initialize();
  }

  @override
  Future<void> updateRequestConfiguration(AdRequestConfig config) {
    return gma.MobileAds.instance.updateRequestConfiguration(
      toGmaRequestConfiguration(config),
    );
  }

  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) async {
    final completer = Completer<InterstitialHandle>();
    await gma.InterstitialAd.load(
      adUnitId: adUnitId,
      request: toGmaAdRequest(options),
      adLoadCallback: gma.InterstitialAdLoadCallback(
        onAdLoaded: (ad) =>
            completer.complete(_GmaInterstitialHandle(adUnitId, ad)),
        onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
      ),
    );
    return completer.future;
  }

  @override
  Future<RewardedHandle> loadRewarded(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  }) async {
    final completer = Completer<RewardedHandle>();
    await gma.RewardedAd.load(
      adUnitId: adUnitId,
      request: toGmaAdRequest(options),
      rewardedAdLoadCallback: gma.RewardedAdLoadCallback(
        onAdLoaded: (ad) => unawaited(() async {
          // SSV must be attached before show; failures must not lose the ad.
          if (ssv != null) {
            try {
              await ad.setServerSideOptions(toGmaSsvOptions(ssv));
            } catch (_) {}
          }
          completer.complete(_GmaRewardedHandle(adUnitId, ad));
        }()),
        onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
      ),
    );
    return completer.future;
  }

  @override
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  }) async {
    final completer = Completer<RewardedInterstitialHandle>();
    await gma.RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: toGmaAdRequest(options),
      rewardedInterstitialAdLoadCallback:
          gma.RewardedInterstitialAdLoadCallback(
            onAdLoaded: (ad) => unawaited(() async {
              if (ssv != null) {
                try {
                  await ad.setServerSideOptions(toGmaSsvOptions(ssv));
                } catch (_) {}
              }
              completer.complete(
                _GmaRewardedInterstitialHandle(adUnitId, ad),
              );
            }()),
            onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
          ),
    );
    return completer.future;
  }

  @override
  Future<AppOpenHandle> loadAppOpen(
    String adUnitId,
    AdRequestOptions options,
  ) async {
    final completer = Completer<AppOpenHandle>();
    await gma.AppOpenAd.load(
      adUnitId: adUnitId,
      request: toGmaAdRequest(options),
      adLoadCallback: gma.AppOpenAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(_GmaAppOpenHandle(adUnitId, ad)),
        onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
      ),
    );
    return completer.future;
  }

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) async {
    final adSize = await _resolveBannerAdSize(spec.size);
    final completer = Completer<BannerHandle>();
    late final _GmaBannerHandle handle;
    final ad = gma.BannerAd(
      adUnitId: spec.adUnitId,
      size: adSize,
      request: toGmaAdRequest(
        spec.request,
        extras: mergeCollapsibleExtras(spec.request.extras, spec.collapsible),
      ),
      listener: gma.BannerAdListener(
        onAdLoaded: (_) => unawaited(
          _finishBannerLoad(handle, spec, completer),
        ),
        onAdFailedToLoad: (ad, e) {
          unawaited(ad.dispose());
          completer.completeError(loadErrorFrom(e));
        },
        onAdOpened: (_) => handle._events.add(ViewAdEvent.opened),
        onAdClosed: (_) => handle._events.add(ViewAdEvent.closed),
        onAdImpression: (_) => handle._events.add(ViewAdEvent.impression),
        onAdClicked: (_) => handle._events.add(ViewAdEvent.clicked),
        onPaidEvent: (ad, valueMicros, precision, currencyCode) =>
            handle._paid.add(
              AdPaidEvent(
                adUnitId: spec.adUnitId,
                valueMicros: valueMicros,
                currencyCode: currencyCode,
                precision: revenuePrecisionFrom(precision),
              ),
            ),
      ),
    );
    handle = _GmaBannerHandle(spec.adUnitId, ad);
    await ad.load();
    return completer.future;
  }

  Future<void> _finishBannerLoad(
    _GmaBannerHandle handle,
    BannerLoadSpec spec,
    Completer<BannerHandle> completer,
  ) async {
    var size = AdDimensions(
      width: handle._ad.size.width.toDouble(),
      height: handle._ad.size.height.toDouble(),
    );
    if (spec.size is InlineAdaptiveSizeSpec) {
      // Inline adaptive banners get their real height only after load.
      try {
        final platformSize = await handle._ad.getPlatformAdSize();
        if (platformSize != null) {
          size = AdDimensions(
            width: platformSize.width.toDouble(),
            height: platformSize.height.toDouble(),
          );
        }
      } catch (_) {
        // Keep the requested size; a wrong reserved height is recoverable,
        // a failed load is not.
      }
    }
    var collapsible = false;
    if (spec.collapsible != null) {
      try {
        collapsible = await handle._ad.isCollapsible;
      } catch (_) {
        collapsible = false;
      }
    }
    handle._size = size;
    handle._isCollapsible = collapsible;
    completer.complete(handle);
  }

  Future<gma.AdSize> _resolveBannerAdSize(BannerSizeSpec spec) async {
    switch (spec) {
      case AnchoredAdaptiveSizeSpec(:final width, :final orientation):
        final gma.AdSize? size = orientation == null
            ? await gma.AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)
            : await gma.AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
                toGmaOrientation(orientation),
                width,
              );
        if (size == null) {
          throw const AdFlowError(
            AdFlowErrorKind.loadFailed,
            'Could not resolve an anchored adaptive banner size for this '
            'device/width.',
          );
        }
        return size;
      case InlineAdaptiveSizeSpec(
        :final width,
        :final maxHeight,
        :final orientation,
      ):
        if (maxHeight != null) {
          return gma.AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight);
        }
        return switch (orientation) {
          null =>
            gma.AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width),
          AdOrientation.portrait =>
            gma.AdSize.getPortraitInlineAdaptiveBannerAdSize(width),
          AdOrientation.landscape =>
            gma.AdSize.getLandscapeInlineAdaptiveBannerAdSize(width),
        };
      case FixedSizeSpec(:final size):
        return toGmaFixedAdSize(size);
    }
  }

  @override
  Future<NativeHandle> loadNative(NativeLoadSpec spec) async {
    final completer = Completer<NativeHandle>();
    late final _GmaNativeHandle handle;
    final ad = gma.NativeAd(
      adUnitId: spec.adUnitId,
      request: toGmaAdRequest(spec.request),
      factoryId: spec.factoryId,
      customOptions: spec.factoryExtras,
      nativeTemplateStyle: spec.templateKind == null
          ? null
          : gma.NativeTemplateStyle(
              templateType: toGmaTemplateType(spec.templateKind!),
            ),
      listener: gma.NativeAdListener(
        onAdLoaded: (_) => completer.complete(handle),
        onAdFailedToLoad: (ad, e) {
          unawaited(ad.dispose());
          completer.completeError(loadErrorFrom(e));
        },
        onAdOpened: (_) => handle._events.add(ViewAdEvent.opened),
        onAdClosed: (_) => handle._events.add(ViewAdEvent.closed),
        onAdImpression: (_) => handle._events.add(ViewAdEvent.impression),
        onAdClicked: (_) => handle._events.add(ViewAdEvent.clicked),
        onPaidEvent: (ad, valueMicros, precision, currencyCode) =>
            handle._paid.add(
              AdPaidEvent(
                adUnitId: spec.adUnitId,
                valueMicros: valueMicros,
                currencyCode: currencyCode,
                precision: revenuePrecisionFrom(precision),
              ),
            ),
      ),
    );
    handle = _GmaNativeHandle(spec.adUnitId, ad);
    await ad.load();
    return completer.future;
  }

  @override
  Stream<AppForegroundEvent> get appForegroundEvents {
    // The plugin requires startListening() before the platform emits events.
    if (!_appStateListening) {
      _appStateListening = true;
      unawaited(gma.AppStateEventNotifier.startListening());
    }
    return gma.AppStateEventNotifier.appStateStream
        .where((state) => state == gma.AppState.foreground)
        .map((_) => const AppForegroundEvent());
  }

  @override
  Future<AdInspectorResult> openAdInspector() {
    final completer = Completer<AdInspectorResult>();
    gma.MobileAds.instance.openAdInspector((error) {
      completer.complete(
        AdInspectorResult(
          error: error == null
              ? null
              : AdFlowError(
                  AdFlowErrorKind.unknown,
                  error.message ?? 'Ad inspector error',
                  domain: error.domain,
                ),
        ),
      );
    });
    return completer.future;
  }

  @override
  Future<void> requestConsentInfoUpdate({
    bool? tagForUnderAgeOfConsent,
    ConsentDebugOptions? debug,
  }) {
    final completer = Completer<void>();
    gma.ConsentInformation.instance.requestConsentInfoUpdate(
      gma.ConsentRequestParameters(
        tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
        consentDebugSettings: debug == null
            ? null
            : gma.ConsentDebugSettings(
                debugGeography: toGmaDebugGeography(debug.geography),
                testIdentifiers: debug.testIdentifiers,
              ),
      ),
      completer.complete,
      (error) => completer.completeError(consentErrorFrom(error)),
    );
    return completer.future;
  }

  @override
  Future<bool> canRequestAds() =>
      gma.ConsentInformation.instance.canRequestAds();

  @override
  Future<AdConsentStatus> getConsentStatus() async => consentStatusFrom(
    await gma.ConsentInformation.instance.getConsentStatus(),
  );

  @override
  Future<bool> isConsentFormAvailable() =>
      gma.ConsentInformation.instance.isConsentFormAvailable();

  @override
  Future<PrivacyOptionsRequirement> getPrivacyOptionsRequirementStatus() async =>
      privacyRequirementFrom(
        await gma.ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus(),
      );

  @override
  Future<void> loadAndShowConsentFormIfRequired() {
    final completer = Completer<void>();
    gma.ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        completer.completeError(consentErrorFrom(error));
      } else {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    gma.ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) {
        completer.completeError(consentErrorFrom(error));
      } else {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  Future<void> resetConsent() => gma.ConsentInformation.instance.reset();
}

// ── Pure mappers (unit-tested without platform channels) ─────────────────

/// Maps seam request options (plus optional pre-merged [extras]) to the
/// plugin's `AdRequest`.
gma.AdRequest toGmaAdRequest(
  AdRequestOptions options, {
  Map<String, String>? extras,
}) {
  return gma.AdRequest(
    keywords: options.keywords,
    contentUrl: options.contentUrl,
    neighboringContentUrls: options.neighboringContentUrls,
    nonPersonalizedAds: options.nonPersonalizedAds,
    extras: extras ?? options.extras,
  );
}

/// Merges the collapsible placement into request extras.
Map<String, String>? mergeCollapsibleExtras(
  Map<String, String>? extras,
  CollapsiblePlacement? collapsible,
) {
  if (collapsible == null) return extras;
  return {...?extras, 'collapsible': collapsible.name};
}

/// Maps the seam request configuration to the plugin's.
gma.RequestConfiguration toGmaRequestConfiguration(AdRequestConfig config) {
  return gma.RequestConfiguration(
    testDeviceIds: config.testDeviceIds,
    maxAdContentRating: config.maxAdContentRating == null
        ? null
        : toGmaMaxContentRating(config.maxAdContentRating!),
    tagForChildDirectedTreatment: toGmaTag(
      config.tagForChildDirectedTreatment,
    ),
    tagForUnderAgeOfConsent: toGmaTag(config.tagForUnderAgeOfConsent),
  );
}

/// Maps a rating to the plugin's string constant.
String toGmaMaxContentRating(MaxContentRating rating) => switch (rating) {
  MaxContentRating.g => gma.MaxAdContentRating.g,
  MaxContentRating.pg => gma.MaxAdContentRating.pg,
  MaxContentRating.t => gma.MaxAdContentRating.t,
  MaxContentRating.ma => gma.MaxAdContentRating.ma,
};

/// Maps a nullable bool tag to the plugin's int encoding (null = omit).
int? toGmaTag(bool? tag) => switch (tag) {
  null => null,
  true => 1,
  false => 0,
};

/// Maps a fixed banner size to the plugin's constant.
gma.AdSize toGmaFixedAdSize(FixedBannerSize size) => switch (size) {
  FixedBannerSize.banner => gma.AdSize.banner,
  FixedBannerSize.largeBanner => gma.AdSize.largeBanner,
  FixedBannerSize.mediumRectangle => gma.AdSize.mediumRectangle,
  FixedBannerSize.fullBanner => gma.AdSize.fullBanner,
  FixedBannerSize.leaderboard => gma.AdSize.leaderboard,
};

/// Maps a seam orientation to Flutter's.
Orientation toGmaOrientation(AdOrientation orientation) =>
    switch (orientation) {
      AdOrientation.portrait => Orientation.portrait,
      AdOrientation.landscape => Orientation.landscape,
    };

/// Maps seam SSV options to the plugin's.
gma.ServerSideVerificationOptions toGmaSsvOptions(ServerSideVerification ssv) =>
    gma.ServerSideVerificationOptions(
      userId: ssv.userId,
      customData: ssv.customData,
    );

/// Maps a template kind to the plugin's.
gma.TemplateType toGmaTemplateType(NativeTemplateKind kind) => switch (kind) {
  NativeTemplateKind.small => gma.TemplateType.small,
  NativeTemplateKind.medium => gma.TemplateType.medium,
};

/// Maps the plugin's revenue precision to the seam's.
AdRevenuePrecision revenuePrecisionFrom(gma.PrecisionType precision) =>
    switch (precision) {
      gma.PrecisionType.unknown => AdRevenuePrecision.unknown,
      gma.PrecisionType.estimated => AdRevenuePrecision.estimated,
      gma.PrecisionType.publisherProvided =>
        AdRevenuePrecision.publisherProvided,
      gma.PrecisionType.precise => AdRevenuePrecision.precise,
    };

/// Maps the plugin's consent status to the seam's.
AdConsentStatus consentStatusFrom(gma.ConsentStatus status) =>
    switch (status) {
      gma.ConsentStatus.unknown => AdConsentStatus.unknown,
      gma.ConsentStatus.required => AdConsentStatus.required,
      gma.ConsentStatus.notRequired => AdConsentStatus.notRequired,
      gma.ConsentStatus.obtained => AdConsentStatus.obtained,
    };

/// Maps the plugin's privacy-options requirement to the seam's.
PrivacyOptionsRequirement privacyRequirementFrom(
  gma.PrivacyOptionsRequirementStatus status,
) => switch (status) {
  gma.PrivacyOptionsRequirementStatus.unknown =>
    PrivacyOptionsRequirement.unknown,
  gma.PrivacyOptionsRequirementStatus.required =>
    PrivacyOptionsRequirement.required,
  gma.PrivacyOptionsRequirementStatus.notRequired =>
    PrivacyOptionsRequirement.notRequired,
};

/// Maps a seam debug geography to the plugin's.
gma.DebugGeography toGmaDebugGeography(ConsentDebugGeography geography) =>
    switch (geography) {
      ConsentDebugGeography.disabled =>
        gma.DebugGeography.debugGeographyDisabled,
      ConsentDebugGeography.eea => gma.DebugGeography.debugGeographyEea,
      ConsentDebugGeography.regulatedUsState =>
        gma.DebugGeography.debugGeographyRegulatedUsState,
      ConsentDebugGeography.other => gma.DebugGeography.debugGeographyOther,
    };

/// Builds a typed load error from the plugin's.
AdFlowError loadErrorFrom(gma.LoadAdError error) => AdFlowError(
  AdFlowErrorKind.loadFailed,
  error.message,
  code: error.code,
  domain: error.domain,
);

/// Builds a typed show error from the plugin's.
AdFlowError showErrorFrom(gma.AdError error) => AdFlowError(
  AdFlowErrorKind.showFailed,
  error.message,
  code: error.code,
  domain: error.domain,
);

/// Builds a typed consent error from a UMP form error.
AdFlowError consentErrorFrom(gma.FormError error) => AdFlowError(
  AdFlowErrorKind.consent,
  error.message,
  code: error.errorCode,
);

// ── Handles ───────────────────────────────────────────────────────────────

/// Shared full-screen handle plumbing over a `gma.AdWithoutView` subtype.
abstract class _GmaFullScreenHandle<T extends gma.AdWithoutView> {
  _GmaFullScreenHandle(this.adUnitId, this._ad) {
    _ad.onPaidEvent = (ad, valueMicros, precision, currencyCode) =>
        _paid.add(
          AdPaidEvent(
            adUnitId: adUnitId,
            valueMicros: valueMicros,
            currencyCode: currencyCode,
            precision: revenuePrecisionFrom(precision),
          ),
        );
  }

  final String adUnitId;
  final T _ad;
  final _content = StreamController<FullScreenAdEvent>.broadcast();
  final _paid = StreamController<AdPaidEvent>.broadcast();

  Stream<FullScreenAdEvent> get contentEvents => _content.stream;

  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  /// The plugin's content callback, mapped onto [contentEvents].
  gma.FullScreenContentCallback<T> contentCallback() =>
      gma.FullScreenContentCallback<T>(
        onAdShowedFullScreenContent: (_) => _content.add(const AdShowedEvent()),
        onAdDismissedFullScreenContent: (_) =>
            _content.add(const AdDismissedEvent()),
        onAdFailedToShowFullScreenContent: (_, e) =>
            _content.add(AdFailedToShowEvent(showErrorFrom(e))),
        onAdImpression: (_) => _content.add(const AdImpressionEvent()),
        onAdClicked: (_) => _content.add(const AdClickedEvent()),
      );

  gma.OnUserEarnedRewardCallback wrapReward(
    OnUserEarnedReward? onUserEarnedReward,
  ) =>
      (ad, item) => onUserEarnedReward?.call(
        RewardEarned(amount: item.amount, type: item.type),
      );

  Future<void> dispose() async {
    await _ad.dispose();
    await _content.close();
    await _paid.close();
  }
}

class _GmaInterstitialHandle extends _GmaFullScreenHandle<gma.InterstitialAd>
    implements InterstitialHandle {
  _GmaInterstitialHandle(super.adUnitId, super.ad) {
    _ad.fullScreenContentCallback = contentCallback();
  }

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) => _ad.show();
}

class _GmaRewardedHandle extends _GmaFullScreenHandle<gma.RewardedAd>
    implements RewardedHandle {
  _GmaRewardedHandle(super.adUnitId, super.ad) {
    _ad.fullScreenContentCallback = contentCallback();
  }

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) =>
      _ad.show(onUserEarnedReward: wrapReward(onUserEarnedReward));
}

class _GmaRewardedInterstitialHandle
    extends _GmaFullScreenHandle<gma.RewardedInterstitialAd>
    implements RewardedInterstitialHandle {
  _GmaRewardedInterstitialHandle(super.adUnitId, super.ad) {
    _ad.fullScreenContentCallback = contentCallback();
  }

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) =>
      _ad.show(onUserEarnedReward: wrapReward(onUserEarnedReward));
}

class _GmaAppOpenHandle extends _GmaFullScreenHandle<gma.AppOpenAd>
    implements AppOpenHandle {
  _GmaAppOpenHandle(super.adUnitId, super.ad) {
    _ad.fullScreenContentCallback = contentCallback();
  }

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) => _ad.show();
}

/// Shared view-ad handle plumbing (banner/native).
abstract class _GmaViewAdHandle {
  _GmaViewAdHandle(this.adUnitId);

  final String adUnitId;
  final _events = StreamController<ViewAdEvent>.broadcast();
  final _paid = StreamController<AdPaidEvent>.broadcast();

  Stream<ViewAdEvent> get events => _events.stream;

  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  gma.AdWithView get _adWithView;

  Widget buildWidget() => gma.AdWidget(ad: _adWithView);

  Future<void> dispose() async {
    await _adWithView.dispose();
    await _events.close();
    await _paid.close();
  }
}

class _GmaBannerHandle extends _GmaViewAdHandle implements BannerHandle {
  _GmaBannerHandle(super.adUnitId, this._ad);

  final gma.BannerAd _ad;

  AdDimensions _size = const AdDimensions(width: 0, height: 0);
  bool _isCollapsible = false;

  @override
  gma.AdWithView get _adWithView => _ad;

  @override
  AdDimensions get size => _size;

  @override
  bool get isCollapsible => _isCollapsible;
}

class _GmaNativeHandle extends _GmaViewAdHandle implements NativeHandle {
  _GmaNativeHandle(super.adUnitId, this._ad);

  final gma.NativeAd _ad;

  @override
  gma.AdWithView get _adWithView => _ad;
}
