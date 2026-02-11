// Copyright 2024 - AdMob Integration Package
// Rewarded Ad Manager for rewarded video ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_manager_mixin.dart';
import 'ad_sdk.dart';
import 'ads_enabled_manager.dart';

/// Callback for rewarded ad events
typedef RewardedAdCallback = void Function(RewardedAd ad);

/// Callback for rewarded ad errors
typedef RewardedAdErrorCallback = void Function(LoadAdError error);

/// Simplified callback for when user earns a reward (just the reward)
typedef OnRewardEarnedCallback = void Function(RewardItem reward);

/// Manages rewarded ads with automatic loading and reward handling.
///
/// Rewarded ads are full-screen ads that users can choose to watch
/// in exchange for in-app rewards (coins, lives, features, etc.).
///
/// Features:
/// - Automatic ad preloading
/// - Reward callback handling
/// - Load retry with linear backoff
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
///     onUserEarnedReward: (reward) {
///       print('User earned ${reward.amount} ${reward.type}');
///       // Grant the reward to user
///     },
///     onAdDismissed: () {
///       // Resume app
///     },
///   );
/// }
/// ```
class RewardedAdManager
    with AdStatusNotifier, AdRetryHandler
    implements AdManager {
  RewardedAd? _rewardedAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isShowing = false;

  // Stored show callbacks — set in showAd(), consumed by fullscreen callbacks.
  VoidCallback? _pendingOnAdDismissed;
  VoidCallback? _pendingOnAdFailedToShow;

  /// The currently loaded rewarded ad
  RewardedAd? get rewardedAd => _rewardedAd;

  /// Whether a rewarded ad is currently loaded
  @override
  bool get isLoaded => _isLoaded;

  /// Whether a rewarded ad is currently loading
  @override
  bool get isLoading => _isLoading;

  /// Whether a rewarded ad is currently being shown
  @override
  bool get isShowing => _isShowing;

  /// Server-side verification options for reward validation.
  ///
  /// Set this before calling [showAd] to enable server-side reward verification.
  /// Your server will receive a callback from Google with these parameters
  /// to validate that the reward was legitimately earned.
  ///
  /// Example:
  /// ```dart
  /// rewardedManager.serverSideVerificationOptions =
  ///     ServerSideVerificationOptions(
  ///       userId: currentUser.id,
  ///       customData: jsonEncode({'level': 5, 'item': 'coins'}),
  ///     );
  /// ```
  ServerSideVerificationOptions? serverSideVerificationOptions;

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
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    // By default, rewarded ads ignore Remove Ads setting since users may still want rewards
    if (!AdFlowConfig.current.rewardedAdsIgnoreRemoveAds &&
        AdsEnabledManager.instance.isDisabled) {
      debugPrint('RewardedAdManager: Ads disabled, skipping load');
      return;
    }

    // Check if already loading or loaded (before async work to prevent races)
    if (_isLoading || _isLoaded) {
      debugPrint('RewardedAdManager: Already loading or loaded, skipping...');
      return;
    }

    _isLoading = true;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('RewardedAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'RewardedAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    debugPrint('RewardedAdManager: Loading rewarded ad...');

    await AdSdk.instance.loadRewardedAd(
      adUnitId: adUnitId ?? AdFlowConfig.current.rewardedAdUnitId,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onLoaded: (RewardedAd ad) {
        debugPrint('RewardedAdManager: Ad loaded successfully');
        _rewardedAd = ad;
        _isLoaded = true;
        _isLoading = false;
        resetRetryAttempts();

        // Set up full screen content callbacks
        _setupFullScreenContentCallback();

        // Apply server-side verification if configured
        if (serverSideVerificationOptions != null) {
          ad.setServerSideOptions(serverSideVerificationOptions!);
        }

        onAdLoaded?.call(ad);
        notifyStatusListeners();
      },
      onFailed: (LoadAdError error) {
        debugPrint('RewardedAdManager: Ad failed to load: ${error.message}');
        _isLoaded = false;
        _isLoading = false;
        notifyStatusListeners();

        // Report error to centralized handler
        AdFlowErrorHandler.instance.reportLoadError(
          error,
          type: AdErrorType.rewardedLoad,
          adUnitId: adUnitId ?? AdFlowConfig.current.rewardedAdUnitId,
        );

        // Retry loading with linear backoff
        final retried = handleLoadFailure(
          checkDisposed: () => isDisposed,
          onRetry: () => loadAd(adUnitId: adUnitId),
          managerName: 'RewardedAdManager',
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
  /// cannot overwrite the user's callbacks.
  void _setupFullScreenContentCallback() {
    _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad ad) {
        debugPrint('RewardedAdManager: Ad showed full screen content');
        _isShowing = true;
        notifyStatusListeners();
      },
      onAdDismissedFullScreenContent: (Ad ad) {
        debugPrint('RewardedAdManager: Ad dismissed');
        _isShowing = false;
        final onDismissed = _pendingOnAdDismissed;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        notifyStatusListeners();
        onDismissed?.call();

        // Preload next ad
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        debugPrint('RewardedAdManager: Ad failed to show: ${error.message}');
        _isShowing = false;
        final onFailed = _pendingOnAdFailedToShow;
        _pendingOnAdDismissed = null;
        _pendingOnAdFailedToShow = null;
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        notifyStatusListeners();

        // Report show error to centralized handler
        AdFlowErrorHandler.instance.reportError(
          AdFlowError(
            type: AdErrorType.rewardedShow,
            code: error.code,
            message: error.message,
          ),
        );

        onFailed?.call();

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
    // Respect rewardedAdsIgnoreRemoveAds config—same guard as loadAd()
    if (!AdFlowConfig.current.rewardedAdsIgnoreRemoveAds &&
        AdsEnabledManager.instance.isDisabled) {
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

    // Check consent hasn't been revoked since the ad was loaded
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('RewardedAdManager: Consent revoked, not showing');
      onAdFailedToShow?.call();
      return false;
    }

    // Store callbacks as instance fields — fullscreen callbacks read from these
    _pendingOnAdDismissed = onAdDismissed;
    _pendingOnAdFailedToShow = onAdFailedToShow;
    _setupFullScreenContentCallback();

    // Set immersive mode for a better fullscreen experience (Android only)
    if (AdFlowPlatform.isAndroid) {
      _rewardedAd!.setImmersiveMode(true);
    }

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
  @override
  Future<void> dispose() async {
    disposeNotifier();
    cancelRetryTimer();
    await _rewardedAd?.dispose();
    _rewardedAd = null;
    _isLoaded = false;
    _isLoading = false;
    _isShowing = false;
    serverSideVerificationOptions = null;
    _pendingOnAdDismissed = null;
    _pendingOnAdFailedToShow = null;
  }
}
