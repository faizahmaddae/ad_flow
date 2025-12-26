// Easy-to-use Banner Ad Widget
// Just drop this widget anywhere in your app!

import 'package:flutter/material.dart';
import 'banner_ad_manager.dart';
import 'ad_config.dart' show CollapsibleBannerPlacement;
import 'ads_enabled_manager.dart';

/// A simple, self-contained banner ad widget.
///
/// This widget automatically respects the "Remove Ads" setting.
/// If ads are disabled via [AdsEnabledManager], this widget shows nothing.
///
/// Usage:
/// ```dart
/// // At bottom of screen
/// Scaffold(
///   body: YourContent(),
///   bottomNavigationBar: EasyBannerAd(),
/// )
///
/// // Or anywhere in a Column
/// Column(
///   children: [
///     YourContent(),
///     EasyBannerAd(),
///   ],
/// )
/// ```
class EasyBannerAd extends StatefulWidget {
  /// Whether to use collapsible banner (larger, then shrinks)
  final bool collapsible;

  const EasyBannerAd({super.key, this.collapsible = false});

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

  @override
  void initState() {
    super.initState();
    _adsEnabled = AdsEnabledManager.instance.isEnabled;

    // Load after first frame to ensure context is ready
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

    // Add listener after marking initialized
    AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);
  }

  void _onAdsEnabledChanged(bool isEnabled) {
    // Check disposed flag first to prevent callbacks after dispose
    if (_isDisposed || !mounted || !_isInitialized) return;

    setState(() => _adsEnabled = isEnabled);
    if (isEnabled && !_isLoaded) {
      _loadAd();
    } else if (!isEnabled) {
      _bannerManager.dispose();
      _isLoaded = false;
    }
  }

  Future<void> _loadAd() async {
    if (!_adsEnabled || !_isInitialized || !mounted) return;

    if (widget.collapsible) {
      await _bannerManager.loadCollapsibleBanner(
        context: context,
        placement: CollapsibleBannerPlacement.bottom,
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
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
          if (mounted) setState(() => _isLoaded = false);
        },
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
    _bannerManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if ads are disabled
    if (!_adsEnabled) return const SizedBox.shrink();

    // Handle orientation changes - dispose and reload banner
    // This follows Google's recommended pattern for adaptive banners
    return OrientationBuilder(
      builder: (context, orientation) {
        if (_currentOrientation != null && _currentOrientation != orientation) {
          // Orientation changed - schedule dispose and reload for proper sizing
          // Using addPostFrameCallback to avoid modifying state during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isDisposed) return;
            _bannerManager.dispose();
            setState(() => _isLoaded = false);
            _loadAd();
          });
        }
        _currentOrientation = orientation;

        if (!_isLoaded) return const SizedBox.shrink();
        return SafeArea(
          child: _bannerManager.buildAdWidget() ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
