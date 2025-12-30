// Copyright 2024 - AdMob Integration Package
// Native Ad Manager for customizable native ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ads_enabled_manager.dart';

/// Callback for native ad events
typedef NativeAdCallback = void Function(NativeAd ad);

/// Callback for native ad errors
typedef NativeAdErrorCallback = void Function(LoadAdError error);

/// Manages native ads with support for multiple factory designs.
///
/// Native ads blend seamlessly with your app's content, providing
/// a non-disruptive advertising experience.
///
/// Features:
/// - Multiple factory/template support
/// - Automatic ad loading and caching
/// - Load retry with exponential backoff
/// - Full callback support
///
/// Example usage:
/// ```dart
/// final nativeManager = NativeAdManager();
///
/// // Load a native ad with a specific factory
/// await nativeManager.loadAd(
///   factoryId: 'small_template',
///   onAdLoaded: (ad) {
///     setState(() => _nativeAd = ad);
///   },
/// );
///
/// // Display with the widget
/// if (nativeManager.isLoaded) {
///   NativeAdWidget(manager: nativeManager);
/// }
/// ```
class NativeAdManager {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  int _loadAttempts = 0;
  String? _currentFactoryId;

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

  /// The currently loaded native ad
  NativeAd? get nativeAd => _nativeAd;

  /// Whether a native ad is currently loaded
  bool get isLoaded => _isLoaded;

  /// Whether a native ad is currently loading
  bool get isLoading => _isLoading;

  /// The factory ID used for the current ad
  String? get currentFactoryId => _currentFactoryId;

  /// Loads a native ad.
  ///
  /// [factoryId] identifies which native ad factory (layout) to use.
  /// Must match a factory registered on the native platform side.
  ///
  /// Built-in factory IDs:
  /// - 'small_template' - Compact layout for lists
  /// - 'medium_template' - Standard layout with image
  /// - 'full_template' - Large layout with all assets
  ///
  /// [adUnitId] can be provided to override the default ad unit ID.
  /// [onAdLoaded] is called when the ad is successfully loaded.
  /// [onAdFailedToLoad] is called if the ad fails to load.
  Future<void> loadAd({
    required String factoryId,
    String? adUnitId,
    NativeAdCallback? onAdLoaded,
    NativeAdErrorCallback? onAdFailedToLoad,
  }) async {
    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('NativeAdManager: Ads disabled, skipping load');
      return;
    }

    // Check consent before loading (Google best practice)
    if (!await ConsentInformation.instance.canRequestAds()) {
      debugPrint('NativeAdManager: Cannot request ads (no consent)');
      return;
    }

    if (_isLoading) {
      debugPrint('NativeAdManager: Already loading, skipping...');
      return;
    }

    // Dispose existing ad if loading a different factory
    if (_isLoaded && _currentFactoryId != factoryId) {
      await dispose();
    }

    if (_isLoaded && _currentFactoryId == factoryId) {
      debugPrint('NativeAdManager: Ad already loaded with same factory');
      return;
    }

    _isLoading = true;
    _currentFactoryId = factoryId;
    _notifyStatusListeners();
    debugPrint('NativeAdManager: Loading native ad with factory: $factoryId');

    _nativeAd = NativeAd(
      adUnitId: adUnitId ?? AdFlowConfig.current.nativeAdUnitId,
      factoryId: factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          debugPrint('NativeAdManager: Ad loaded successfully');
          _isLoaded = true;
          _isLoading = false;
          _loadAttempts = 0;
          _notifyStatusListeners();
          onAdLoaded?.call(ad as NativeAd);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          debugPrint('NativeAdManager: Ad failed to load: ${error.message}');
          _isLoaded = false;
          _isLoading = false;
          _loadAttempts++;
          ad.dispose();
          _nativeAd = null;
          _notifyStatusListeners();

          // Report error to centralized handler
          AdFlowErrorHandler.instance.reportLoadError(
            error,
            type: AdErrorType.nativeLoad,
            adUnitId: adUnitId ?? AdFlowConfig.current.nativeAdUnitId,
          );

          // Retry loading if under max attempts
          if (_loadAttempts < AdFlowConfig.current.maxLoadRetries) {
            debugPrint(
              'NativeAdManager: Retrying load (attempt $_loadAttempts)...',
            );
            Future.delayed(
              AdFlowConfig.current.retryDelay * _loadAttempts,
              () => loadAd(
                factoryId: factoryId,
                adUnitId: adUnitId,
                onAdLoaded: onAdLoaded,
                onAdFailedToLoad: onAdFailedToLoad,
              ),
            );
          } else {
            onAdFailedToLoad?.call(error);
          }
        },
        onAdOpened: (Ad ad) {
          debugPrint('NativeAdManager: Ad opened');
        },
        onAdClosed: (Ad ad) {
          debugPrint('NativeAdManager: Ad closed');
        },
        onAdClicked: (Ad ad) {
          debugPrint('NativeAdManager: Ad clicked');
        },
        onAdImpression: (Ad ad) {
          debugPrint('NativeAdManager: Ad impression recorded');
        },
      ),
    );

    await _nativeAd!.load();
  }

  /// Disposes of the current native ad.
  Future<void> dispose() async {
    _statusListeners.clear();
    await _nativeAd?.dispose();
    _nativeAd = null;
    _isLoaded = false;
    _isLoading = false;
    _currentFactoryId = null;
  }
}

// ============================================================================
// NATIVE AD FACTORY IDS
// ============================================================================

/// Pre-defined factory IDs for native ad layouts.
///
/// These must match the factory IDs registered on the native platform side.
/// See the setup instructions in native_ad_factories.dart for implementation.
abstract class NativeAdFactoryIds {
  /// Small, compact layout - ideal for lists and feeds
  /// Shows: icon, headline, body (truncated), call to action
  static const String small = 'small_template';

  /// Medium layout with image - good balance of visibility and space
  /// Shows: icon, headline, body, media/image, call to action
  static const String medium = 'medium_template';

  /// Full layout showing all native ad assets
  /// Shows: icon, headline, body, media, advertiser, star rating, store, price, call to action
  static const String full = 'full_template';

  /// List item style - designed to blend with list items
  /// Shows: icon, headline, call to action (inline)
  static const String listItem = 'list_item_template';

  /// Card style - elevated card design
  /// Shows: media, icon, headline, body, call to action
  static const String card = 'card_template';

  /// Banner style - horizontal layout similar to banner ads
  /// Shows: icon, headline, call to action (horizontal)
  static const String banner = 'banner_template';
}
