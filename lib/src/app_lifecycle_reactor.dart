// Copyright 2024 - AdMob Integration Package
// App Lifecycle Reactor for monitoring app state changes

import 'package:flutter/material.dart';

import 'app_open_ad_manager.dart';

/// Monitors app lifecycle changes and shows app open ads accordingly.
///
/// This class uses Flutter's native [WidgetsBindingObserver] to detect
/// when the app comes to the foreground, and automatically shows an
/// app open ad if one is available.
///
/// Example usage:
/// ```dart
/// final appOpenManager = AppOpenAdManager();
/// final lifecycleReactor = AppLifecycleReactor(appOpenAdManager: appOpenManager);
///
/// // Start listening for app state changes
/// lifecycleReactor.startListening();
///
/// // Don't forget to dispose when done
/// lifecycleReactor.dispose();
/// ```
class AppLifecycleReactor with WidgetsBindingObserver {
  final AppOpenAdManager _appOpenAdManager;
  bool _isListening = false;
  bool _isPaused = false;
  bool _wasInBackground = false;
  DateTime? _lastAdShowTime;
  bool _isShowingAd = false;
  int _foregroundAdCount = 0;

  /// Maximum number of app open ads to show on foreground per session.
  /// Set to 0 for unlimited. This does NOT count the cold start ad.
  int maxForegroundAdsPerSession;

  /// Minimum time between showing app open ads.
  /// This prevents ads from showing in a loop when dismissing triggers resume.
  static const Duration _minTimeBetweenAds = Duration(seconds: 10);

  /// Creates an [AppLifecycleReactor] with the given [AppOpenAdManager].
  ///
  /// [maxForegroundAdsPerSession] limits how many ads show when returning
  /// from background. Set to 0 for unlimited. Default is 1.
  AppLifecycleReactor({
    required AppOpenAdManager appOpenAdManager,
    this.maxForegroundAdsPerSession = 1,
  }) : _appOpenAdManager = appOpenAdManager;

  /// Number of foreground ads shown this session
  int get foregroundAdCount => _foregroundAdCount;

  /// Whether the reactor is currently listening for app state changes.
  bool get isListening => _isListening;

  /// Whether the reactor is paused (won't show ads even when listening).
  bool get isPaused => _isPaused;

  /// Resets the foreground ad counter (call this to allow more ads)
  void resetForegroundAdCount() {
    _foregroundAdCount = 0;
    debugPrint('🔄 AppLifecycleReactor: Foreground ad count reset');
  }

  /// Starts listening for app state changes.
  ///
  /// When the app comes to the foreground (from background), an app open
  /// ad will be shown if one is available.
  void startListening() {
    if (_isListening) {
      debugPrint('🔄 AppLifecycleReactor: Already listening');
      return;
    }

    debugPrint(
      '🔄 AppLifecycleReactor: ✅ Starting to listen (WidgetsBindingObserver)',
    );
    _isListening = true;
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🔄 AppLifecycleReactor: ✅ Observer added successfully');
  }

  /// Stops listening for app state changes.
  void stopListening() {
    if (!_isListening) {
      debugPrint('AppLifecycleReactor: Not listening');
      return;
    }

    debugPrint('AppLifecycleReactor: Stopping listening');
    WidgetsBinding.instance.removeObserver(this);
    _isListening = false;
  }

  /// Pauses the reactor temporarily.
  ///
  /// Use this when you don't want app open ads to show, for example
  /// during a purchase flow or when the user is filling out a form.
  ///
  /// Call [resume] to start showing ads again.
  void pause() {
    debugPrint('AppLifecycleReactor: Paused');
    _isPaused = true;
  }

  /// Resumes the reactor after being paused.
  void resume() {
    debugPrint('AppLifecycleReactor: Resumed');
    _isPaused = false;
  }

  /// Called when the app lifecycle state changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🔄 AppLifecycleReactor: Lifecycle state changed to $state');
    debugPrint(
      '🔄 AppLifecycleReactor: isPaused=$_isPaused, wasInBackground=$_wasInBackground, isAdAvailable=${_appOpenAdManager.isAdAvailable}',
    );

    if (_isPaused) {
      debugPrint('🔄 AppLifecycleReactor: Paused, not showing ad');
      return;
    }

