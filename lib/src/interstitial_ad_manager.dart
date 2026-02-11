// Copyright 2024 - AdMob Integration Package
// Interstitial Ad Manager for full-screen interstitial ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_manager_mixin.dart';
import 'ad_sdk.dart';
import 'ads_enabled_manager.dart';
import 'ad_flow_logger.dart';

/// Callback for interstitial ad events
typedef InterstitialAdCallback = void Function(InterstitialAd ad);

/// Callback for interstitial ad errors
typedef InterstitialAdErrorCallback = void Function(LoadAdError error);

/// Manages interstitial ads with automatic loading and cooldown handling.
///
/// Features:
/// - Automatic ad preloading
/// - Cooldown period between ads
/// - Load retry with linear backoff
/// - FullScreenContentCallback handling
///
/// Example usage:
/// ```dart
/// final interstitialManager = InterstitialAdManager();
///
/// // Preload an interstitial
/// await interstitialManager.loadAd();
///
/// // Show when ready
/// if (interstitialManager.isLoaded) {
///   await interstitialManager.showAd(
///     onAdDismissed: () {
///       // Resume app
///     },
///   );
/// }
/// ```
class InterstitialAdManager
    with AdStatusNotifier, AdRetryHandler
    implements AdManager {
  InterstitialAd? _interstitialAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isShowing = false;
  DateTime? _lastShowTime;

  // Stored show callbacks — set in showAd(), consumed by fullscreen callbacks.
  // Prevents auto-preload's _setupFullScreenContentCallback() from
  // overwriting the user's callbacks.
  VoidCallback? _pendingOnAdDismissed;
  VoidCallback? _pendingOnAdFailedToShow;

  /// The currently loaded interstitial ad
  InterstitialAd? get interstitialAd => _interstitialAd;

  /// Whether an interstitial ad is currently loaded
  @override
  bool get isLoaded => _isLoaded;

  /// Whether an interstitial ad is currently loading
  @override
  bool get isLoading => _isLoading;

  /// Whether an interstitial ad is currently being shown
  @override
  bool get isShowing => _isShowing;

  /// Whether enough time has passed since the last interstitial
  bool get canShowAd {
    if (_lastShowTime == null) return true;
    final elapsed = DateTime.now().difference(_lastShowTime!);
    return elapsed >= AdFlowConfig.current.minInterstitialInterval;
  }

  /// Loads an interstitial ad.
  ///
  /// [adUnitId] can be provided to override the default ad unit ID.
  /// [onAdLoaded] is called when the ad is successfully loaded.
  /// [onAdFailedToLoad] is called if the ad fails to load.
  Future<void> loadAd({
    String? adUnitId,
    InterstitialAdCallback? onAdLoaded,
    InterstitialAdErrorCallback? onAdFailedToLoad,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      adFlowLog('InterstitialAdManager: Ads disabled, skipping load');
      return;
    }

    if (_isLoading || _isLoaded) {
      adFlowLog(
        'InterstitialAdManager: Already loading or loaded, skipping...',
      );
      return;
    }

    _isLoading = true;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      adFlowLog('InterstitialAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'InterstitialAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    adFlowLog('InterstitialAdManager: Loading interstitial ad...');

    await AdSdk.instance.loadInterstitialAd(
      adUnitId: adUnitId ?? AdFlowConfig.current.interstitialAdUnitId,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onLoaded: (InterstitialAd ad) {
        adFlowLog('InterstitialAdManager: Ad loaded successfully');
        _interstitialAd = ad;
        _isLoaded = true;
        _isLoading = false;
        resetRetryAttempts();

        // Set up full screen content callbacks
        _setupFullScreenContentCallback();

        onAdLoaded?.call(ad);
        notifyStatusListeners();
      },
      onFailed: (LoadAdError error) {
        adFlowLog('InterstitialAdManager: Ad failed to load: ${error.message}');
        _isLoaded = false;
        _isLoading = false;
        notifyStatusListeners();

        // Report error to centralized handler
        AdFlowErrorHandler.instance.reportLoadError(
          error,
          type: AdErrorType.interstitialLoad,
          adUnitId: adUnitId ?? AdFlowConfig.current.interstitialAdUnitId,
        );

        // Retry loading with linear backoff
        final retried = handleLoadFailure(
          checkDisposed: () => isDisposed,
          onRetry: () => loadAd(adUnitId: adUnitId),
          managerName: 'InterstitialAdManager',
        );

        // Only report to callback when all retries exhausted
        if (!retried) {
          onAdFailedToLoad?.call(error);
        }
      },
    );
  }

  /// Sets up the full screen content callbacks.
  ///
  /// Reads dismiss/fail callbacks from [_pendingOnAdDismissed] and
  /// [_pendingOnAdFailedToShow] instance fields so that auto-preload
  /// (which calls this with no arguments) cannot overwrite user callbacks.
  void _setupFullScreenContentCallback() {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad ad) {
        adFlowLog('InterstitialAdManager: Ad showed full screen content');
        _isShowing = true;
        notifyStatusListeners();
      },
      onAdDismissedFullScreenContent: (Ad ad) {
        adFlowLog('InterstitialAdManager: Ad dismissed');
        _isShowing = false;
        _lastShowTime = DateTime.now();
        // Capture and clear callbacks before any side-effects
        final onDismissed = _pendingOnAdDismissed;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _interstitialAd = null;
        _isLoaded = false;
        notifyStatusListeners();
        onDismissed?.call();

        // Preload next ad
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        adFlowLog('InterstitialAdManager: Ad failed to show: ${error.message}');
        _isShowing = false;
        // Capture and clear callbacks before any side-effects
        final onFailed = _pendingOnAdFailedToShow;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _interstitialAd = null;
        _isLoaded = false;
        notifyStatusListeners();

        // Report show error to centralized handler
        AdFlowErrorHandler.instance.reportError(
          AdFlowError(
            type: AdErrorType.interstitialShow,
            code: error.code,
            message: error.message,
          ),
        );

        onFailed?.call();

        // Try to load another ad
        loadAd();
      },
      onAdImpression: (Ad ad) {
        adFlowLog('InterstitialAdManager: Ad impression recorded');
      },
      onAdClicked: (Ad ad) {
        adFlowLog('InterstitialAdManager: Ad clicked');
      },
      // iOS only - called before dismissing full screen content
      onAdWillDismissFullScreenContent: (Ad ad) {
        adFlowLog('InterstitialAdManager: Ad will dismiss (iOS)');
      },
    );
  }

  /// Shows the loaded interstitial ad.
  ///
  /// Returns `true` if the ad was shown, `false` otherwise.
  ///
  /// [onAdDismissed] is called when the ad is dismissed.
  /// [onAdFailedToShow] is called if the ad fails to show.
  /// [ignoreCooldown] if true, shows the ad even if cooldown hasn't elapsed.
  Future<bool> showAd({
    VoidCallback? onAdDismissed,
    VoidCallback? onAdFailedToShow,
    bool ignoreCooldown = false,
  }) async {
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      adFlowLog('InterstitialAdManager: Ads disabled, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    if (!_isLoaded || _interstitialAd == null) {
      adFlowLog('InterstitialAdManager: No ad loaded to show');
      onAdFailedToShow?.call();
      return false;
    }

    if (!ignoreCooldown && !canShowAd) {
      adFlowLog('InterstitialAdManager: Cooldown period not elapsed');
      onAdFailedToShow?.call();
      return false;
    }

    if (_isShowing) {
      adFlowLog('InterstitialAdManager: Ad already showing');
      return false;
    }

    // Check consent hasn't been revoked since the ad was loaded
    if (!await AdSdk.instance.canRequestAds()) {
      adFlowLog('InterstitialAdManager: Consent revoked, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    // Store callbacks as instance fields — fullscreen callbacks read from these
    _pendingOnAdDismissed = onAdDismissed;
    _pendingOnAdFailedToShow = onAdFailedToShow;
    _setupFullScreenContentCallback();

    adFlowLog('InterstitialAdManager: Showing ad...');
    await _interstitialAd!.show();
    return true;
  }

  /// Disposes of the current interstitial ad.
  @override
  Future<void> dispose() async {
    disposeNotifier();
    cancelRetryTimer();
    await _interstitialAd?.dispose();
    _interstitialAd = null;
    _isLoaded = false;
    _isLoading = false;
    _isShowing = false;
    _lastShowTime = null;
    _pendingOnAdDismissed = null;
    _pendingOnAdFailedToShow = null;
  }
}
