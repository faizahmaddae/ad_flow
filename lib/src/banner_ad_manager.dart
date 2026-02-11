// Copyright 2024 - AdMob Integration Package
// Banner Ad Manager for standard and collapsible banner ads

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_manager_mixin.dart';
import 'ad_sdk.dart';
import 'ads_enabled_manager.dart';

/// Callback for banner ad events
typedef BannerAdCallback = void Function(BannerAd ad);

/// Callback for banner ad errors
typedef BannerAdErrorCallback = void Function(BannerAd ad, LoadAdError error);

/// Manages banner ads including standard adaptive and collapsible banners.
///
/// Supports:
/// - Anchored adaptive banner ads (recommended for most use cases)
/// - Collapsible banner ads (larger overlay that collapses to banner size)
/// - Automatic size calculation based on device orientation
/// - Orientation change handling
///
/// Example usage:
/// ```dart
/// final bannerManager = BannerAdManager();
///
/// // Load an adaptive banner
/// await bannerManager.loadAdaptiveBanner(
///   context: context,
///   onAdLoaded: (ad) {
///     setState(() => _bannerAd = ad);
///   },
/// );
///
/// // Display with AdWidget
/// if (bannerManager.isLoaded) {
///   AdWidget(ad: bannerManager.bannerAd!);
/// }
/// ```
class BannerAdManager
    with AdStatusNotifier, AdRetryHandler
    implements AdManager {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  AdSize? _currentSize;
  String? _pendingAdUnitId;

  /// The currently loaded banner ad
  BannerAd? get bannerAd => _bannerAd;

  /// Whether a banner ad is currently loaded
  @override
  bool get isLoaded => _isLoaded;

  /// Whether a banner ad is currently loading
  @override
  bool get isLoading => _isLoading;

  /// Not applicable to banner ads (non-fullscreen)
  @override
  bool get isShowing => false;

  /// The size of the current banner ad
  AdSize? get currentSize => _currentSize;

  /// Loads a banner ad with a custom size.
  ///
  /// Use this method when you need a specific ad size like
  /// [AdSize.mediumRectangle] (300x250) for dialogs or other layouts.
  ///
  /// Example:
  /// ```dart
  /// await bannerManager.loadBanner(
  ///   size: AdSize.mediumRectangle, // 300x250 - great for dialogs
  ///   onAdLoaded: (ad) {
  ///     setState(() => _adLoaded = true);
  ///   },
  /// );
  /// ```
  ///
  /// For responsive banners that fit the screen width, use
  /// [loadAdaptiveBanner] instead.
  Future<void> loadBanner({
    required AdSize size,
    BannerAdCallback? onAdLoaded,
    BannerAdErrorCallback? onAdFailedToLoad,
    String? adUnitId,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('BannerAdManager: Ads disabled, skipping load');
      return;
    }

    if (_isLoading) {
      debugPrint('BannerAdManager: Already loading, skipping...');
      return;
    }

    _isLoading = true;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('BannerAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'BannerAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    _currentSize = size;

    await _loadBanner(
      adUnitId: adUnitId ?? AdFlowConfig.current.bannerAdUnitId,
      size: size,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onAdLoaded: onAdLoaded,
      onAdFailedToLoad: onAdFailedToLoad,
    );
  }

  /// Loads an anchored adaptive banner ad.
  ///
  /// The ad size is automatically calculated based on the device width
  /// and current orientation.
  ///
  /// [context] is required to get the device width.
  /// [onAdLoaded] is called when the ad is successfully loaded.
  /// [onAdFailedToLoad] is called if the ad fails to load.
  /// [adUnitId] can be provided to override the default ad unit ID.
  Future<void> loadAdaptiveBanner({
    required BuildContext context,
    BannerAdCallback? onAdLoaded,
    BannerAdErrorCallback? onAdFailedToLoad,
    String? adUnitId,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('BannerAdManager: Ads disabled, skipping load');
      return;
    }

    // Capture width before async gap to avoid use_build_context_synchronously
    final screenWidth = MediaQuery.sizeOf(context).width.truncate();

    if (_isLoading) {
      debugPrint('BannerAdManager: Already loading, skipping...');
      return;
    }

    _isLoading = true;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('BannerAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'BannerAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Get adaptive banner size
    final size = await AdSdk.instance.getAdaptiveBannerSize(screenWidth);

    if (size == null) {
      debugPrint('BannerAdManager: Unable to get adaptive banner size');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    _currentSize = size;

    await _loadBanner(
      adUnitId: adUnitId ?? AdFlowConfig.current.bannerAdUnitId,
      size: size,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onAdLoaded: onAdLoaded,
      onAdFailedToLoad: onAdFailedToLoad,
    );
  }

  /// Loads a collapsible banner ad.
  ///
  /// Collapsible banners initially show as a larger overlay, then
  /// collapse to the normal banner size when the user taps the
  /// collapse button.
  ///
  /// [placement] determines whether the banner anchors to the top
  /// or bottom of the screen.
  ///
  /// Example:
  /// ```dart
  /// await bannerManager.loadCollapsibleBanner(
  ///   context: context,
  ///   placement: CollapsibleBannerPlacement.bottom,
  ///   onAdLoaded: (ad) {
  ///     setState(() => _bannerAd = ad);
  ///   },
  /// );
  /// ```
  Future<void> loadCollapsibleBanner({
    required BuildContext context,
    required CollapsibleBannerPlacement placement,
    BannerAdCallback? onAdLoaded,
    BannerAdErrorCallback? onAdFailedToLoad,
    String? adUnitId,
  }) async {
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('BannerAdManager: Ads disabled, skipping load');
      return;
    }

    // Capture width before async gap to avoid use_build_context_synchronously
    final screenWidth = MediaQuery.sizeOf(context).width.truncate();

    if (_isLoading) {
      debugPrint('BannerAdManager: Already loading, skipping...');
      return;
    }

    _isLoading = true;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('BannerAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'BannerAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Get adaptive banner size
    final size = await AdSdk.instance.getAdaptiveBannerSize(screenWidth);

    if (size == null) {
      debugPrint('BannerAdManager: Unable to get adaptive banner size');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    _currentSize = size;

    // Create request with collapsible extras
    final request = AdRequest(extras: {'collapsible': placement.value});

    await _loadBanner(
      adUnitId: adUnitId ?? AdFlowConfig.current.bannerAdUnitId,
      size: size,
      request: request,
      onAdLoaded: onAdLoaded,
      onAdFailedToLoad: onAdFailedToLoad,
    );
  }

  /// Internal method to load a banner ad.
  Future<void> _loadBanner({
    required String adUnitId,
    required AdSize size,
    required AdRequest request,
    BannerAdCallback? onAdLoaded,
    BannerAdErrorCallback? onAdFailedToLoad,
  }) async {
    // Dispose existing ad without clearing listeners
    await _disposeCurrentAd();
    _pendingAdUnitId = adUnitId;

    debugPrint('BannerAdManager: Loading banner ad...');

    await AdSdk.instance.loadBannerAd(
      adUnitId: adUnitId,
      size: size,
      request: request,
      onAdLoaded: (BannerAd ad) {
        debugPrint('BannerAdManager: Ad loaded successfully');
        _bannerAd = ad;
        _isLoaded = true;
        _isLoading = false;
        resetRetryAttempts();
        notifyStatusListeners();
        onAdLoaded?.call(ad);
      },
      onAdFailedToLoad: (BannerAd ad, LoadAdError error) {
        debugPrint('BannerAdManager: Ad failed to load: ${error.message}');
        _isLoaded = false;
        _isLoading = false;
        _bannerAd = null;
        notifyStatusListeners();

        // Report error to centralized handler
        AdFlowErrorHandler.instance.reportLoadError(
          error,
          type: AdErrorType.bannerLoad,
          adUnitId: adUnitId,
        );

        // Retry loading with linear backoff.
        // Don't pass onAdLoaded/onAdFailedToLoad to retry — callers may
        // have disposed their widgets by the time the retry fires, leading
        // to stale callbacks. Status listeners remain the safe channel.
        final retried = handleLoadFailure(
          checkDisposed: () => isDisposed,
          onRetry: () => _loadBanner(
            adUnitId: _pendingAdUnitId ?? adUnitId,
            size: size,
            request: request,
          ),
          managerName: 'BannerAdManager',
        );

        // Only report to callback when all retries exhausted
        if (!retried) {
          onAdFailedToLoad?.call(ad, error);
        }

        // Dispose the failed ad AFTER callbacks to avoid passing a disposed object
        ad.dispose();
      },
    );
  }

  /// Handles orientation changes by reloading the banner.
  ///
  /// Call this method when the device orientation changes to ensure
  /// the banner ad has the correct size.
  ///
  /// Example:
  /// ```dart
  /// OrientationBuilder(
  ///   builder: (context, orientation) {
  ///     if (_lastOrientation != null && _lastOrientation != orientation) {
  ///       bannerManager.handleOrientationChange(
  ///         context: context,
  ///         onAdLoaded: (ad) => setState(() {}),
  ///       );
  ///     }
  ///     _lastOrientation = orientation;
  ///     return YourWidget();
  ///   },
  /// );
  /// ```
  Future<void> handleOrientationChange({
    required BuildContext context,
    BannerAdCallback? onAdLoaded,
    BannerAdErrorCallback? onAdFailedToLoad,
    bool isCollapsible = false,
    CollapsibleBannerPlacement placement = CollapsibleBannerPlacement.bottom,
  }) async {
    if (isCollapsible) {
      await loadCollapsibleBanner(
        context: context,
        placement: placement,
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      );
    } else {
      await loadAdaptiveBanner(
        context: context,
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      );
    }
  }

  /// Creates a widget to display the banner ad.
  ///
  /// Returns null if no ad is loaded.
  Widget? buildAdWidget() {
    if (!_isLoaded || _bannerAd == null) {
      return null;
    }

    return SizedBox(
      width: _currentSize!.width.toDouble(),
      height: _currentSize!.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  /// Creates a widget container for the banner ad with SafeArea.
  ///
  /// This is the recommended way to display banner ads, especially
  /// for bottom-anchored banners.
  Widget buildBannerContainer({Alignment alignment = Alignment.bottomCenter}) {
    final adWidget = buildAdWidget();
    if (adWidget == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: alignment,
      child: SafeArea(child: adWidget),
    );
  }

  /// Disposes of the current banner ad without clearing listeners.
  /// Use this when reloading ads to preserve status listeners.
  Future<void> _disposeCurrentAd() async {
    await _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
  }

  /// Disposes of the manager completely.
  /// Call this when the manager is no longer needed.
  @override
  Future<void> dispose() async {
    disposeNotifier();
    resetRetryState();
    await _disposeCurrentAd();
    _isLoading = false;
    _pendingAdUnitId = null;
  }
}
