## 1.3.14

* **NEW**: Non-blocking initialization for instant app startup
  - App can start immediately without waiting for AdFlow to initialize
  - Ads load in background while users interact with the app
  - Dramatically improves user experience on slow networks
* **NEW**: `waitForInit()` method - waits for initialization to complete
  - Returns `Future<bool>` indicating if ads can be requested
  - Returns immediately if already initialized
  - Use for fullscreen ads (interstitial, rewarded) before showing
* **NEW**: `initStream` - broadcast stream that emits when initialization completes
  - Widgets can subscribe and react when AdFlow becomes ready
  - Useful for complex scenarios requiring custom ad loading
* **IMPROVED**: `EasyBannerAd` and `EasyNativeAd` are now fully reactive
  - Automatically subscribe to `initStream` on mount
  - Auto-load ads when AdFlow initialization completes
  - No code changes required - existing widgets work seamlessly
* **IMPROVED**: Test coverage expanded from 309 to 328 tests
  - Added tests for `waitForInit()` behavior
  - Added tests for reactive widget initialization
  - Added tests for stream subscription cleanup

## 1.3.13

* **FIX**: Ad managers now properly guard against dispose-during-retry crashes
  - Added `_isDisposed` flag to `InterstitialAdManager`, `RewardedAdManager`, `AppOpenAdManager`, `NativeAdManager`
  - Retry loops now exit early if manager is disposed mid-operation
  - Prevents `setState() called after dispose()` errors in edge cases
* **FIX**: Status listener iteration is now safe from concurrent modification
  - All ad managers now use `List.of()` when notifying listeners
  - Prevents `ConcurrentModificationError` if listener removes itself during callback
* **FIX**: Removed unnecessary `meta` import in `ad_service.dart`
* **IMPROVED**: Test coverage expanded from 227 to 309 tests
  - Added comprehensive tests for `EasyPrivacySettingsButton` and `PrivacySettingsListTile`
  - Added dispose guard tests for all ad managers
  - Added listener safety tests for concurrent modification scenarios

## 1.3.12

* **FIX**: Splash screen remains too long when AdMob initialization is slow ([#4](https://github.com/faizahmaddae/ad_flow/issues/4))
  - Added smart timeouts with sensible defaults to prevent indefinite blocking
  - `consentNetworkTimeout` (default: 10s) - Timeout for consent info network request, falls back to cached status
  - `sdkInitTimeout` (default: 8s) - Timeout for Mobile Ads SDK initialization, retries in background
  - `coldStartAdTimeout` (default: 3s) - Timeout for cold-start app open ad loading
  - Consent dialogs are NOT affected - they always wait for user interaction (compliance)
  - Zero code changes required - existing apps get faster initialization automatically
* **IMPROVED**: Background retry for SDK initialization if timeout occurs
* **IMPROVED**: Cold-start app open ads now use bounded timeout instead of blocking indefinitely

## 1.3.11

* **FIX**: `AppOpenAdManager.addStatusListener` callback now fires correctly ([#3](https://github.com/faizahmaddae/ad_flow/issues/3))
  - Status listeners were not notified when using `showAdIfAvailable()`
  - Now properly calls `_notifyStatusListeners()` on show/dismiss/fail events
* **FIX**: iOS App Store rejection for GDPR shown after ATT denial ([#2](https://github.com/faizahmaddae/ad_flow/issues/2))
  - Added `skipGdprConsentIfAttDenied` config option (default: `true`)
  - When user selects "Ask App Not to Track", GDPR consent UI is skipped
  - Prevents Apple Guideline 5.1.1 rejections
  - Set to `false` if you legally require showing GDPR consent regardless of ATT
* **NEW**: `ConsentManager.lastAttStatus` and `isAttDenied` getters
  - Access the iOS ATT authorization status after consent gathering

## 1.3.10

* **NEW**: `EasyBannerAd` now supports custom ad sizes
  - Use `EasyBannerAd(adSize: AdSize.mediumRectangle)` for fixed-size banners
  - Supports all standard sizes: `banner`, `largeBanner`, `mediumRectangle`, `leaderboard`, etc.
  - Fixed-size banners skip orientation handling for better performance
  - Priority: `adSize` > `collapsible` > adaptive (default)

## 1.3.9

* **FIX**: Export `BannerAdListener` from `google_mobile_ads` (fixes [#1](https://github.com/faizahmaddae/ad_flow/issues/1))
  - Allows users to create custom-sized `BannerAd` instances directly
* **NEW**: Added `BannerAdManager.loadBanner()` method for custom ad sizes
  - Load banners with specific sizes like `AdSize.mediumRectangle` (300x250) for dialogs
  - Same consent/disabled checks and callbacks as `loadAdaptiveBanner()`

## 1.3.8

* **NEW**: Mediation support for third-party ad networks
  - Added `MediationHelper` class for forwarding consent to mediation networks
  - Built-in support for Unity Ads and AppLovin with convenience methods
  - Register custom adapters for any mediation network
  - Consent auto-forwarded during `initialize()` / `initializeWithExplainer()`
  - See `doc/MEDIATION_SETUP.md` for complete integration guide
* **DOCS**: Added comprehensive mediation documentation
* **IMPROVED**: Updated copilot-instructions.md with mediation patterns

## 1.3.7

* **FIX**: `NativeAdWidget` now respects `AdsEnabledManager.isDisabled` on initial build
* **IMPROVED**: Added comprehensive tests for `EasyNativeAd` and `NativeAdWidget` ads-disabled behavior

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
