// Copyright 2024 - AdMob Integration Package
// Native Ad Manager for customizable native ads

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_manager_mixin.dart';
import 'ad_sdk.dart';
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
/// - Load retry with linear backoff
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
class NativeAdManager
    with AdStatusNotifier, AdRetryHandler
    implements AdManager {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _currentFactoryId;

  /// The currently loaded native ad
  NativeAd? get nativeAd => _nativeAd;

  /// Whether a native ad is currently loaded
  @override
  bool get isLoaded => _isLoaded;

  /// Whether a native ad is currently loading
  @override
  bool get isLoading => _isLoading;

  /// Not applicable to native ads (non-fullscreen)
  @override
  bool get isShowing => false;

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
    // Reset disposed flag to allow reuse (manager is accessed via lazy getter)
    resetDisposedState();

    // Check if ads are disabled (Remove Ads feature)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('NativeAdManager: Ads disabled, skipping load');
      return;
    }

    if (_isLoading) {
      debugPrint('NativeAdManager: Already loading, skipping...');
      return;
    }

    // Dispose existing ad if loading a different factory
    if (_isLoaded && _currentFactoryId != factoryId) {
      await _disposeCurrentAd();
    }

    if (_isLoaded && _currentFactoryId == factoryId) {
      debugPrint('NativeAdManager: Ad already loaded with same factory');
      return;
    }

    _isLoading = true;
    _currentFactoryId = factoryId;
    notifyStatusListeners();

    // Check consent before loading (Google best practice)
    if (!await AdSdk.instance.canRequestAds()) {
      debugPrint('NativeAdManager: Cannot request ads (no consent)');
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    // Check retry cooldown after max attempts
    if (isInRetryCooldown(managerName: 'NativeAdManager')) {
      _isLoading = false;
      notifyStatusListeners();
      return;
    }

    debugPrint('NativeAdManager: Loading native ad with factory: $factoryId');

    await AdSdk.instance.loadNativeAd(
      adUnitId: adUnitId ?? AdFlowConfig.current.nativeAdUnitId,
      factoryId: factoryId,
      request: AdRequest(
        httpTimeoutMillis: AdFlowConfig.current.httpTimeoutMillis,
      ),
      onAdLoaded: (NativeAd ad) {
        debugPrint('NativeAdManager: Ad loaded successfully');
        _nativeAd = ad;
        _isLoaded = true;
        _isLoading = false;
        resetRetryAttempts();
        notifyStatusListeners();
        onAdLoaded?.call(ad);
      },
      onAdFailedToLoad: (NativeAd ad, LoadAdError error) {
        debugPrint('NativeAdManager: Ad failed to load: ${error.message}');
        // Hint for common factory registration issue
        if (error.code == 0 ||
            error.message.toLowerCase().contains('factory')) {
          debugPrint(
            'NativeAdManager: HINT - Ensure native ad factory "$factoryId" is registered in native code (Android/iOS)',
          );
        }
        _isLoaded = false;
        _isLoading = false;
        ad.dispose();
        _nativeAd = null;
        notifyStatusListeners();

        // Report error to centralized handler
        AdFlowErrorHandler.instance.reportLoadError(
          error,
          type: AdErrorType.nativeLoad,
          adUnitId: adUnitId ?? AdFlowConfig.current.nativeAdUnitId,
        );

        // Retry loading with linear backoff
        // Note: Retries don't pass user callbacks to avoid invoking
        // stale widget callbacks after widget dispose. The user callback
        // is only called on final failure (below).
        final retried = handleLoadFailure(
          checkDisposed: () => isDisposed,
          onRetry: () => loadAd(factoryId: factoryId, adUnitId: adUnitId),
          managerName: 'NativeAdManager',
        );

        // Only report to callback when all retries exhausted
        if (!retried) {
          onAdFailedToLoad?.call(error);
        }
      },
    );
  }

  /// Disposes only the current ad object, preserving listeners and retry state.
  ///
  /// Used when switching factory IDs — the manager stays alive but the
  /// previous ad is cleaned up.
  Future<void> _disposeCurrentAd() async {
    await _nativeAd?.dispose();
    _nativeAd = null;
    _isLoaded = false;
    _currentFactoryId = null;
  }

  /// Disposes of the manager and all resources.
  @override
  Future<void> dispose() async {
    disposeNotifier();
    cancelRetryTimer();
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
