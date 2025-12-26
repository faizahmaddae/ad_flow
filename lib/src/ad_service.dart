// Copyright 2024 - AdMob Integration Package
// Unified Ad Service for initialization and coordination

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'consent_manager.dart';
import 'consent_explainer_dialog.dart';
import 'banner_ad_manager.dart';
import 'interstitial_ad_manager.dart';
import 'app_open_ad_manager.dart';
import 'app_lifecycle_reactor.dart';
import 'native_ad_manager.dart';
import 'rewarded_ad_manager.dart';
import 'ads_enabled_manager.dart';

/// Callback for ad service initialization completion.
///
/// [canRequestAds] is `true` if ads can be requested, `false` otherwise.
typedef AdFlowInitCallback = void Function(bool canRequestAds);

/// Unified service for managing all ad-related functionality.
///
/// This service:
/// - Initializes the Mobile Ads SDK
/// - Handles consent gathering
/// - Coordinates all ad managers
/// - Provides a simple API for common ad operations
///
/// Example usage:
/// ```dart
/// // Initialize in main.dart with your ad unit IDs
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await AdFlow.instance.initialize(
///     config: AdFlowConfig(
///       androidBannerAdUnitId: 'ca-app-pub-xxx/xxx',
///       iosBannerAdUnitId: 'ca-app-pub-xxx/xxx',
///       androidInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
///       iosInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
///     ),
///     onComplete: (canRequestAds) {
///       if (canRequestAds) {
///         AdFlow.instance.preloadAds();
///       }
///     },
///   );
///
///   runApp(MyApp());
/// }
///
/// // Or use test mode during development:
/// await AdFlow.instance.initialize(
///   config: AdFlowConfig.testMode(),
/// );
/// ```
class AdFlow {
  AdFlow._();
  static final AdFlow _instance = AdFlow._();

  /// Singleton instance of AdFlow
  static AdFlow get instance => _instance;

  // Managers - lazily initialized for better performance
  // Only created when first accessed, so users who only need banners
  // won't have interstitial/rewarded/etc managers taking up memory
  BannerAdManager? _bannerAdManager;
  InterstitialAdManager? _interstitialAdManager;
  AppOpenAdManager? _appOpenAdManager;
  NativeAdManager? _nativeAdManager;
  RewardedAdManager? _rewardedAdManager;
  AppLifecycleReactor? _lifecycleReactor;

  // State
  bool _isInitialized = false;
  bool _isMobileAdsInitialized = false;
  int _maxForegroundAdsPerSession = _kDefaultMaxForegroundAds;
  AdFlowConfig? _config;

  /// Default maximum foreground ads per session
  static const int _kDefaultMaxForegroundAds = 1;

  /// The current ad configuration
  AdFlowConfig get config => _config ?? AdFlowConfig.testMode();

  /// Whether the ad service is fully initialized
  bool get isInitialized => _isInitialized;

  /// Whether the Mobile Ads SDK is initialized
  bool get isMobileAdsInitialized => _isMobileAdsInitialized;

  // ============================================================
  // ERROR HANDLING
  // ============================================================

  /// Stream of all ad-related errors.
  ///
  /// Subscribe to receive errors from any ad operation:
  /// ```dart
  /// AdFlow.instance.errorStream.listen((error) {
  ///   print('Ad error: ${error.type} - ${error.message}');
  ///   // Log to analytics, show UI, etc.
  /// });
  /// ```
  Stream<AdFlowError> get errorStream =>
      AdFlowErrorHandler.instance.errorStream;

  /// Sets a callback to be invoked on every ad error.
  ///
  /// Alternative to using the stream for simpler use cases:
  /// ```dart
  /// AdFlow.instance.setErrorCallback((error) {
  ///   analytics.logEvent('ad_error', {
  ///     'type': error.type.name,
  ///     'code': error.code,
  ///     'message': error.message,
  ///   });
  /// });
  /// ```
  void setErrorCallback(AdFlowErrorCallback? callback) {
    AdFlowErrorHandler.instance.setErrorCallback(callback);
  }

  /// Clears the error callback.
  void clearErrorCallback() {
    AdFlowErrorHandler.instance.clearErrorCallback();
  }

  // ============================================================
  // ADS ENABLED (Remove Ads Feature)
  // ============================================================

  /// Whether ads are enabled (for Remove Ads feature).
  ///
  /// Returns `false` if the user has purchased "Remove Ads".
  /// All ad widgets automatically respect this setting.
  bool get isAdsEnabled => AdsEnabledManager.instance.isEnabled;

  /// Whether ads are disabled (convenience getter).
  bool get isAdsDisabled => AdsEnabledManager.instance.isDisabled;

  /// Stream of ads enabled status changes.
  ///
  /// Use for reactive UI updates:
  /// ```dart
  /// StreamBuilder<bool>(
  ///   stream: AdFlow.instance.adsEnabledStream,
  ///   builder: (context, snapshot) {
  ///     if (snapshot.data == false) return SizedBox.shrink();
  ///     return YourAdWidget();
  ///   },
  /// )
  /// ```
  Stream<bool> get adsEnabledStream => AdsEnabledManager.instance.stream;

  /// Disables all ads (call after "Remove Ads" purchase).
  ///
  /// This will:
  /// - Persist the disabled state
  /// - Stop showing all ad types
  /// - Pause the app lifecycle reactor
  ///
  /// Example:
  /// ```dart
  /// // After successful in-app purchase
  /// await AdFlow.instance.disableAds();
  /// ```
  Future<void> disableAds() async {
    await AdsEnabledManager.instance.disableAds();
    // Pause app open ads when ads are disabled
    _lifecycleReactor?.pause();
    // Dispose loaded ads to free memory
    await disposeAllAds();
  }

  /// Enables ads (call to restore ads).
  ///
  /// This will:
  /// - Persist the enabled state
  /// - Resume showing ads
  /// - Resume the app lifecycle reactor
  Future<void> enableAds() async {
    await AdsEnabledManager.instance.enableAds();
    // Resume app open ads when ads are enabled
    _lifecycleReactor?.resume();
  }

  /// Disposes all loaded ads to free memory.
  ///
  /// Call this after disabling ads or when cleaning up.
  /// Only disposes managers that were actually created.
  Future<void> disposeAllAds() async {
    await _bannerAdManager?.dispose();
    await _interstitialAdManager?.dispose();
    await _appOpenAdManager?.dispose();
    await _nativeAdManager?.dispose();
    await _rewardedAdManager?.dispose();
  }

  // ============================================================
  // MANAGERS
  // ============================================================

  /// Access to the consent manager
  ConsentManager get consent => ConsentManager.instance;

  /// Access to the banner ad manager (lazily initialized)
  BannerAdManager get banner => _bannerAdManager ??= BannerAdManager();

  /// Access to the interstitial ad manager (lazily initialized)
  InterstitialAdManager get interstitial =>
      _interstitialAdManager ??= InterstitialAdManager();

  /// Access to the app open ad manager (lazily initialized)
  AppOpenAdManager get appOpen => _appOpenAdManager ??= AppOpenAdManager();

  /// Access to the native ad manager (lazily initialized)
  NativeAdManager get native => _nativeAdManager ??= NativeAdManager();

  /// Access to the rewarded ad manager (lazily initialized)
  RewardedAdManager get rewarded => _rewardedAdManager ??= RewardedAdManager();

  /// Access to the app lifecycle reactor (after initialization)
  AppLifecycleReactor? get lifecycleReactor => _lifecycleReactor;

  /// Initializes the ad service.
  ///
  /// This method:
  /// 1. Gathers user consent (GDPR, ATT, etc.)
  /// 2. Initializes the Mobile Ads SDK if consent allows
  /// 3. Sets up the app lifecycle reactor for app open ads
  ///
  /// [onComplete] is called when initialization is complete, with a boolean
  /// indicating whether ads can be requested.
  ///
  /// [config] ad unit IDs and settings. Use [AdFlowConfig.testMode()] for development.
  /// [preloadInterstitial] if true, preloads an interstitial ad after init.
  /// [preloadRewarded] if true, preloads a rewarded ad after init.
  /// [preloadAppOpen] if true, preloads an app open ad after init (default: false).
  /// [enableAppOpenOnForeground] if true, enables automatic app open ads.
  /// [showAppOpenOnColdStart] if true, shows app open ad on first launch.
  /// [maxForegroundAdsPerSession] limits foreground ads per session (0 = unlimited).
  Future<void> initialize({
    AdFlowConfig? config,
    AdFlowInitCallback? onComplete,
    bool preloadInterstitial = false,
    bool preloadRewarded = false,
    bool preloadAppOpen = false,
    bool enableAppOpenOnForeground = false,
    bool showAppOpenOnColdStart = false,
    int maxForegroundAdsPerSession = 1,
  }) async {
    if (_isInitialized) {
      debugPrint('AdFlow: Already initialized');
      onComplete?.call(consent.canRequestAds);
      return;
    }

    // Set config (defaults to test mode if not provided)
    _config = config ?? AdFlowConfig.testMode();
    AdFlowConfig.setCurrent(_config!);

    debugPrint('AdFlow: Starting initialization...');
    debugPrint(
      'AdFlow: Using test ads: ${AdFlowConfig.current.isUsingTestAds}',
    );
    _maxForegroundAdsPerSession = maxForegroundAdsPerSession;

    // Step 0: Initialize AdsEnabledManager (for Remove Ads feature)
    await AdsEnabledManager.instance.initialize();

    // Check if ads are disabled (user purchased Remove Ads)
    if (AdsEnabledManager.instance.isDisabled) {
      debugPrint('AdFlow: Ads are disabled (Remove Ads purchased)');
      _isInitialized = true;
      onComplete?.call(false);
      return;
    }

    // Step 1: Gather consent
    await consent.gatherConsent(
      onConsentGatheringComplete: (error) async {
        if (error != null) {
          debugPrint('AdFlow: Consent error: ${error.message}');
        }

        // Step 2: Initialize Mobile Ads SDK if we can request ads
        bool sdkInitialized = false;
        if (consent.canRequestAds && !_isMobileAdsInitialized) {
          sdkInitialized = await _initializeMobileAds();
        } else {
          sdkInitialized = _isMobileAdsInitialized;
        }

        // Only proceed with ad operations if SDK initialized successfully
        if (consent.canRequestAds && sdkInitialized) {
          // Step 3: Setup lifecycle reactor for app open ads
          if (enableAppOpenOnForeground) {
            _setupLifecycleReactor();
          }

          // Step 4: Preload ads if configured
          if (preloadInterstitial) {
            interstitial.loadAd();
          }
          if (preloadRewarded) {
            rewarded.loadAd();
          }
          if (preloadAppOpen) {
            // Load and wait for the ad to be ready
            final adLoaded = await appOpen.loadAdAndWait();

            // Show app open ad on cold start if enabled and ad is ready
            if (showAppOpenOnColdStart && adLoaded && appOpen.isAdAvailable) {
              debugPrint('AdFlow: Showing app open ad on cold start');
              await appOpen.showAdIfAvailable();
            }
          }
        } else if (consent.canRequestAds && !sdkInitialized) {
          debugPrint('AdFlow: SDK initialization failed, skipping ad preload');
        }

        _isInitialized = true;
        debugPrint('AdFlow: Initialization complete');
        debugPrint(
          'AdFlow: Can request ads: ${consent.canRequestAds && sdkInitialized}',
        );

        onComplete?.call(consent.canRequestAds && sdkInitialized);
      },
    );
  }

  /// Initializes the ad service WITH a pre-consent explainer dialog.
  ///
  /// This is the same as [initialize] but shows a friendly explainer dialog
  /// before any consent popups appear, giving users context about why
  /// they're being asked for consent.
  ///
  /// Use this in a widget's initState or after the first frame:
  /// ```dart
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   WidgetsBinding.instance.addPostFrameCallback((_) {
  ///     AdFlow.instance.initializeWithExplainer(
  ///       context: context,
  ///       onComplete: (canRequestAds) {
  ///         if (canRequestAds) {
  ///           AdFlow.instance.preloadAds();
  ///         }
  ///       },
  ///     );
  ///   });
  /// }
  /// ```
  ///
  /// For localization, pass custom texts:
  /// ```dart
  /// AdFlow.instance.initializeWithExplainer(
  ///   context: context,
  ///   consentTexts: ConsentExplainerTexts(
  ///     title: 'Votre vie privée compte',
  ///     continueButton: 'Continuer',
  ///   ),
  ///   attTexts: ATTExplainerTexts(
  ///     title: 'Autoriser le suivi?',
  ///     gotItButton: 'Compris',
  ///   ),
  /// );
  /// ```
  Future<void> initializeWithExplainer({
    required BuildContext context,
    AdFlowConfig? config,
    AdFlowInitCallback? onComplete,
    bool preloadInterstitial = false,
    bool preloadRewarded = false,
    bool preloadAppOpen = false,
    bool enableAppOpenOnForeground = false,
    bool showAppOpenOnColdStart = false,
    int maxForegroundAdsPerSession = 1,
    bool showExplainer = true,
    ConsentExplainerTexts consentTexts = kDefaultConsentExplainerTexts,
    ATTExplainerTexts attTexts = kDefaultATTExplainerTexts,
  }) async {
    if (_isInitialized) {
      debugPrint('AdFlow: Already initialized');
      onComplete?.call(consent.canRequestAds);
      return;
    }

    // Set config (defaults to test mode if not provided)
    _config = config ?? AdFlowConfig.testMode();
    AdFlowConfig.setCurrent(_config!);

    debugPrint('AdFlow: Starting initialization with explainer...');
    debugPrint(
      'AdFlow: Using test ads: ${AdFlowConfig.current.isUsingTestAds}',
    );
    _maxForegroundAdsPerSession = maxForegroundAdsPerSession;

    // Step 1: Gather consent WITH explainer dialog
    await consent.gatherConsentWithExplainer(
      context: context,
      showExplainer: showExplainer,
      consentTexts: consentTexts,
      attTexts: attTexts,
      onConsentGatheringComplete: (error) async {
        if (error != null) {
          debugPrint('AdFlow: Consent error: ${error.message}');
        }

        // Step 2: Initialize Mobile Ads SDK if we can request ads
        bool sdkInitialized = false;
        if (consent.canRequestAds && !_isMobileAdsInitialized) {
          sdkInitialized = await _initializeMobileAds();
        } else {
          sdkInitialized = _isMobileAdsInitialized;
        }

        // Only proceed with ad operations if SDK initialized successfully
        if (consent.canRequestAds && sdkInitialized) {
          // Step 3: Setup lifecycle reactor for app open ads
          if (enableAppOpenOnForeground) {
            _setupLifecycleReactor();
          }

          // Step 4: Preload ads if configured
          if (preloadInterstitial) {
            interstitial.loadAd();
          }
          if (preloadRewarded) {
            rewarded.loadAd();
          }
          if (preloadAppOpen) {
            final adLoaded = await appOpen.loadAdAndWait();

            if (showAppOpenOnColdStart && adLoaded && appOpen.isAdAvailable) {
              debugPrint('AdFlow: Showing app open ad on cold start');
              await appOpen.showAdIfAvailable();
            }
          }
        } else if (consent.canRequestAds && !sdkInitialized) {
          debugPrint('AdFlow: SDK initialization failed, skipping ad preload');
        }

        _isInitialized = true;
        debugPrint('AdFlow: Initialization complete (with explainer)');
        debugPrint(
          'AdFlow: Can request ads: ${consent.canRequestAds && sdkInitialized}',
        );

        onComplete?.call(consent.canRequestAds && sdkInitialized);
      },
    );
  }

  /// Initializes the Mobile Ads SDK.
  ///
  /// Returns `true` if initialization succeeded, `false` otherwise.
  Future<bool> _initializeMobileAds() async {
    debugPrint('AdFlow: Initializing Mobile Ads SDK...');

    try {
      await MobileAds.instance.initialize();
      _isMobileAdsInitialized = true;
      debugPrint('AdFlow: Mobile Ads SDK initialized');

      // Set request configuration
      final config = RequestConfiguration(
        testDeviceIds: AdFlowConfig.current.testDeviceIds,
        tagForUnderAgeOfConsent: AdFlowConfig.current.tagForUnderAgeOfConsent
            ? TagForUnderAgeOfConsent.yes
            : TagForUnderAgeOfConsent.no,
      );
      await MobileAds.instance.updateRequestConfiguration(config);
      return true;
    } catch (e) {
      debugPrint('AdFlow: Failed to initialize Mobile Ads SDK: $e');
      _isMobileAdsInitialized = false;
      return false;
    }
  }

  /// Sets up the app lifecycle reactor for app open ads.
  void _setupLifecycleReactor() {
    _lifecycleReactor = AppLifecycleReactor(
      appOpenAdManager: appOpen, // Uses lazy getter
      maxForegroundAdsPerSession: _maxForegroundAdsPerSession,
    );
    _lifecycleReactor!.startListening();
    debugPrint(
      'AdFlow: Lifecycle reactor started (max foreground ads: $_maxForegroundAdsPerSession)',
    );
  }

  /// Preloads ad types that have real (non-test) IDs configured.
  ///
  /// Call this after initialization when you know ads can be requested.
  /// Only creates managers for ad types that have production IDs configured,
  /// so you can safely call this even if you only use some ad types.
  ///
  /// For test mode, nothing will be preloaded (use explicit preload flags
  /// in [initialize] instead).
  Future<void> preloadAds() async {
    if (!consent.canRequestAds) {
      debugPrint('AdFlow: Cannot request ads, skipping preload');
      return;
    }

    final futures = <Future<void>>[];

    if (config.hasInterstitialConfigured) {
      debugPrint('AdFlow: Preloading interstitial ad...');
      futures.add(interstitial.loadAd());
    }

    if (config.hasAppOpenConfigured) {
      debugPrint('AdFlow: Preloading app open ad...');
      futures.add(appOpen.loadAd());
    }

    if (config.hasRewardedConfigured) {
      debugPrint('AdFlow: Preloading rewarded ad...');
      futures.add(rewarded.loadAd());
    }

    if (futures.isEmpty) {
      debugPrint(
        'AdFlow: No ad types configured for preload (test mode or no IDs set)',
      );
      return;
    }

    debugPrint('AdFlow: Preloading ${futures.length} ad type(s)...');
    await Future.wait(futures);
  }

  /// Checks if privacy options are required and should be shown.
  bool get isPrivacyOptionsRequired => consent.isPrivacyOptionsRequired();

  /// Shows the privacy options form.
  void showPrivacyOptions({VoidCallback? onComplete}) {
    consent.showPrivacyOptionsForm(
      onComplete: (error) {
        if (error != null) {
          debugPrint('AdFlow: Privacy form error: ${error.message}');
        }
        onComplete?.call();
      },
    );
  }

  /// Opens the Ad Inspector for debugging.
  ///
  /// This is useful during development to inspect ad behavior.
  void openAdInspector() {
    MobileAds.instance.openAdInspector((error) {
      if (error != null) {
        debugPrint('AdFlow: Ad Inspector error: ${error.message}');
      }
    });
  }

  /// Pauses app open ads temporarily.
  ///
  /// Use this during sensitive flows like purchases.
  void pauseAppOpenAds() {
    _lifecycleReactor?.pause();
  }

  /// Resumes app open ads after pausing.
  void resumeAppOpenAds() {
    _lifecycleReactor?.resume();
  }

  /// Disposes of all ad resources.
  /// Only disposes managers that were actually created.
  Future<void> dispose() async {
    await _bannerAdManager?.dispose();
    await _interstitialAdManager?.dispose();
    await _appOpenAdManager?.dispose();
    await _nativeAdManager?.dispose();
    await _rewardedAdManager?.dispose();
    _lifecycleReactor?.dispose();
    _isInitialized = false;
    debugPrint('AdFlow: Disposed');
  }

  /// Resets the AdFlow singleton state for testing purposes.
  ///
  /// WARNING: Only use this during development/testing.
  /// This will:
  /// - Dispose all ad managers
  /// - Reset all internal state
  /// - Allow re-initialization
  ///
  /// Example:
  /// ```dart
  /// // In tests
  /// setUp(() async {
  ///   await AdFlow.instance.reset();
  /// });
  /// ```
  Future<void> reset() async {
    debugPrint('AdFlow: Resetting state...');
    await dispose();
    _bannerAdManager = null;
    _interstitialAdManager = null;
    _appOpenAdManager = null;
    _nativeAdManager = null;
    _rewardedAdManager = null;
    _lifecycleReactor = null;
    _isMobileAdsInitialized = false;
    _maxForegroundAdsPerSession = _kDefaultMaxForegroundAds;
    _config = null;
    AdFlowConfig.resetCurrent();
    debugPrint('AdFlow: State reset complete');
  }
}