    // Track when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _wasInBackground = true;
      debugPrint('🔄 AppLifecycleReactor: App went to background');
    }

    // Show ad when app comes back to foreground FROM background
    if (state == AppLifecycleState.resumed && _wasInBackground) {
      debugPrint(
        '🔄 AppLifecycleReactor: ✅ Foreground detected (was in background), attempting to show ad...',
      );
      _wasInBackground = false;
      _showAppOpenAd();
    }
  }

  /// Shows an app open ad if available.
  Future<void> _showAppOpenAd() async {
    // Check if we've hit the session limit
    if (maxForegroundAdsPerSession > 0 &&
        _foregroundAdCount >= maxForegroundAdsPerSession) {
      debugPrint(
        '🔄 AppLifecycleReactor: Session limit reached ($_foregroundAdCount/$maxForegroundAdsPerSession), skipping',
      );
      return;
    }

    // Don't show if we're already in the process of showing
    if (_isShowingAd) {
      debugPrint('🔄 AppLifecycleReactor: Already in show process, skipping');
      return;
    }

    // Check cooldown to prevent ad loop
    if (_lastAdShowTime != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAdShowTime!);
      if (timeSinceLastAd < _minTimeBetweenAds) {
        final remaining = _minTimeBetweenAds - timeSinceLastAd;
        debugPrint(
          '🔄 AppLifecycleReactor: Cooldown active (${remaining.inSeconds}s remaining), skipping',
        );
        return;
      }
    }

    // Don't show if already showing
    if (_appOpenAdManager.isShowing) {
      debugPrint(
        '🔄 AppLifecycleReactor: Ad manager already showing, skipping',
      );
      return;
    }

    if (_appOpenAdManager.isAdAvailable) {
      final limitText = maxForegroundAdsPerSession > 0
          ? '(${_foregroundAdCount + 1}/$maxForegroundAdsPerSession)'
          : '(unlimited)';
      debugPrint(
        '🔄 AppLifecycleReactor: Ad available, showing now... $limitText',
      );
      _isShowingAd = true;
      _lastAdShowTime = DateTime.now();
      _foregroundAdCount++;
      await _appOpenAdManager.showAdIfAvailable(
        onAdDismissed: () {
          _isShowingAd = false;
          debugPrint(
            '🔄 AppLifecycleReactor: Ad dismissed, cooldown started. Count: $_foregroundAdCount',
          );
        },
        onAdFailedToShow: () {
          _isShowingAd = false;
          _foregroundAdCount--; // Don't count failed shows
          debugPrint('🔄 AppLifecycleReactor: Ad failed to show');
        },
      );
    } else {
      debugPrint(
        '🔄 AppLifecycleReactor: No ad available, preloading for next time...',
      );
      // Preload for next foreground event
      _appOpenAdManager.loadAd();
    }
  }

  /// Disposes of the reactor and stops listening.
  void dispose() {
    stopListening();
  }
}

/// A widget that wraps your app and handles app open ads automatically.
///
/// This widget integrates [AppLifecycleReactor] with your widget tree,
/// making it easy to show app open ads when the app comes to the foreground.
///
/// Example:
/// ```dart
/// void main() {
///   runApp(
///     AppOpenAdWrapper(
///       appOpenAdManager: myAppOpenAdManager,
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
class AppOpenAdWrapper extends StatefulWidget {
  /// The app open ad manager to use.
  final AppOpenAdManager appOpenAdManager;

  /// The child widget (usually your main app widget).
  final Widget child;

  /// Whether to load an app open ad immediately when the widget is created.
  final bool preloadAd;

  /// Whether to show an app open ad on cold start.
  final bool showOnColdStart;

  const AppOpenAdWrapper({
    super.key,
    required this.appOpenAdManager,
    required this.child,
    this.preloadAd = true,
    this.showOnColdStart = false,
  });

  @override
  State<AppOpenAdWrapper> createState() => _AppOpenAdWrapperState();
}

class _AppOpenAdWrapperState extends State<AppOpenAdWrapper> {
  late AppLifecycleReactor _lifecycleReactor;
  bool _hasShownColdStartAd = false;

  @override
  void initState() {
    super.initState();

    _lifecycleReactor = AppLifecycleReactor(
      appOpenAdManager: widget.appOpenAdManager,
    );

    // Start listening for app state changes
    _lifecycleReactor.startListening();

    // Preload ad if requested
    if (widget.preloadAd) {
      _preloadAd();
    }
  }

  Future<void> _preloadAd() async {
    await widget.appOpenAdManager.loadAd(
      onAdLoaded: (ad) {
        // Show on cold start if configured and not already shown
        if (widget.showOnColdStart && !_hasShownColdStartAd) {
          _hasShownColdStartAd = true;
          widget.appOpenAdManager.showAdIfAvailable();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleReactor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
