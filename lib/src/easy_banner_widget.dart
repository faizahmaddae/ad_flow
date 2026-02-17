// Easy-to-use Banner Ad Widget
// Just drop this widget anywhere in your app!

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' show AdSize;
import 'banner_ad_manager.dart';
import 'ad_config.dart' show CollapsibleBannerPlacement;
import 'ads_enabled_manager.dart';
import 'ad_service.dart';
import 'ad_flow_logger.dart';

/// A simple, self-contained banner ad widget.
///
/// This widget automatically respects the "Remove Ads" setting.
/// If ads are disabled via [AdsEnabledManager], this widget shows nothing.
///
/// Usage:
/// ```dart
/// // Adaptive banner (default) - fits screen width
/// EasyBannerAd()
///
/// // Fixed size banner
/// EasyBannerAd(adSize: AdSize.mediumRectangle)  // 300x250
/// EasyBannerAd(adSize: AdSize.largeBanner)      // 320x100
///
/// // Collapsible banner (expands then shrinks)
/// EasyBannerAd(collapsible: true)
/// ```
class EasyBannerAd extends StatefulWidget {
  /// Fixed ad size. If null, uses adaptive banner that fits screen width.
  ///
  /// Common sizes: `AdSize.banner`, `AdSize.mediumRectangle`,
  /// `AdSize.largeBanner`, `AdSize.leaderboard`.
  final AdSize? adSize;

  /// Whether to use collapsible banner (larger, then shrinks).
  /// Ignored if [adSize] is provided.
  final bool collapsible;

  // Optional if user want to use it or not. Default (true)
  final bool useSafeArea;

  const EasyBannerAd({
    super.key,
    this.adSize,
    this.collapsible = false,
    this.useSafeArea = true,
  });

  @override
  State<EasyBannerAd> createState() => _EasyBannerAdState();
}

class _EasyBannerAdState extends State<EasyBannerAd> {
  final BannerAdManager _bannerManager = BannerAdManager();
  bool _isLoaded = false;
  bool _adsEnabled = true;
  bool _isInitialized = false;
  bool _isDisposed = false;
  Orientation? _currentOrientation;
  StreamSubscription<bool>? _initSubscription;
  Timer? _orientationDebounceTimer;

  /// Debounce duration for orientation changes to prevent ad request spam
  static const Duration _orientationDebounceDuration = Duration(
    milliseconds: 300,
  );

