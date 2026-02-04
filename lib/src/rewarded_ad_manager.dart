// Copyright 2024 - AdMob Integration Package
// Rewarded Ad Manager for rewarded video ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ads_enabled_manager.dart';

/// Callback for rewarded ad events
typedef RewardedAdCallback = void Function(RewardedAd ad);

/// Callback for rewarded ad errors
typedef RewardedAdErrorCallback = void Function(LoadAdError error);

/// Simplified callback for when user earns a reward (just the reward)
typedef OnRewardEarnedCallback = void Function(RewardItem reward);

/// Full callback for when user earns a reward (includes ad reference)
typedef OnUserEarnedRewardCallback =
    void Function(AdWithoutView ad, RewardItem reward);

/// Manages rewarded ads with automatic loading and reward handling.
///
/// Rewarded ads are full-screen ads that users can choose to watch
/// in exchange for in-app rewards (coins, lives, features, etc.).
///
/// Features:
/// - Automatic ad preloading
/// - Reward callback handling
/// - Load retry with exponential backoff
/// - FullScreenContentCallback handling
///
/// Example usage:
/// ```dart
/// final rewardedManager = RewardedAdManager();
///
/// // Preload a rewarded ad
/// await rewardedManager.loadAd();
///
/// // Show when ready and handle reward
/// if (rewardedManager.isLoaded) {
///   await rewardedManager.showAd(
///     onUserEarnedReward: (ad, reward) {
///       print('User earned ${reward.amount} ${reward.type}');
///       // Grant the reward to user
///     },
///     onAdDismissed: () {
///       // Resume app
///     },
///   );
/// }
/// ```
class RewardedAdManager {
  RewardedAd? _rewardedAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isShowing = false;
  bool _isDisposed = false;
  int _loadAttempts = 0;
  DateTime? _lastMaxRetryFailureTime;

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
    if (_isDisposed) return;
    for (final listener in List.of(_statusListeners)) {
      listener();
    }
  }

  /// The currently loaded rewarded ad
  RewardedAd? get rewardedAd => _rewardedAd;

  /// Whether a rewarded ad is currently loaded
  bool get isLoaded => _isLoaded;

  /// Whether a rewarded ad is currently loading
  bool get isLoading => _isLoading;

  /// Whether a rewarded ad is currently being shown
  bool get isShowing => _isShowing;

  /// Loads a rewarded ad.
  ///
  /// [adUnitId] can be provided to override the default ad unit ID.
  /// [onAdLoaded] is called when the ad is successfully loaded.
  /// [onAdFailedToLoad] is called if the ad fails to load.
  Future<void> loadAd({
    String? adUnitId,
    RewardedAdCallback? onAdLoaded,
    RewardedAdErrorCallback? onAdFailedToLoad,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    _isDisposed = false;

    // Check if ads are disabled (Remove Ads feature)
    // By default, rewarded ads ignore Remove Ads setting since users may still want rewards
    if (!AdFlowConfig.current.rewardedAdsIgnoreRemoveAds &&
        AdsEnabledManager.instance.isDisabled) {
      debugPrint('RewardedAdManager: Ads disabled, skipping load');
      return;
    }

    // Check consent before loading (Google best practice)
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('RewardedAdManager: Cannot request ads (no consent)');
      return;
    }

    // Check if already loading or loaded (before cooldown check to avoid unnecessary work)
    if (_isLoading || _isLoaded) {
      debugPrint('RewardedAdManager: Already loading or loaded, skipping...');
      return;
    }

    // Check retry cooldown after max attempts
    if (_loadAttempts >= AdFlowConfig.current.maxLoadRetries &&
        _lastMaxRetryFailureTime != null) {
      final elapsed = DateTime.now().difference(_lastMaxRetryFailureTime!);
      if (elapsed < AdFlowConfig.current.retryCooldownAfterMaxAttempts) {
        final remaining =
            AdFlowConfig.current.retryCooldownAfterMaxAttempts - elapsed;
        debugPrint(
          'RewardedAdManager: In cooldown after max retries (${remaining.inSeconds}s remaining)',
        );
        return;
      } else {
        // Cooldown expired, reset attempts
        _loadAttempts = 0;
        _lastMaxRetryFailureTime = null;
      }
    }

    _isLoading = true;
    _notifyStatusListeners();
    debugPrint('RewardedAdManager: Loading rewarded ad...');

    await RewardedAd.load(
      adUnitId: adUnitId ?? AdFlowConfig.current.rewardedAdUnitId,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          debugPrint('RewardedAdManager: Ad loaded successfully');
          _rewardedAd = ad;
          _isLoaded = true;
          _isLoading = false;
          _loadAttempts = 0;

          // Set up full screen content callbacks
          _setupFullScreenContentCallback();

          onAdLoaded?.call(ad);
          _notifyStatusListeners();
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('RewardedAdManager: Ad failed to load: ${error.message}');
          _isLoaded = false;
          _isLoading = false;
          _loadAttempts++;
          _notifyStatusListeners();

          // Report error to centralized handler
          AdFlowErrorHandler.instance.reportLoadError(
            error,
            type: AdErrorType.rewardedLoad,
            adUnitId: adUnitId ?? AdFlowConfig.current.rewardedAdUnitId,
          );

          // Retry loading if under max attempts
          if (_loadAttempts < AdFlowConfig.current.maxLoadRetries) {
            debugPrint(
              'RewardedAdManager: Retrying load (attempt $_loadAttempts)...',
            );
            Future.delayed(AdFlowConfig.current.retryDelay * _loadAttempts, () {
              // Guard against retry after dispose
              if (_isDisposed) return;
              loadAd(adUnitId: adUnitId);
            });
          } else {
            // Max retries exhausted, start cooldown
            _lastMaxRetryFailureTime = DateTime.now();
            debugPrint(
              'RewardedAdManager: Max retries exhausted, entering ${AdFlowConfig.current.retryCooldownAfterMaxAttempts.inMinutes}min cooldown',
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
    _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad ad) {
        debugPrint('RewardedAdManager: Ad showed full screen content');
        _isShowing = true;
        _notifyStatusListeners();
      },
      onAdDismissedFullScreenContent: (Ad ad) {
        debugPrint('RewardedAdManager: Ad dismissed');
        _isShowing = false;
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        _notifyStatusListeners();
        onAdDismissed?.call();

        // Preload next ad
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        debugPrint('RewardedAdManager: Ad failed to show: ${error.message}');
        _isShowing = false;
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        _notifyStatusListeners();
        onAdFailedToShow?.call();

        // Try to load another ad
        loadAd();
      },
      onAdImpression: (Ad ad) {
        debugPrint('RewardedAdManager: Ad impression recorded');
      },
      onAdClicked: (Ad ad) {
        debugPrint('RewardedAdManager: Ad clicked');
      },
      // iOS only - called before dismissing full screen content
      onAdWillDismissFullScreenContent: (Ad ad) {
        debugPrint('RewardedAdManager: Ad will dismiss (iOS)');
      },
    );
  }

  /// Shows the loaded rewarded ad.
  ///
  /// Returns `true` if the ad was shown, `false` otherwise.
  ///
  /// [onUserEarnedReward] is called when the user earns a reward.
  /// This is the most important callback - use it to grant the reward!
  /// The callback receives just the [RewardItem] for simplicity.
  /// [onAdDismissed] is called when the ad is dismissed.
  /// [onAdFailedToShow] is called if the ad fails to show.
  Future<bool> showAd({
    required OnRewardEarnedCallback onUserEarnedReward,
    VoidCallback? onAdDismissed,
    VoidCallback? onAdFailedToShow,
  }) async {
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('RewardedAdManager: Ads disabled, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    if (!_isLoaded || _rewardedAd == null) {
      debugPrint('RewardedAdManager: No ad loaded to show');
      onAdFailedToShow?.call();
      return false;
    }

    if (_isShowing) {
      debugPrint('RewardedAdManager: Ad already showing');
      return false;
    }

    // Update callbacks for this show with user-provided handlers
    _setupFullScreenContentCallback(
      onAdDismissed: onAdDismissed,
      onAdFailedToShow: onAdFailedToShow,
    );

    // Set immersive mode for a better fullscreen experience (Google best practice)
    _rewardedAd!.setImmersiveMode(true);

    debugPrint('RewardedAdManager: Showing ad...');
    // Wrap the simplified callback to match the SDK's expected signature
    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onUserEarnedReward(reward);
      },
    );
    return true;
  }

  /// Disposes of the current rewarded ad.
  Future<void> dispose() async {
    _isDisposed = true;
    _statusListeners.clear();
    await _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoaded = false;
    _isLoading = false;
    _isShowing = false;
  }
}
