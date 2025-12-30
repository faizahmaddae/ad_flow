// Copyright 2024 - AdMob Integration Package
// Interstitial Ad Manager for full-screen interstitial ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ads_enabled_manager.dart';

/// Callback for interstitial ad events
typedef InterstitialAdCallback = void Function(InterstitialAd ad);

/// Callback for interstitial ad errors
typedef InterstitialAdErrorCallback = void Function(LoadAdError error);

/// Callback for when user earns reward (not used for interstitial, but for consistency)
typedef OnUserEarnedReward = void Function(AdWithoutView ad, RewardItem reward);

/// Manages interstitial ads with automatic loading and cooldown handling.
///
/// Features:
/// - Automatic ad preloading
/// - Cooldown period between ads
/// - Load retry with exponential backoff
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
class InterstitialAdManager {
  /// HTTP timeout for ad requests (30 seconds for better fill rate)
  static const int _kHttpTimeoutMillis = 30000;

  InterstitialAd? _interstitialAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isShowing = false;
  DateTime? _lastShowTime;
  int _loadAttempts = 0;

  /// Status listeners for reactive UI updates
  final List<VoidCallback> _statusListeners = [];

  /// Add a listener that will be called when the ad status changes
  void addStatusListener(VoidCallback listener) {
    _statusListeners.add(listener);
  }

  /// Remove a previously added listener
  void removeStatusListener(VoidCallback listener) {
    _statusListeners.remove(listener);
  }

  /// Notify all listeners of a status change
  void _notifyStatusListeners() {
    for (final listener in _statusListeners) {
      listener();
    }
  }

  /// The currently loaded interstitial ad
  InterstitialAd? get interstitialAd => _interstitialAd;

  /// Whether an interstitial ad is currently loaded
  bool get isLoaded => _isLoaded;

  /// Whether an interstitial ad is currently loading
  bool get isLoading => _isLoading;

  /// Whether an interstitial ad is currently being shown
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
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('InterstitialAdManager: Ads disabled, skipping load');
      return;
    }

    // Check consent before loading (Google best practice)
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('InterstitialAdManager: Cannot request ads (no consent)');
      return;
    }

    if (_isLoading || _isLoaded) {
      debugPrint(
        'InterstitialAdManager: Already loading or loaded, skipping...',
      );
      return;
    }

    _isLoading = true;
    _notifyStatusListeners();
    debugPrint('InterstitialAdManager: Loading interstitial ad...');

    await InterstitialAd.load(
      adUnitId: adUnitId ?? AdFlowConfig.current.interstitialAdUnitId,
      request: const AdRequest(
        httpTimeoutMillis:
            _kHttpTimeoutMillis, // Longer timeout for better fill rate
      ),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          debugPrint('InterstitialAdManager: Ad loaded successfully');
          _interstitialAd = ad;
          _isLoaded = true;
          _isLoading = false;
          _loadAttempts = 0;

          // Set up full screen content callbacks
          _setupFullScreenContentCallback();

          onAdLoaded?.call(ad);
          _notifyStatusListeners();
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint(
            'InterstitialAdManager: Ad failed to load: ${error.message}',
          );
          _isLoaded = false;
          _isLoading = false;
          _loadAttempts++;
          _notifyStatusListeners();

          // Report error to centralized handler
          AdFlowErrorHandler.instance.reportLoadError(
            error,
            type: AdErrorType.interstitialLoad,
            adUnitId: adUnitId ?? AdFlowConfig.current.interstitialAdUnitId,
          );

          // Retry loading if under max attempts
          if (_loadAttempts < AdFlowConfig.current.maxLoadRetries) {
            debugPrint(
              'InterstitialAdManager: Retrying load (attempt $_loadAttempts)...',
            );
            Future.delayed(
              AdFlowConfig.current.retryDelay * _loadAttempts,
              () => loadAd(adUnitId: adUnitId),
            );
          }

          onAdFailedToLoad?.call(error);
        },
      ),
    );
  }

  /// Sets up the full screen content callbacks.
  ///
  /// [onAdDismissed] optional callback when ad is dismissed by user.
  /// [onAdFailedToShow] optional callback when ad fails to show.
  void _setupFullScreenContentCallback({
    VoidCallback? onAdDismissed,
    VoidCallback? onAdFailedToShow,
  }) {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad ad) {
        debugPrint('InterstitialAdManager: Ad showed full screen content');
        _isShowing = true;
        _notifyStatusListeners();
      },
      onAdDismissedFullScreenContent: (Ad ad) {
        debugPrint('InterstitialAdManager: Ad dismissed');
        _isShowing = false;
        _lastShowTime = DateTime.now();
        ad.dispose();
        _interstitialAd = null;
        _isLoaded = false;
        _notifyStatusListeners();
        onAdDismissed?.call();

        // Preload next ad
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        debugPrint(
          'InterstitialAdManager: Ad failed to show: ${error.message}',
        );
        _isShowing = false;
        ad.dispose();
        _interstitialAd = null;
        _isLoaded = false;
        _notifyStatusListeners();
        onAdFailedToShow?.call();

        // Try to load another ad
        loadAd();
      },
      onAdImpression: (Ad ad) {
        debugPrint('InterstitialAdManager: Ad impression recorded');
      },
      onAdClicked: (Ad ad) {
        debugPrint('InterstitialAdManager: Ad clicked');
      },
      // iOS only - called before dismissing full screen content
      onAdWillDismissFullScreenContent: (Ad ad) {
        debugPrint('InterstitialAdManager: Ad will dismiss (iOS)');
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
      debugPrint('InterstitialAdManager: Ads disabled, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    if (!_isLoaded || _interstitialAd == null) {
      debugPrint('InterstitialAdManager: No ad loaded to show');
      onAdFailedToShow?.call();
      return false;
    }

    if (!ignoreCooldown && !canShowAd) {
      debugPrint('InterstitialAdManager: Cooldown period not elapsed');
      onAdFailedToShow?.call();
      return false;
    }

    if (_isShowing) {
      debugPrint('InterstitialAdManager: Ad already showing');
      return false;
    }

    // Update callbacks for this show with user-provided handlers
    _setupFullScreenContentCallback(
      onAdDismissed: onAdDismissed,
      onAdFailedToShow: onAdFailedToShow,
    );

    debugPrint('InterstitialAdManager: Showing ad...');
    await _interstitialAd!.show();
    return true;
  }

  /// Disposes of the current interstitial ad.
  Future<void> dispose() async {
    _statusListeners.clear();
    await _interstitialAd?.dispose();
    _interstitialAd = null;
    _isLoaded = false;
    _isLoading = false;
    _isShowing = false;
  }
}
