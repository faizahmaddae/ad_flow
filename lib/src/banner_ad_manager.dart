// Copyright 2024 - AdMob Integration Package
// Banner Ad Manager for standard and collapsible banner ads

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
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
class BannerAdManager {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  AdSize? _currentSize;

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

  /// The currently loaded banner ad
  BannerAd? get bannerAd => _bannerAd;

  /// Whether a banner ad is currently loaded
  bool get isLoaded => _isLoaded;

  /// Whether a banner ad is currently loading
  bool get isLoading => _isLoading;

  /// The size of the current banner ad
  AdSize? get currentSize => _currentSize;

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
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('BannerAdManager: Ads disabled, skipping load');
      return;
    }

    // Capture width before async gap to avoid use_build_context_synchronously
    final screenWidth = MediaQuery.sizeOf(context).width.truncate();

    // Check consent before loading (Google best practice)
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('BannerAdManager: Cannot request ads (no consent)');
      return;
    }

    if (_isLoading) {
      debugPrint('BannerAdManager: Already loading, skipping...');
      return;
    }

    _isLoading = true;

    // Get adaptive banner size
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      screenWidth,
    );

    if (size == null) {
      debugPrint('BannerAdManager: Unable to get adaptive banner size');
      _isLoading = false;
      return;
    }

    _currentSize = size;

    await _loadBanner(
      adUnitId: adUnitId ?? AdFlowConfig.current.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
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
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('BannerAdManager: Ads disabled, skipping load');
      return;
    }

    // Capture width before async gap to avoid use_build_context_synchronously
    final screenWidth = MediaQuery.sizeOf(context).width.truncate();

    // Check consent before loading (Google best practice)
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('BannerAdManager: Cannot request ads (no consent)');
      return;
    }

    if (_isLoading) {
      debugPrint('BannerAdManager: Already loading, skipping...');
      return;
    }

    _isLoading = true;

    // Get adaptive banner size
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      screenWidth,
    );

    if (size == null) {
      debugPrint('BannerAdManager: Unable to get adaptive banner size');
      _isLoading = false;
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
    // Dispose existing ad
    await dispose();

    debugPrint('BannerAdManager: Loading banner ad...');

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: request,
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          debugPrint('BannerAdManager: Ad loaded successfully');
          _isLoaded = true;
          _isLoading = false;
          _notifyStatusListeners();
          onAdLoaded?.call(ad as BannerAd);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          debugPrint('BannerAdManager: Ad failed to load: ${error.message}');
          _isLoaded = false;
          _isLoading = false;
          ad.dispose();
          _bannerAd = null;
          _notifyStatusListeners();

          // Report error to centralized handler
          AdFlowErrorHandler.instance.reportLoadError(
            error,
            type: AdErrorType.bannerLoad,
            adUnitId: adUnitId,
          );

          onAdFailedToLoad?.call(ad as BannerAd, error);
        },
        onAdOpened: (Ad ad) {
          debugPrint('BannerAdManager: Ad opened');
        },
        onAdClosed: (Ad ad) {
          debugPrint('BannerAdManager: Ad closed');
        },
        onAdClicked: (Ad ad) {
          debugPrint('BannerAdManager: Ad clicked');
        },
        onAdImpression: (Ad ad) {
          debugPrint('BannerAdManager: Ad impression recorded');
        },
      ),
    );

    await _bannerAd!.load();
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

  /// Disposes of the current banner ad.
  Future<void> dispose() async {
    _statusListeners.clear();
    await _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _isLoading = false;
  }
}
