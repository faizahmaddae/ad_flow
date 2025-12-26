// Copyright 2024 - AdMob Integration Package
// Barrel export file for easy imports
//
// A production-ready AdMob integration package for Flutter.
//
// This package provides:
// - Banner Ads (standard adaptive and collapsible)
// - Interstitial Ads
// - App Open Ads
// - Rewarded Ads
// - Native Ads
// - GDPR, US Privacy, and iOS ATT compliance via UMP SDK
//
// Quick Start:
//
// import 'package:ad_flow/ad_flow.dart';
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   await AdFlow.instance.initialize(
//     config: AdFlowConfig.testMode(),
//     onComplete: (canRequestAds) {
//       debugPrint('Ads ready: $canRequestAds');
//     },
//   );
//
//   runApp(MyApp());
// }
//
// Setup Requirements:
//
// 1. Add your AdMob App ID to:
//    - Android: android/app/src/main/AndroidManifest.xml
//    - iOS: ios/Runner/Info.plist
//
// 2. Pass your production ad unit IDs via AdFlowConfig
//
// 3. Configure your consent message in the AdMob console

// Configuration
export 'src/ad_config.dart';

// Error Handling
export 'src/ad_error_handler.dart';

// Ads Enabled Manager (Remove Ads feature)
export 'src/ads_enabled_manager.dart';

// Consent Management (with localization support)
export 'src/consent_manager.dart';
export 'src/consent_explainer_dialog.dart';
export 'src/consent_explainer_localizations.dart';

// Ad Managers
export 'src/banner_ad_manager.dart';
export 'src/interstitial_ad_manager.dart';
export 'src/app_open_ad_manager.dart';
export 'src/native_ad_manager.dart';
export 'src/rewarded_ad_manager.dart';

// App Lifecycle
export 'src/app_lifecycle_reactor.dart';

// Easy Widgets
export 'src/easy_banner_widget.dart';
export 'src/easy_privacy_settings_button.dart';
export 'src/native_ad_widget.dart';

// Unified Service
export 'src/ad_service.dart';

// Re-export commonly used types from google_mobile_ads
export 'package:google_mobile_ads/google_mobile_ads.dart'
    show
        AdWidget,
        AdSize,
        BannerAd,
        InterstitialAd,
        AppOpenAd,
        NativeAd,
        RewardedAd,
        RewardItem,
        AdRequest,
        LoadAdError,
        AdError;
