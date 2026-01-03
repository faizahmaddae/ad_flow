## 1.3.6

* **NEW**: `EasyNativeAd` now collapses when ads fail to load (no more empty white space)
  - Added `hideOnLoading` parameter (default: `true`) - collapses while loading
  - Added `hideOnError` parameter (default: `true`) - collapses on load failure (e.g., no fill)
  - Set to `false` to show loading/error widgets with reserved height
* **FIX**: Removed double semicolon in `BannerAdManager` causing static analysis warning
* **IMPROVED**: Better UX for fixed-height layouts like `bottomNavigationBar`

## 1.3.5

* **FIX**: All ad managers now respect `AdsEnabledManager.isDisabled` state
  - `loadAd()` and `showAd()` check disabled state before proceeding
  - Fixes race condition where `disableAds()` in `onComplete` was too late
  - Affected managers: `BannerAdManager`, `InterstitialAdManager`, `RewardedAdManager`, `AppOpenAdManager`, `NativeAdManager`
* **DOCS**: Updated copilot-instructions.md with timing warning for disabling ads

## 1.3.4

* **FIX**: Applied `dart format` to all files for pub.dev static analysis compliance

## 1.3.3

* **IMPROVED**: Code quality improvements across all ad managers
  - Extracted magic numbers to named constants for better maintainability
  - Added explicit types for improved type safety in `AdFlowConfig`
  - Fixed potential memory leaks in dispose methods (banner, interstitial, app open)
* **IMPROVED**: Selective ad type preloading
  - `preloadAds()` now only preloads ad types that have real IDs configured
  - Added `hasBannerConfigured`, `hasInterstitialConfigured`, etc. getters
  - Use only the ad types you need without loading unnecessary ads
* **FIX**: `reset()` now properly calls `AdFlowConfig.resetCurrent()`
  - Previously config state persisted after reset, now fully resets
* **FIX**: Status listeners properly cleaned up in dispose methods
* **IMPROVED**: Simplified example files
  - Replaced complex demo pages with two clean, reactive examples
  - `example_with_explainer.dart` - GDPR-friendly with explainer dialog
  - `example_without_explainer.dart` - Direct initialization
  - Both examples demonstrate reactive UI with status listeners

## 1.3.2

* **NEW**: Centralized error handling with `AdFlowError` and `errorStream`
  - Subscribe to `AdFlow.instance.errorStream` for all ad-related errors
  - Use `AdFlow.instance.setErrorCallback()` for simpler callback-based handling
  - Errors include type, code, message, ad unit ID, and timestamp
  - Supports logging to analytics, crash reporting, or custom UI
* **NEW**: Comprehensive native ad factory documentation
  - Added `doc/NATIVE_ADS_SETUP.md` with platform code examples
  - Android (Kotlin) and iOS (Swift) factory implementations
  - Layout XML and XIB templates
* **BREAKING**: Removed deprecated `AdConfig` class
  - Use `AdFlowConfig.current` for static access to config values
  - Use `AdFlow.instance.config` for instance-based access
  - Cleaner API with no deprecation warnings
* **IMPROVED**: Simplified consent flow to match Google's official samples
  - Sequential popup handling prevents stacking
  - Explainer dialogs only shown when consent is actually needed

## 1.3.1

* **NEW**: Added `AdFlow.instance.reset()` for testing
  - Enables proper unit testing of singleton state
  - Clears all managers and resets initialization
* **FIX**: Fixed barrel export to use correct file (`ad_service.dart`)
* **FIX**: Fixed `use_build_context_synchronously` warnings in `BannerAdManager`
* **IMPROVED**: Added lazy initialization for ad managers
  - Managers only created when first accessed
  - Better memory efficiency for apps using subset of ad types
* **IMPROVED**: Expanded test coverage from 140 to 185 tests
  - Added `AdFlow` singleton tests
  - Added `EasyBannerAd` widget tests
  - Added `ConsentManager` tests
* Removed duplicate `ad_flow_service.dart` file

## 1.3.0

* **NEW**: Added `EasyPrivacySettingsButton` widget for GDPR compliance
  - Auto shows/hides based on privacy options requirement
  - Opens official Google privacy options form
  - Customizable text, icon, and style
* **NEW**: Added `PrivacySettingsListTile` for settings screens
* **FIX**: `initializeWithExplainer()` now properly checks AdsEnabledManager
  - Previously skipped "Remove Ads" check, now matches `initialize()` behavior
* **FIX**: `isPrivacyOptionsRequired()` now returns correct cached value
  - Was incorrectly returning `canRequestAds` instead of privacy options status
* Added production example with complete implementation guide
* Updated documentation with privacy button usage examples

## 1.2.0

* **NEW**: Added `RewardedAdManager` for rewarded video ads
  - Watch ads to earn in-app rewards (coins, lives, etc.)
  - Automatic preloading and retry logic
  - Reward callbacks with type and amount
  - Status listeners for UI updates
* Added `androidRewardedAdUnitId` and `iosRewardedAdUnitId` to `AdFlowConfig`
* Added `TestAdUnitIds.rewarded` for testing
* Re-exported `RewardedAd` and `RewardItem` from google_mobile_ads
* Updated example app with rewarded ads demo page

## 1.1.0

* **BREAKING**: Added `AdFlowConfig` for runtime configuration of ad unit IDs
* Users can now configure ad unit IDs without modifying package source code
* Added `AdFlowConfig.testMode()` factory for easy development/testing setup
* Added `TestAdUnitIds` class with Google's official test ad unit IDs
* `AdConfig` is now a proxy that reads from `AdFlowConfig`
* Updated example app to demonstrate new configuration pattern

## 1.0.2

* Added explicit platform support declaration for Android and iOS

## 1.0.1+1

* Code formatting fixes for pub.dev static analysis compliance

## 1.0.1

* Initial release
* Banner ads (adaptive and collapsible)
* Interstitial ads with cooldown management
* App open ads with lifecycle handling
* Native ads with factory support
* GDPR/ATT consent management via UMP SDK
* iOS App Tracking Transparency support
* Remove Ads feature with persistence
* Multi-language consent dialogs (English, Spanish, Persian)
