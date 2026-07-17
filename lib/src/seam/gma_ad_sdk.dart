import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart'
    as att;
import 'package:flutter/foundation.dart';
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
    await _dispatchFullScreenLoad(
      () => gma.InterstitialAd.load(
        adUnitId: adUnitId,
        request: toGmaAdRequest(options),
        adLoadCallback: gma.InterstitialAdLoadCallback(
          onAdLoaded: (ad) =>
              completer.complete(_GmaInterstitialHandle(adUnitId, ad)),
          onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
        ),
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
    await _dispatchFullScreenLoad(
      () => gma.RewardedAd.load(
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
    await _dispatchFullScreenLoad(
      () => gma.RewardedInterstitialAd.load(
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
              onAdFailedToLoad: (e) =>
                  completer.completeError(loadErrorFrom(e)),
            ),
      ),
    );
    return completer.future;
  }

  /// Known upstream limitation (plugin 9.0.0, verified in
  /// `ad_instance_manager.dart`'s `_invokeOnAdFailedToLoad`): on a FAILED
  /// load the plugin auto-disposes interstitial/rewarded/rewarded-
  /// interstitial ads but NOT `AppOpenAd`, and the failure callback carries
  /// no ad reference — so each failed app-open load leaks one plugin-side ad
  /// entry that this seam cannot release. Re-check when bumping the plugin;
  /// see RESEARCH.md §3.
  @override
  Future<AppOpenHandle> loadAppOpen(
    String adUnitId,
    AdRequestOptions options,
  ) async {
    final completer = Completer<AppOpenHandle>();
    await _dispatchFullScreenLoad(
      () => gma.AppOpenAd.load(
        adUnitId: adUnitId,
        request: toGmaAdRequest(options),
        adLoadCallback: gma.AppOpenAdLoadCallback(
          onAdLoaded: (ad) =>
              completer.complete(_GmaAppOpenHandle(adUnitId, ad)),
          onAdFailedToLoad: (e) => completer.completeError(loadErrorFrom(e)),
        ),
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
        onAdLoaded: (_) =>
            unawaited(_finishBannerLoad(handle, spec, completer)),
        onAdFailedToLoad: (ad, e) {
          // Like onAdLoaded, BannerAdListener.onAdFailedToLoad fires on every
          // AdMob-driven auto-refresh of this SAME BannerAd — not just the
          // initial load. A refresh that fails (routine on a weak network) is
          // NOT a load failure: the SDK keeps the previously loaded creative
          // on screen and retries on its own schedule.
          //
          // Tearing down here unconditionally was the symmetric hole to review
          // finding #2: it disposed the LIVE, mounted banner (leaving the
          // mounted AdWidget hosting a destroyed ad), closed the handle's
          // streams (silently ending paid-event/revenue reporting for the
          // placement), and called completeError() on an already-completed
          // Completer — "Bad state: Future already completed", an unhandled
          // async error, on every failed refresh cycle.
          if (completer.isCompleted) return;
          unawaited(ad.dispose());
          // handle's two StreamControllers are constructed eagerly, before
          // ad.load() even runs, so a failed load must still close them —
          // otherwise they're simply dropped unclosed once this function
          // returns (nit flagged alongside review finding #2's audit).
          unawaited(handle._events.close());
          unawaited(handle._paid.close());
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
                adSourceName: summarizeResponseInfo(
                  ad.responseInfo,
                )?.adSourceName,
              ),
            ),
      ),
    );
    handle = _GmaBannerHandle(spec.adUnitId, ad);
    await _dispatchViewLoad(ad, handle._events, handle._paid);
    return completer.future;
  }

  /// Dispatches `ad.load()` for a view ad, normalizing a raw channel throw.
  ///
  /// The load DISPATCH itself is a method-channel invoke that can reject with
  /// a raw `PlatformException` (a native error constructing the ad) — a path
  /// the `onAdFailedToLoad` callback mapping never sees. The seam contract
  /// says load failures are `AdFlowError`s, and the handle's two eagerly
  /// constructed stream controllers must not be dropped unclosed (the same
  /// leak ADR-026 nit #13 closed on the callback path). 2026-07 audit.
  Future<void> _dispatchViewLoad(
    gma.AdWithView ad,
    StreamController<ViewAdEvent> events,
    StreamController<AdPaidEvent> paid,
  ) async {
    try {
      await ad.load();
    } catch (e) {
      unawaited(ad.dispose());
      unawaited(events.close());
      unawaited(paid.close());
      throw asAdFlowError(e, AdFlowErrorKind.loadFailed);
    }
  }

  /// Normalizes a raw channel throw from a full-screen static `load` call
  /// (`InterstitialAd.load` etc. can reject with a raw `PlatformException`
  /// before any callback fires). The plugin holds no caller-visible ad
  /// reference on this path, so normalization is all the seam can do.
  static Future<T> _dispatchFullScreenLoad<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw asAdFlowError(e, AdFlowErrorKind.loadFailed);
    }
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
      // Inline adaptive banners get their real height only after load: the
      // plugin's InlineAdaptiveSize is constructed with HEIGHT 0 and is only
      // resolved by getPlatformAdSize() (see AdSize.getInlineAdaptiveBanner…
      // in the plugin — "an AdSize with the given width and 0 height").
      AdDimensions? resolved;
      try {
        final platformSize = await handle._ad.getPlatformAdSize();
        if (platformSize != null) {
          resolved = AdDimensions(
            width: platformSize.width.toDouble(),
            height: platformSize.height.toDouble(),
          );
        }
      } catch (_) {
        // Fall through to the failure path below.
      }
      if (resolved == null || resolved.height <= 0) {
        // On an AUTO-REFRESH (completer already completed) the ad on screen
        // is live, mounted and earning: a failed size query must keep the
        // last known size, never tear the ad down — the symmetric hole to
        // the onAdFailedToLoad refresh guard above (review finding #2,
        // 2026-07 audit).
        if (completer.isCompleted) return;
        // On the INITIAL load we cannot size the container, and the
        // requested size's height is 0. Rendering the ad anyway would put a
        // LOADED, BILLABLE creative in a zero-height box: an impression the
        // user can never see. Google's own guidance is to use
        // getPlatformAdSize() to size the container, so if it will not tell
        // us, treat this as a failed load — dispose the ad (no impression)
        // and let the controller's normal retry path run.
        unawaited(handle._ad.dispose());
        unawaited(handle._events.close());
        unawaited(handle._paid.close());
        completer.completeError(
          const AdFlowError(
            AdFlowErrorKind.loadFailed,
            'Could not resolve the inline adaptive banner height '
            '(getPlatformAdSize returned no size).',
          ),
        );
        return;
      }
      size = resolved;
    }
    var collapsible = false;
    if (spec.collapsible != null) {
      try {
        collapsible = await handle._ad.isCollapsible;
      } catch (_) {
        collapsible = false;
      }
    }
    // A ValueNotifier write: a refresh that resolves a DIFFERENT size (inline
    // adaptive creatives vary per refresh) notifies the hosting widget so it
    // can resize its box; an unchanged size no-ops.
    handle._dimensions.value = size;
    handle._isCollapsible = collapsible;
    // BannerAdListener.onAdLoaded fires on every AdMob-driven auto-refresh
    // of this BannerAd, not just the first load — still refresh the
    // handle's size/collapsible fields above, but only complete the
    // one-shot load Future once (review finding #2: a second completion
    // threw "Bad state: Future already completed" as an unhandled async
    // error on every refresh cycle).
    if (!completer.isCompleted) completer.complete(handle);
  }

  Future<gma.AdSize> _resolveBannerAdSize(BannerSizeSpec spec) async {
    switch (spec) {
      case AnchoredAdaptiveSizeSpec(:final width, :final orientation):
        final gma.AdSize? size = orientation == null
            ? await gma.AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)
            : await gma
                  .AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
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
          null => gma.AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(
            width,
          ),
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
          // See loadBanner's onAdFailedToLoad: never tear down an ad whose
          // load already succeeded, and never complete the Completer twice.
          if (completer.isCompleted) return;
          unawaited(ad.dispose());
          unawaited(handle._events.close());
          unawaited(handle._paid.close());
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
                adSourceName: summarizeResponseInfo(
                  ad.responseInfo,
                )?.adSourceName,
              ),
            ),
      ),
    );
    handle = _GmaNativeHandle(spec.adUnitId, ad);
    await _dispatchViewLoad(ad, handle._events, handle._paid);
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
  Future<PrivacyOptionsRequirement>
  getPrivacyOptionsRequirementStatus() async => privacyRequirementFrom(
    await gma.ConsentInformation.instance.getPrivacyOptionsRequirementStatus(),
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

  @override
  Future<AttStatus> getTrackingAuthorizationStatus() async {
    // Guard client-side so no channel call is made off iOS (the plugin also
    // returns notSupported there, but this keeps the seam honest and unit
    // testable via debugDefaultTargetPlatformOverride).
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return AttStatus.notSupported;
    }
    return attStatusFrom(
      await att.AppTrackingTransparency.trackingAuthorizationStatus,
    );
  }

  @override
  Future<AttStatus> requestTrackingAuthorization() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return AttStatus.notSupported;
    }
    return attStatusFrom(
      await att.AppTrackingTransparency.requestTrackingAuthorization(),
    );
  }
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
    tagForChildDirectedTreatment: toGmaTag(config.tagForChildDirectedTreatment),
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
AdConsentStatus consentStatusFrom(gma.ConsentStatus status) => switch (status) {
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
AdFlowError consentErrorFrom(gma.FormError error) =>
    AdFlowError(AdFlowErrorKind.consent, error.message, code: error.errorCode);

/// Summarizes the plugin's `ResponseInfo` into the seam's plugin-free
/// [AdResponseSummary] (null in, null out).
AdResponseSummary? summarizeResponseInfo(gma.ResponseInfo? info) {
  if (info == null) return null;
  final loaded = info.loadedAdapterResponseInfo;
  return AdResponseSummary(
    responseId: info.responseId,
    mediationAdapterClassName: info.mediationAdapterClassName,
    adSourceName: loaded?.adSourceName,
    adSourceInstanceName: loaded?.adSourceInstanceName,
  );
}

/// Maps the `app_tracking_transparency` status to the seam's [AttStatus].
AttStatus attStatusFrom(att.TrackingStatus status) => switch (status) {
  att.TrackingStatus.notDetermined => AttStatus.notDetermined,
  att.TrackingStatus.restricted => AttStatus.restricted,
  att.TrackingStatus.denied => AttStatus.denied,
  att.TrackingStatus.authorized => AttStatus.authorized,
  att.TrackingStatus.notSupported => AttStatus.notSupported,
};

// ── Handles ───────────────────────────────────────────────────────────────

/// Shared full-screen handle plumbing over a `gma.AdWithoutView` subtype.
abstract class _GmaFullScreenHandle<T extends gma.AdWithoutView> {
  _GmaFullScreenHandle(this.adUnitId, this._ad) {
    _ad.onPaidEvent = (ad, valueMicros, precision, currencyCode) => _paid.add(
      AdPaidEvent(
        adUnitId: adUnitId,
        valueMicros: valueMicros,
        currencyCode: currencyCode,
        precision: revenuePrecisionFrom(precision),
        // Read at event time — the winning source for THIS impression.
        adSourceName: summarizeResponseInfo(_ad.responseInfo)?.adSourceName,
      ),
    );
  }

  final String adUnitId;
  final T _ad;

  AdResponseSummary? get response => summarizeResponseInfo(_ad.responseInfo);
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

  @override
  Future<void> updateServerSideVerification(ServerSideVerification ssv) =>
      _updateSsv(() => _ad.setServerSideOptions(toGmaSsvOptions(ssv)));
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

  @override
  Future<void> updateServerSideVerification(ServerSideVerification ssv) =>
      _updateSsv(() => _ad.setServerSideOptions(toGmaSsvOptions(ssv)));
}

/// Normalizes an SSV attach failure — unlike the silent best-effort attach
/// during load (where failing the whole load over SSV would cost the ad),
/// an explicit update must SURFACE failure: the caller is about to grant a
/// high-value reward on the strength of this payload.
Future<void> _updateSsv(Future<void> Function() call) async {
  try {
    await call();
  } catch (e) {
    throw asAdFlowError(e, AdFlowErrorKind.unknown);
  }
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

  AdResponseSummary? get response =>
      summarizeResponseInfo(_adWithView.responseInfo);

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

  // Deliberately never disposed: the hosting widget may still be subscribed
  // when the controller swaps handles (it unsubscribes on its next build),
  // and a plain ValueNotifier holds no platform resources.
  final ValueNotifier<AdDimensions> _dimensions = ValueNotifier(
    const AdDimensions(width: 0, height: 0),
  );
  bool _isCollapsible = false;

  @override
  gma.AdWithView get _adWithView => _ad;

  @override
  AdDimensions get size => _dimensions.value;

  @override
  ValueListenable<AdDimensions> get dimensions => _dimensions;

  @override
  bool get isCollapsible => _isCollapsible;
}

class _GmaNativeHandle extends _GmaViewAdHandle implements NativeHandle {
  _GmaNativeHandle(super.adUnitId, this._ad);

  final gma.NativeAd _ad;

  @override
  gma.AdWithView get _adWithView => _ad;
}
