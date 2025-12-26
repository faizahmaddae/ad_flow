// Copyright 2024 - AdMob Integration Package
// Native Ad Widget - Easy-to-use Flutter widget for native ads

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'native_ad_manager.dart';
import 'ads_enabled_manager.dart';

/// A widget that displays a native ad.
///
/// Usage with NativeAdManager:
/// ```dart
/// NativeAdWidget(
///   manager: _nativeAdManager,
///   height: 300,
///   placeholder: CircularProgressIndicator(),
/// )
/// ```
class NativeAdWidget extends StatelessWidget {
  /// The NativeAdManager that holds the loaded ad
  final NativeAdManager manager;

  /// Height of the ad container (required for proper layout)
  final double? height;

  /// Width of the ad container (defaults to full width)
  final double? width;

  /// Widget to show while ad is loading or if not loaded
  final Widget? placeholder;

  /// Widget to show if ad fails to load
  final Widget? errorWidget;

  /// Padding around the ad
  final EdgeInsets padding;

  /// Background color of the ad container
  final Color? backgroundColor;

  /// Border radius for the ad container
  final BorderRadius? borderRadius;

  const NativeAdWidget({
    super.key,
    required this.manager,
    this.height,
    this.width,
    this.placeholder,
    this.errorWidget,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (!manager.isLoaded || manager.nativeAd == null) {
      return placeholder ?? const SizedBox.shrink();
    }

    Widget adWidget = AdWidget(ad: manager.nativeAd!);

    if (height != null || width != null) {
      adWidget = SizedBox(height: height, width: width, child: adWidget);
    }

    if (backgroundColor != null || borderRadius != null) {
      adWidget = Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
        ),
        clipBehavior: borderRadius != null ? Clip.antiAlias : Clip.none,
        child: adWidget,
      );
    }

    if (padding != EdgeInsets.zero) {
      adWidget = Padding(padding: padding, child: adWidget);
    }

    return adWidget;
  }
}

/// A self-contained native ad widget that handles its own loading.
///
/// This is the simplest way to add a native ad - just drop it in your widget tree!
///
/// Usage:
/// ```dart
/// EasyNativeAd(
///   factoryId: NativeAdFactoryIds.medium,
///   height: 300,
/// )
/// ```
class EasyNativeAd extends StatefulWidget {
  /// Factory ID for the native ad layout
  final String factoryId;

  /// Height of the ad (required for proper layout)
  final double height;

  /// Width of the ad (defaults to full width)
  final double? width;

  /// Widget to show while ad is loading
  final Widget? loadingWidget;

  /// Widget to show if ad fails to load
  final Widget? errorWidget;

  /// Padding around the ad
  final EdgeInsets padding;

  /// Background color
  final Color? backgroundColor;

  /// Border radius
  final BorderRadius? borderRadius;

  /// Callback when ad is loaded
  final VoidCallback? onAdLoaded;

  /// Callback when ad fails to load
  final VoidCallback? onAdFailedToLoad;

  const EasyNativeAd({
    super.key,
    this.factoryId = 'medium_template',
    required this.height,
    this.width,
    this.loadingWidget,
    this.errorWidget,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.borderRadius,
    this.onAdLoaded,
    this.onAdFailedToLoad,
  });

  @override
  State<EasyNativeAd> createState() => _EasyNativeAdState();
}

class _EasyNativeAdState extends State<EasyNativeAd> {
  final NativeAdManager _manager = NativeAdManager();
  bool _isLoaded = false;
  bool _hasError = false;
  bool _adsEnabled = true;
  bool _isInitialized = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _adsEnabled = AdsEnabledManager.instance.isEnabled;

    if (_adsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        _isInitialized = true;
        _loadAd();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        _isInitialized = true;
      });
    }

    AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);
  }

  void _onAdsEnabledChanged(bool isEnabled) {
    // Check disposed flag first to prevent callbacks after dispose
    if (_isDisposed || !mounted || !_isInitialized) return;

    setState(() => _adsEnabled = isEnabled);
    if (isEnabled && !_isLoaded && !_hasError) {
      _loadAd();
    } else if (!isEnabled) {
      _manager.dispose();
      _isLoaded = false;
    }
  }

  Future<void> _loadAd() async {
    if (!_adsEnabled || !_isInitialized) return;

    await _manager.loadAd(
      factoryId: widget.factoryId,
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isLoaded = true;
            _hasError = false;
          });
          widget.onAdLoaded?.call();
        }
      },
      onAdFailedToLoad: (error) {
        if (mounted) {
          setState(() {
            _isLoaded = false;
            _hasError = true;
          });
          widget.onAdFailedToLoad?.call();
        }
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if ads are disabled
    if (!_adsEnabled) return const SizedBox.shrink();

    if (_hasError) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    if (!_isLoaded) {
      return SizedBox(
        height: widget.height,
        width: widget.width,
        child:
            widget.loadingWidget ??
            Container(
              decoration: BoxDecoration(
                color: widget.backgroundColor ?? Colors.grey[200],
                borderRadius: widget.borderRadius,
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      );
    }

    return NativeAdWidget(
      manager: _manager,
      height: widget.height,
      width: widget.width,
      padding: widget.padding,
      backgroundColor: widget.backgroundColor,
      borderRadius: widget.borderRadius,
    );
  }
}

/// Helper class for building native ad layouts programmatically.
///
/// Use this to create consistent spacing and sizing across different
/// native ad implementations.
class NativeAdLayoutHelper {
  NativeAdLayoutHelper._();

  /// Recommended heights for different native ad factory types
  static const Map<String, double> recommendedHeights = {
    'small_template': 100,
    'medium_template': 250,
    'full_template': 350,
    'list_item_template': 80,
    'card_template': 300,
    'banner_template': 60,
  };

  /// Get recommended height for a factory ID
  static double getRecommendedHeight(String factoryId) {
    return recommendedHeights[factoryId] ?? 250;
  }
}
