// Copyright 2024 - AdMob Integration Package
// App Open Ad Manager for full-screen app open ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_manager_mixin.dart';
import 'ad_sdk.dart';
import 'ads_enabled_manager.dart';

/// Callback for app open ad events
typedef AppOpenAdCallback = void Function(AppOpenAd ad);

/// Callback for app open ad errors
typedef AppOpenAdErrorCallback = void Function(LoadAdError error);

/// Manages app open ads that display when users bring your app to the foreground.
///
/// Features:
/// - Automatic ad loading and caching
/// - Cache expiration handling (max 4 hours as per Google recommendation)
/// - App lifecycle awareness
/// - Cold start support
///
/// Example usage:
/// ```dart
/// final appOpenManager = AppOpenAdManager();
///
/// // Load an app open ad
/// await appOpenManager.loadAd();
///
/// // Show when app comes to foreground
/// if (appOpenManager.isAdAvailable) {
///   await appOpenManager.showAdIfAvailable();
/// }
/// ```
class AppOpenAdManager
    with AdStatusNotifier, AdRetryHandler
    implements AdManager {
  AppOpenAd? _appOpenAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isShowing = false;
  DateTime? _loadTime;
  Completer<bool>? _loadCompleter;

  // Stored show callbacks — set in showAdIfAvailable(), consumed by fullscreen callbacks.
  VoidCallback? _pendingOnAdDismissed;
  VoidCallback? _pendingOnAdFailedToShow;

  /// The currently loaded app open ad
  AppOpenAd? get appOpenAd => _appOpenAd;

  /// Whether an app open ad is currently loaded
  @override
  bool get isLoaded => _isLoaded;

  /// Whether an app open ad is currently loading
  @override
  bool get isLoading => _isLoading;

  /// Whether an app open ad is currently being shown
  @override
  bool get isShowing => _isShowing;

  /// Whether an ad is available to show (loaded and not expired)
  bool get isAdAvailable {
    if (!_isLoaded || _appOpenAd == null) return false;
    return !_isAdExpired;
  }

  /// Whether the cached ad has expired (older than max cache duration)
  bool get _isAdExpired {
    if (_loadTime == null) return true;
    final elapsed = DateTime.now().difference(_loadTime!);
    return elapsed >= AdFlowConfig.current.appOpenAdMaxCacheDuration;
  }

  /// Loads an app open ad.
  ///
  /// [adUnitId] can be provided to override the default ad unit ID.
  /// [onAdLoaded] is called when the ad is successfully loaded.
  /// [onAdFailedToLoad] is called if the ad fails to load.
  Future<void> loadAd({
    String? adUnitId,
    AppOpenAdCallback? onAdLoaded,
    AppOpenAdErrorCallback? onAdFailedToLoad,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('AppOpenAdManager: Ads disabled, skipping load');
      return;
    }

    // If already loading, wait for existing load
    if (_isLoading && _loadCompleter != null) {
      debugPrint(
        'AppOpenAdManager: Already loading, waiting for existing load...',
      );
      return;
    }

    // Don't load if we already have a valid ad
    if (isAdAvailable) {
      debugPrint('AppOpenAdManager: Ad already loaded and valid');
      return;
    }

    // Dispose expired ad if exists
    if (_isLoaded && _isAdExpired) {
      debugPrint('AppOpenAdManager: Disposing expired ad');
      await _disposeCurrentAd();
    }

    _isLoading = true;
    _loadCompleter = Completer<bool>();
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('AppOpenAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      _loadCompleter?.complete(false);
      _loadCompleter = null;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'AppOpenAdManager')) {
      _isLoading = false;
      _loadCompleter?.complete(false);
      _loadCompleter = null;
      notifyStatusListeners();
      return;
    }

    debugPrint('AppOpenAdManager: Loading app open ad...');

    await AdSdk.instance.loadAppOpenAd(
      adUnitId: adUnitId ?? AdFlowConfig.current.appOpenAdUnitId,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onLoaded: (AppOpenAd ad) {
        debugPrint('AppOpenAdManager: Ad loaded successfully');
        _appOpenAd = ad;
        _isLoaded = true;
        _isLoading = false;
        _loadTime = DateTime.now();
        resetRetryAttempts();

        // Set up full screen content callbacks
        _setupFullScreenContentCallback();

        // Complete the load completer
        if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
          _loadCompleter!.complete(true);
        }

        onAdLoaded?.call(ad);
        notifyStatusListeners();
      },
      onFailed: (LoadAdError error) {
        debugPrint('AppOpenAdManager: Ad failed to load: ${error.message}');
        _isLoaded = false;
        _isLoading = false;

        // Complete the load completer with failure
        if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
          _loadCompleter!.complete(false);
        }

        // Report error to centralized handler
        AdFlowErrorHandler.instance.reportLoadError(
          error,
          type: AdErrorType.appOpenLoad,
          adUnitId: adUnitId ?? AdFlowConfig.current.appOpenAdUnitId,
        );

        notifyStatusListeners();

        // Retry loading with linear backoff
        final retried = handleLoadFailure(
          checkDisposed: () => isDisposed,
          onRetry: () => loadAd(adUnitId: adUnitId),
          managerName: 'AppOpenAdManager',
        );

        // Only report to callback when all retries exhausted
        if (!retried) {
          onAdFailedToLoad?.call(error);
        }
      },
    );
  }

  /// Loads an app open ad and waits for it to complete.
  /// Returns true if ad loaded successfully, false otherwise.
  Future<bool> loadAdAndWait({String? adUnitId}) async {
    debugPrint('AppOpenAdManager: loadAdAndWait called');

    // Already have a valid ad
    if (isAdAvailable) {
      debugPrint('AppOpenAdManager: Ad already available');
      return true;
    }

    // If already loading, wait for that to complete
    if (_isLoading && _loadCompleter != null && !_loadCompleter!.isCompleted) {
      debugPrint(
        'AppOpenAdManager: Already loading, waiting for completion...',
      );
      return await _loadCompleter!.future;
    }

    // Start a new load
    await loadAd(adUnitId: adUnitId);

    // Wait for the load to complete
    if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
      debugPrint('AppOpenAdManager: Waiting for load completer...');
      return await _loadCompleter!.future;
    }

    // Check if ad is now available
    return isAdAvailable;
  }

  /// Sets up the full screen content callbacks.
  ///
  /// Reads dismiss/fail callbacks from [_pendingOnAdDismissed] and
  /// [_pendingOnAdFailedToShow] instance fields so that auto-preload
  /// cannot overwrite the user's callbacks.
  void _setupFullScreenContentCallback() {
    _appOpenAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad ad) {
        debugPrint('AppOpenAdManager: Ad showed full screen content');
        _isShowing = true;
        notifyStatusListeners();
      },
      onAdDismissedFullScreenContent: (Ad ad) {
        debugPrint('AppOpenAdManager: Ad dismissed');
        _isShowing = false;
        final onDismissed = _pendingOnAdDismissed;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _appOpenAd = null;
        _isLoaded = false;
        _loadTime = null;
        notifyStatusListeners();
        onDismissed?.call();

        // Preload next ad
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        debugPrint('AppOpenAdManager: Ad failed to show: ${error.message}');
        _isShowing = false;
        final onFailed = _pendingOnAdFailedToShow;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _appOpenAd = null;
        _isLoaded = false;
        _loadTime = null;
        notifyStatusListeners();

        // Report show error to centralized handler
        AdFlowErrorHandler.instance.reportError(
          AdFlowError(
            type: AdErrorType.appOpenShow,
            code: error.code,
            message: error.message,
          ),
        );

        onFailed?.call();

        // Try to load another ad
        loadAd();
      },
      onAdImpression: (Ad ad) {
        debugPrint('AppOpenAdManager: Ad impression recorded');
      },
      onAdClicked: (Ad ad) {
        debugPrint('AppOpenAdManager: Ad clicked');
      },
      // iOS only - called before dismissing full screen content
      onAdWillDismissFullScreenContent: (Ad ad) {
        debugPrint('AppOpenAdManager: Ad will dismiss (iOS)');
      },
    );
  }

  /// Shows the app open ad if one is available.
  ///
  /// Returns `true` if the ad was shown, `false` otherwise.
  ///
  /// [onAdDismissed] is called when the ad is dismissed.
  /// [onAdFailedToShow] is called if the ad fails to show.
  Future<bool> showAdIfAvailable({
    VoidCallback? onAdDismissed,
    VoidCallback? onAdFailedToShow,
  }) async {
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('AppOpenAdManager: Ads disabled, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    if (!isAdAvailable) {
      debugPrint('AppOpenAdManager: No ad available to show');
      // Try to load one for next time
      loadAd();
      onAdFailedToShow?.call();
      return false;
    }

    if (_isShowing) {
      debugPrint('AppOpenAdManager: Ad already showing');
      return false;
    }

    // Check if ad is expired
    if (_isAdExpired) {
      debugPrint('AppOpenAdManager: Ad expired, loading new one');
      await _disposeCurrentAd();
      loadAd();
      onAdFailedToShow?.call();
      return false;
    }

    // Check consent hasn't been revoked since the ad was loaded
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('AppOpenAdManager: Consent revoked, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    // Store callbacks as instance fields — fullscreen callbacks read from these
    _pendingOnAdDismissed = onAdDismissed;
    _pendingOnAdFailedToShow = onAdFailedToShow;
    _setupFullScreenContentCallback();

    debugPrint('AppOpenAdManager: Showing ad...');
    await _appOpenAd!.show();
    return true;
  }

  /// Disposes only the current ad object, preserving listeners and retry state.
  ///
  /// Used when disposing expired ads — the manager stays alive but the
  /// previous ad is cleaned up.
  Future<void> _disposeCurrentAd() async {
    await _appOpenAd?.dispose();
    _appOpenAd = null;
    _isLoaded = false;
    _loadTime = null;
  }

  /// Disposes of the current app open ad.
  @override
  Future<void> dispose() async {
    disposeNotifier();
    cancelRetryTimer();
    // Complete any pending loadCompleter to unblock waiters
    if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
      _loadCompleter!.complete(false);
    }
    await _appOpenAd?.dispose();
    _appOpenAd = null;
    _isLoaded = false;
    _isLoading = false;
    _isShowing = false;
    _loadTime = null;
    _loadCompleter = null;
    _pendingOnAdDismissed = null;
    _pendingOnAdFailedToShow = null;
  }
}