  @override
  void initState() {
    super.initState();
    _adsEnabled = AdsEnabledManager.instance.isEnabled;

    // Load after first frame to ensure context is ready
    if (_adsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        _isInitialized = true;
        _tryLoadAd();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        _isInitialized = true;
      });
    }

    // Listen for ads enabled changes
    AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);

    // Listen for AdFlow initialization completion (for non-blocking init)
    // This allows the widget to load ads when AdFlow becomes ready
    _initSubscription = AdFlow.instance.initStream.listen(_onAdFlowInitialized);

    // Listen for manager status changes (e.g. retry-loaded ads)
    _bannerManager.addStatusListener(_onStatusChanged);
  }

  void _onAdFlowInitialized(bool canRequestAds) {
    if (_isDisposed || !mounted || !_isInitialized) return;
    if (canRequestAds && _adsEnabled && !_isLoaded) {
      adFlowLog('EasyBannerAd: AdFlow initialized, loading ad');
      _loadAd();
    }
  }

  /// Reacts to manager status changes (e.g. a retried load succeeded).
  void _onStatusChanged() {
    if (_isDisposed || !mounted) return;
    final loaded = _bannerManager.isLoaded;
    if (loaded != _isLoaded) {
      setState(() => _isLoaded = loaded);
    }
  }

  @override
  void didUpdateWidget(EasyBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adSize != widget.adSize ||
        oldWidget.collapsible != widget.collapsible) {
      if (_adsEnabled && _isInitialized && !_isDisposed) {
        _bannerManager.disposeCurrentAd();
        setState(() => _isLoaded = false);
        _tryLoadAd();
      }
    }
  }

  /// Tries to load ad if AdFlow is initialized, otherwise waits for init stream.
  Future<void> _tryLoadAd() async {
    if (!_adsEnabled || !_isInitialized || !mounted) return;

    // If AdFlow is already initialized, load immediately
    if (AdFlow.instance.isInitialized) {
      await _loadAd();
    } else {
      // AdFlow not ready yet - will be triggered by _onAdFlowInitialized
      adFlowLog('EasyBannerAd: Waiting for AdFlow initialization...');
    }
  }

  void _onAdsEnabledChanged(bool isEnabled) {
    // Check disposed flag first to prevent callbacks after dispose
    if (_isDisposed || !mounted || !_isInitialized) return;

    setState(() => _adsEnabled = isEnabled);
    if (isEnabled && !_isLoaded) {
      _tryLoadAd();
    } else if (!isEnabled) {
      // Use disposeCurrentAd + cancelRetryTimer instead of full dispose()
      // to preserve status listeners — full dispose() clears them, so a
      // subsequent re-enable + retry success would never reach the widget.
      _bannerManager.disposeCurrentAd();
      _bannerManager.cancelRetryTimer();
      _isLoaded = false;
    }
  }

  Future<void> _loadAd() async {
    if (!_adsEnabled || !_isInitialized || !mounted || _isDisposed) return;

    // Priority: adSize > collapsible > adaptive
    if (widget.adSize != null) {
      // Fixed size banner
      await _bannerManager.loadBanner(
        size: widget.adSize!,
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Note: BannerAdManager already reports errors to AdFlowErrorHandler
          if (mounted) setState(() => _isLoaded = false);
        },
      );
    } else if (widget.collapsible) {
      await _bannerManager.loadCollapsibleBanner(
        context: context,
        placement: CollapsibleBannerPlacement.bottom,
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Note: BannerAdManager already reports errors to AdFlowErrorHandler
          if (mounted) setState(() => _isLoaded = false);
        },
      );
    } else {
      await _bannerManager.loadAdaptiveBanner(
        context: context,
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Note: BannerAdManager already reports errors to AdFlowErrorHandler
          if (mounted) setState(() => _isLoaded = false);
        },
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _orientationDebounceTimer?.cancel();
    _initSubscription?.cancel();
    _bannerManager.removeStatusListener(_onStatusChanged);
    AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
    _bannerManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if ads are disabled
    if (!_adsEnabled) return const SizedBox.shrink();

    // Fixed size banners don't need orientation handling
    if (widget.adSize != null) {
      if (!_isLoaded) return const SizedBox.shrink();
      return SafeArea(
        child: _bannerManager.buildAdWidget() ?? const SizedBox.shrink(),
      );
    }

    // Handle orientation changes for adaptive/collapsible banners
    // This follows Google's recommended pattern for adaptive banners
    return OrientationBuilder(
      builder: (context, orientation) {
        if (_currentOrientation != null && _currentOrientation != orientation) {
          // Orientation changed - debounce to prevent ad request spam during rotation
          // Using addPostFrameCallback to avoid modifying state during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isDisposed) return;
            // Cancel any pending reload and start new debounce
            _orientationDebounceTimer?.cancel();
            _orientationDebounceTimer = Timer(_orientationDebounceDuration, () {
              if (!mounted || _isDisposed) return;
              // Only dispose the current ad, not the entire manager
              // (full dispose clears status listeners and marks disposed)
              _bannerManager.disposeCurrentAd();
              setState(() => _isLoaded = false);
              _tryLoadAd();
            });
          });
        }
        _currentOrientation = orientation;

        if (!_isLoaded) return const SizedBox.shrink();
        if (!widget.useSafeArea) {
          return _bannerManager.buildAdWidget() ?? const SizedBox.shrink();
        }
        return SafeArea(
          child: _bannerManager.buildAdWidget() ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
