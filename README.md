# ad_flow

Easy AdMob integration for Flutter — banners, interstitials, rewarded, native, and app open ads with built-in GDPR/ATT consent and mediation support.

[![pub package](https://img.shields.io/pub/v/ad_flow.svg)](https://pub.dev/packages/ad_flow)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-blue.svg)](https://flutter.dev)
[![google_mobile_ads](https://img.shields.io/badge/google__mobile__ads-7.0.0-green.svg)](https://pub.dev/packages/google_mobile_ads)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Table of Contents

1. [Installation](#step-1-installation)
2. [Platform Setup](#step-2-platform-setup)
3. [Initialize AdFlow](#step-3-initialize-adflow)
4. [Show Banner Ads](#step-4-show-banner-ads)
5. [Show Interstitial Ads](#step-5-show-interstitial-ads)
6. [Show Rewarded Ads](#step-6-show-rewarded-ads)
7. [Show App Open Ads](#step-7-show-app-open-ads)
8. [Show Native Ads](#step-8-show-native-ads)
9. [Remove Ads (In-App Purchase)](#step-9-remove-ads-in-app-purchase)
10. [Privacy & Consent](#step-10-privacy--consent)
11. [Error Handling](#step-11-error-handling)
12. [Mediation](#step-12-mediation)
13. [Configuration Reference](#step-13-configuration-reference)
14. [Troubleshooting](#troubleshooting)

---

## Step 1: Installation

Add `ad_flow` to your `pubspec.yaml`:

```yaml
dependencies:
  ad_flow: ^1.3.14
```

Then run:

```bash
flutter pub get
```

---

## Step 2: Platform Setup

### Android

Open `android/app/src/main/AndroidManifest.xml` and add your AdMob App ID inside `<application>`:

```xml
<manifest>
    <application>
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
    </application>
</manifest>
```

### iOS

Open `ios/Runner/Info.plist` and add:

```xml
<!-- AdMob App ID -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>

<!-- App Tracking Transparency description (required) -->
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>

<!-- SKAdNetwork IDs (required for iOS 14+) -->
<key>SKAdNetworkItems</key>
<array>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>cstr6suwn9.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>4fzdc2evr5.skadnetwork</string>
    </dict>
    <!-- Add more from https://developers.google.com/admob/ios/quick-start#update_your_infoplist -->
</array>
```

> Get the full SKAdNetwork IDs list from the [AdMob documentation](https://developers.google.com/admob/ios/quick-start#update_your_infoplist).

---

## Step 3: Initialize AdFlow

AdFlow is a singleton — initialize it **once**, then use it anywhere in your app.

### Option A: Quick Start (test mode)

```dart
import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdFlow.instance.initialize(
    config: AdFlowConfig.testMode(), // Uses Google's test ad unit IDs
    onComplete: (canRequestAds) {
      debugPrint('Ads ready: $canRequestAds');
    },
  );

  runApp(const MyApp());
}
```

### Option B: Production

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdFlow.instance.initialize(
    config: AdFlowConfig(
      androidBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER',
      iosBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER',
      androidInterstitialAdUnitId: 'ca-app-pub-YOUR_ID/INTERSTITIAL',
      iosInterstitialAdUnitId: 'ca-app-pub-YOUR_ID/INTERSTITIAL',
      androidRewardedAdUnitId: 'ca-app-pub-YOUR_ID/REWARDED',
      iosRewardedAdUnitId: 'ca-app-pub-YOUR_ID/REWARDED',
      androidAppOpenAdUnitId: 'ca-app-pub-YOUR_ID/APP_OPEN',
      iosAppOpenAdUnitId: 'ca-app-pub-YOUR_ID/APP_OPEN',
      androidNativeAdUnitId: 'ca-app-pub-YOUR_ID/NATIVE',
      iosNativeAdUnitId: 'ca-app-pub-YOUR_ID/NATIVE',
    ),
    preloadInterstitial: true,
    preloadRewarded: true,
    onComplete: (canRequestAds) {
      debugPrint('Ads ready: $canRequestAds');
    },
  );

  runApp(const MyApp());
}
```

### Option C: Non-Blocking (Recommended)

The app starts instantly. Ads load in the background. Reactive widgets (`EasyBannerAd`, `EasyNativeAd`) automatically display when ready.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp()); // App starts immediately!
}
```

Then in your first page:

```dart
class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // No await — runs in background
      AdFlow.instance.initializeWithExplainer(
        context: context,
        config: AdFlowConfig.testMode(),
        preloadInterstitial: true,
        onComplete: (canRequestAds) {
          debugPrint('Ads ready: $canRequestAds');
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(child: Text('App loaded instantly!')),
      // Banner appears automatically when AdFlow finishes initializing
      bottomNavigationBar: const EasyBannerAd(),
    );
  }
}
```

> **`initialize` vs `initializeWithExplainer`:**
> Both do the same thing. The only difference is `initializeWithExplainer` shows a friendly explanation dialog *before* the system consent prompts, giving users context about why they're asked. It requires a `BuildContext`, so call it from a widget.

### What happens during initialization

```
1. Load "Remove Ads" state from SharedPreferences
2. Gather consent (iOS ATT prompt → GDPR/UMP dialog)
3. Initialize the Google Mobile Ads SDK
4. Preload ads (interstitial, rewarded, etc. based on config flags)
5. Emit on initStream → reactive widgets auto-load
```

### Waiting for init completion

For fullscreen ads, you may need to wait for initialization:

```dart
// Returns true if ads can be requested, false if consent denied or failed
final isReady = await AdFlow.instance.waitForInit();

if (isReady) {
  await AdFlow.instance.interstitial.showAd();
}
```

Or subscribe to the stream:

```dart
late StreamSubscription<bool> _initSub;

@override
void initState() {
  super.initState();
  _initSub = AdFlow.instance.initStream.listen((canRequestAds) {
    if (canRequestAds) {
      // Safe to load/show ads
    }
  });
}

// Always cancel in dispose()!
@override
void dispose() {
  _initSub.cancel();
  super.dispose();
}
```

---

## Step 4: Show Banner Ads

### The Easy Way

Drop `EasyBannerAd` into any widget tree. It handles loading, lifecycle, and error recovery automatically:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: const Center(child: Text('My App')),
    bottomNavigationBar: const EasyBannerAd(),
  );
}
```

Collapsible banner:

```dart
const EasyBannerAd(collapsible: true)
```

Fixed-size banner:

```dart
const EasyBannerAd(adSize: AdSize.mediumRectangle) // 300×250
```

### With More Control

Use `BannerAdManager` directly when you need custom callbacks or manual load timing:

```dart
class _MyPageState extends State<MyPage> {
  final _bannerManager = BannerAdManager();

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    await _bannerManager.loadAdaptiveBanner(
      context: context,
      onAdLoaded: (ad) => setState(() {}),
      onAdFailedToLoad: (ad, error) {
        debugPrint('Banner failed: ${error.message}');
      },
    );
  }

  @override
  void dispose() {
    _bannerManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Text('Content'),
      bottomNavigationBar: _bannerManager.isLoaded
          ? _bannerManager.buildAdWidget()
          : const SizedBox.shrink(),
    );
  }
}
```

### Common Banner Sizes

| Size | Constant | Best For |
|------|----------|----------|
| 320×50 | `AdSize.banner` | Phone footer |
| 320×100 | `AdSize.largeBanner` | Tablets |
| 300×250 | `AdSize.mediumRectangle` | In-feed, dialogs |
| Adaptive | `loadAdaptiveBanner()` | Any screen (recommended) |

---

## Step 5: Show Interstitial Ads

Interstitial ads are full-screen ads shown at natural transition points (e.g., between levels, after completing a task).

### Show a preloaded interstitial

```dart
// If you set preloadInterstitial: true during init, the ad is already loaded
await AdFlow.instance.interstitial.showAd(
  onAdDismissed: () {
    // User closed the ad — continue your flow
    Navigator.pushNamed(context, '/nextScreen');
  },
  onAdFailedToShow: () {
    // Ad wasn't ready — continue anyway
    Navigator.pushNamed(context, '/nextScreen');
  },
);
```

### Load and show manually

```dart
// Load
await AdFlow.instance.interstitial.loadAd(
  onAdLoaded: (_) => debugPrint('Interstitial ready'),
  onAdFailedToLoad: (error) => debugPrint('Failed: ${error.message}'),
);

// Show when ready
if (AdFlow.instance.interstitial.isLoaded) {
  await AdFlow.instance.interstitial.showAd();
}
```

### Show every N actions

```dart
int _actionCount = 0;

void _onUserAction() {
  _actionCount++;
  if (_actionCount % 5 == 0 && AdFlow.instance.interstitial.isLoaded) {
    AdFlow.instance.interstitial.showAd();
  }
}
```

### Built-in cooldown

Interstitials have a 30-second cooldown by default (configurable via `minInterstitialInterval` in `AdFlowConfig`). This prevents showing too many ads in a row. Check with:

```dart
if (AdFlow.instance.interstitial.canShowAd) {
  // Cooldown has passed, safe to show
}
```

To bypass the cooldown for a specific show call:

```dart
await AdFlow.instance.interstitial.showAd(
  ignoreCooldown: true, // Skip the 30s cooldown for this call
  onAdDismissed: () => debugPrint('Ad dismissed'),
);
```

---

## Step 6: Show Rewarded Ads

Rewarded ads let users watch a video in exchange for a reward (coins, extra lives, etc.).

### Load and show

```dart
// Load
await AdFlow.instance.rewarded.loadAd(
  onAdLoaded: (_) => debugPrint('Rewarded ad ready'),
  onAdFailedToLoad: (error) => debugPrint('Failed: ${error.message}'),
);

// Show
await AdFlow.instance.rewarded.showAd(
  onUserEarnedReward: (reward) {
    setState(() {
      _coins += reward.amount.toInt();
    });
    debugPrint('Earned ${reward.amount} ${reward.type}');
  },
  onAdDismissed: () => debugPrint('Ad closed'),
  onAdFailedToShow: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No reward available right now')),
    );
  },
);
```

### Reactive "Watch Ad" button

Use status listeners to show/hide the button based on ad availability:

```dart
class _RewardButtonState extends State<RewardButton> {
  @override
  void initState() {
    super.initState();
    AdFlow.instance.rewarded.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged() => setState(() {});

  @override
  void dispose() {
    AdFlow.instance.rewarded.removeStatusListener(_onStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = AdFlow.instance.rewarded.isLoaded;

    return ElevatedButton(
      onPressed: isReady ? _watchAd : null,
      child: Text(isReady ? 'Watch Ad for 50 Coins' : 'Loading...'),
    );
  }

  Future<void> _watchAd() async {
    await AdFlow.instance.rewarded.showAd(
      onUserEarnedReward: (reward) {
        // Grant reward
      },
    );
  }
}
```

> Rewarded ads automatically reload after being shown. By default, they remain available even when the user has purchased "Remove Ads" (configurable via `rewardedAdsIgnoreRemoveAds` in `AdFlowConfig`).

---

## Step 7: Show App Open Ads

App open ads appear when the user opens or returns to your app.

### Automatic (recommended)

Set these flags during initialization and ads will appear automatically:

```dart
await AdFlow.instance.initialize(
  config: AdFlowConfig.testMode(),
  preloadAppOpen: true,
  showAppOpenOnColdStart: true,       // Show on first app launch
  enableAppOpenOnForeground: true,    // Show when returning from background
  maxForegroundAdsPerSession: 2,      // Max 2 per session
);
```

That's it — no other code needed.

### Manual

```dart
// Load
await AdFlow.instance.appOpen.loadAd(
  onAdLoaded: (_) => debugPrint('App open ad ready'),
  onAdFailedToLoad: (error) => debugPrint('Failed: ${error.message}'),
);

// Show if available (checks load status + 4-hour expiry)
if (AdFlow.instance.appOpen.isAdAvailable) {
  await AdFlow.instance.appOpen.showAdIfAvailable(
    onAdDismissed: () => debugPrint('Resumed'),
    onAdFailedToShow: () => debugPrint('Ad failed to show'),
  );
}
```

### Pause/resume

Prevent app open ads from showing during sensitive flows (e.g., in-app purchase, onboarding):

```dart
// Pause (e.g., before opening a payment screen)
AdFlow.instance.pauseAppOpenAds();

// Resume
AdFlow.instance.resumeAppOpenAds();
```

> App open ads expire after 4 hours. If the cached ad is expired, it will be discarded and a new one loaded.

---

## Step 8: Show Native Ads

Native ads match your app's look and feel. They require platform-specific setup.

> See the full guide: [doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md)

### After platform setup

Use `EasyNativeAd` for a drop-in widget:

```dart
const EasyNativeAd(
  factoryId: 'medium_template', // Must match your registered factory ID
  height: 300,
)
```

With options:

```dart
EasyNativeAd(
  factoryId: 'medium_template',
  height: 300,
  hideOnLoading: true,  // Collapse while loading (no blank space)
  hideOnError: true,    // Collapse on error/no fill
  backgroundColor: Colors.white,
  borderRadius: BorderRadius.circular(12),
  padding: const EdgeInsets.all(8),
  onAdLoaded: () => debugPrint('Native ad loaded'),
  onAdFailedToLoad: () => debugPrint('Native ad failed'),
)
```

### With NativeAdManager

For more control:

```dart
final _nativeManager = NativeAdManager();

await _nativeManager.loadAd(
  factoryId: 'medium_template',
  onAdLoaded: (ad) => setState(() {}),
  onAdFailedToLoad: (error) => debugPrint('Failed: ${error.message}'),
);

// In build:
if (_nativeManager.isLoaded) {
  SizedBox(
    height: 300,
    child: AdWidget(ad: _nativeManager.nativeAd!),
  )
}

// Dispose when done
_nativeManager.dispose();
```

---

## Step 9: Remove Ads (In-App Purchase)

ad_flow has built-in "Remove Ads" support. When disabled, all ad widgets (`EasyBannerAd`, `EasyNativeAd`, etc.) automatically hide, and ad managers skip loading/showing.

### After a successful purchase

```dart
await AdFlow.instance.disableAds();
// All ads stop immediately! Widgets collapse to SizedBox.shrink().
```

### Restore on refund or re-enable

```dart
await AdFlow.instance.enableAds();
```

### Check current state

```dart
if (AdFlow.instance.isAdsEnabled) {
  // Show ads
}
```

### React to changes

```dart
// Listen to changes (e.g., to toggle UI)
AdsEnabledManager.instance.addListener(() {
  setState(() {});
});

// Or use the stream
StreamBuilder<bool>(
  stream: AdFlow.instance.adsEnabledStream,
  builder: (context, snapshot) {
    final adsEnabled = snapshot.data ?? true;
    return adsEnabled ? const EasyBannerAd() : const SizedBox.shrink();
  },
)
```

> The state is persisted in SharedPreferences and survives app restarts. Rewarded ads stay available by default (configurable via `rewardedAdsIgnoreRemoveAds`).

---

## Step 10: Privacy & Consent

ad_flow handles GDPR, US Privacy (CCPA), and iOS ATT automatically during initialization. You don't need to write any consent code — it's all built in.

### What happens automatically

| Region | What ad_flow does |
|--------|-------------------|
| EU/UK | Shows Google's UMP consent form |
| US (CCPA states) | Handles opt-out via UMP |
| iOS (all regions) | Shows ATT permission prompt |
| Other | Skips consent, proceeds to ads |

### Privacy settings button

GDPR requires that users can change their consent at any time. Add a privacy button to your settings screen:

```dart
// Simple button — only visible in GDPR regions
const EasyPrivacySettingsButton()

// Customized
EasyPrivacySettingsButton(
  text: 'Manage Privacy',
  icon: Icons.shield,
  onFormDismissed: () => debugPrint('User updated preferences'),
)

// ListTile for settings screens
const PrivacySettingsListTile(
  title: 'Privacy Settings',
  subtitle: 'Manage your ad preferences',
)

// Force visibility (even outside GDPR regions)
const PrivacySettingsListTile(alwaysShow: true)
```

### Manual privacy options

```dart
if (AdFlow.instance.isPrivacyOptionsRequired) {
  AdFlow.instance.showPrivacyOptions(
    onComplete: () => debugPrint('Privacy form dismissed'),
  );
}
```

### Pre-consent explainer

`initializeWithExplainer` shows a friendly dialog *before* the system prompts, explaining *why* the user is being asked:

```dart
AdFlow.instance.initializeWithExplainer(
  context: context,
  config: AdFlowConfig.testMode(),
);
```

Custom language:

```dart
AdFlow.instance.initializeWithExplainer(
  context: context,
  consentTexts: kPersianConsentExplainerTexts,
  attTexts: kPersianATTExplainerTexts,
);
```

Or by language code:

```dart
final (consentTexts, attTexts) = getExplainerTextsForLanguage('es'); // Spanish

AdFlow.instance.initializeWithExplainer(
  context: context,
  consentTexts: consentTexts,
  attTexts: attTexts,
);
```

Built-in languages: English (default), Persian, Spanish. You can also create fully custom texts:

```dart
const myTexts = ConsentExplainerTexts(
  title: 'Your Privacy Matters',
  description: 'We use ads to keep this app free.',
  benefitRelevantAds: 'Relevant ads',
  benefitDataSecure: 'Data stays secure',
  benefitKeepFree: 'Keeps the app free',
  settingsHint: 'Change anytime in Settings.',
  continueButton: 'Continue',
  skipButton: 'Decide later',
);
```

---

## Step 11: Error Handling

All ad errors flow through a centralized error stream. Subscribe to it for logging, analytics, or user-facing messages.

### Stream-based (recommended)

```dart
AdFlow.instance.errorStream.listen((error) {
  debugPrint('${error.type.name}: ${error.message} (code: ${error.code})');

  // Send to analytics
  analytics.logEvent('ad_error', {
    'type': error.type.name,
    'code': error.code,
    'message': error.message,
  });
});
```

### Callback-based (simpler)

```dart
AdFlow.instance.setErrorCallback((error) {
  crashlytics.recordError(error.originalError ?? error.message);
});

// Clear when done
AdFlow.instance.clearErrorCallback();
```

### Error types

| Type | Meaning |
|------|---------|
| `bannerLoad` | Banner ad failed to load |
| `interstitialLoad` | Interstitial failed to load |
| `interstitialShow` | Interstitial failed to show |
| `rewardedLoad` | Rewarded ad failed to load |
| `rewardedShow` | Rewarded ad failed to show |
| `appOpenLoad` | App open ad failed to load |
| `appOpenShow` | App open ad failed to show |
| `nativeLoad` | Native ad failed to load |
| `consent` | Consent gathering failed |
| `sdkInitialization` | SDK initialization failed |

---

## Step 12: Mediation

Mediation serves ads from multiple networks (Unity Ads, AppLovin, Meta, etc.) to maximize fill rate and revenue.

### Quick setup

```dart
import 'package:ad_flow/ad_flow.dart';
import 'package:gma_mediation_unity/gma_mediation_unity.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Register adapters BEFORE initializing AdFlow
  final unity = GmaMediationUnity();
  MediationHelper.registerUnityWithCallbacks(
    setGDPRConsent: unity.setGDPRConsent,
    setCCPAConsent: unity.setCCPAConsent,
  );

  // 2. Initialize — consent is auto-forwarded to registered networks
  await AdFlow.instance.initialize(
    config: AdFlowConfig(...),
  );

  runApp(const MyApp());
}
```

### Generic adapter

```dart
MediationHelper.registerAdapter(
  name: 'MyNetwork',
  forwarder: ({required gdprConsent, required ccpaOptOut}) async {
    MyNetworkSdk.setConsent(gdpr: gdprConsent, ccpa: ccpaOptOut);
  },
);
```

> Full mediation guide: [doc/MEDIATION_SETUP.md](doc/MEDIATION_SETUP.md)

---

## Step 13: Configuration Reference

### AdFlowConfig

All fields are optional. Only provide the ad unit IDs for the ad types you use.

```dart
AdFlowConfig(
  // Ad unit IDs (one pair per ad type, per platform)
  androidBannerAdUnitId: 'ca-app-pub-xxx/xxx',
  iosBannerAdUnitId: 'ca-app-pub-xxx/xxx',
  androidInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
  iosInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
  androidRewardedAdUnitId: 'ca-app-pub-xxx/xxx',
  iosRewardedAdUnitId: 'ca-app-pub-xxx/xxx',
  androidAppOpenAdUnitId: 'ca-app-pub-xxx/xxx',
  iosAppOpenAdUnitId: 'ca-app-pub-xxx/xxx',
  androidNativeAdUnitId: 'ca-app-pub-xxx/xxx',
  iosNativeAdUnitId: 'ca-app-pub-xxx/xxx',

  // Behavior
  minInterstitialInterval: Duration(seconds: 30),    // Cooldown between interstitials
  appOpenAdMaxCacheDuration: Duration(hours: 4),      // App open ad expiry
  maxLoadRetries: 3,                                   // Retry failed loads
  retryDelay: Duration(seconds: 5),                   // Delay between retries
  retryCooldownAfterMaxAttempts: Duration(minutes: 5), // Cooldown after all retries fail

  // Privacy
  skipGdprConsentIfAttDenied: true,   // iOS: skip GDPR if ATT denied
  rewardedAdsIgnoreRemoveAds: true,   // Rewarded available even after "Remove Ads"

  // Network
  httpTimeoutMillis: 30000,                        // Ad request timeout (30s)
  coldStartAdTimeout: Duration(seconds: 3),        // App open ad cold-start timeout

  // Testing
  testDeviceIds: ['YOUR_DEVICE_ID'],               // Avoid invalid impressions
  enableConsentDebug: false,                        // Test GDPR in non-EU regions
  maxAdContentRating: MaxAdContentRating.g,        // Content restriction
  tagForUnderAgeOfConsent: false,                   // COPPA
)
```

### Initialize parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `config` | `testMode()` | Ad unit IDs and settings |
| `onComplete` | `null` | Called when init finishes: `(bool canRequestAds) => ...` |
| `preloadInterstitial` | `false` | Preload an interstitial on init |
| `preloadRewarded` | `false` | Preload a rewarded ad on init |
| `preloadAppOpen` | `false` | Preload an app open ad on init |
| `showAppOpenOnColdStart` | `false` | Show app open ad on first launch |
| `enableAppOpenOnForeground` | `false` | Show app open ad when app returns from background |
| `maxForegroundAdsPerSession` | `1` | Max foreground app open ads per session |

### Manager API summary

Every ad manager shares this contract:

| Property / Method | Description |
|-------------------|-------------|
| `isLoaded` | Ad is ready to show |
| `isLoading` | Load in progress |
| `isShowing` | Fullscreen ad currently visible (interstitial/rewarded/app open) |
| `loadAd(...)` | Load an ad |
| `showAd(...)` | Show the ad (fullscreen types) |
| `dispose()` | Clean up resources |
| `addStatusListener(cb)` | Get notified when state changes |
| `removeStatusListener(cb)` | Remove listener |

### Callbacks per ad type

Every `loadAd()` and `showAd()` method accepts optional callbacks. Here's the complete reference:

**Banner** (`BannerAdManager`):

| Method | Callback | Type | When |
|--------|----------|------|------|
| `loadAdaptiveBanner()` | `onAdLoaded` | `void Function(BannerAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(BannerAd, LoadAdError)` | Load failed |
| `loadCollapsibleBanner()` | `onAdLoaded` | `void Function(BannerAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(BannerAd, LoadAdError)` | Load failed |

**Interstitial** (`InterstitialAdManager`):

| Method | Callback | Type | When |
|--------|----------|------|------|
| `loadAd()` | `onAdLoaded` | `void Function(InterstitialAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(LoadAdError)` | Load failed after retries |
| `showAd()` | `onAdDismissed` | `VoidCallback` | User closed the ad |
| | `onAdFailedToShow` | `VoidCallback` | Ad not ready or show error |
| | `ignoreCooldown` | `bool` | Bypass the 30s cooldown (default: `false`) |

**Rewarded** (`RewardedAdManager`):

| Method | Callback | Type | When |
|--------|----------|------|------|
| `loadAd()` | `onAdLoaded` | `void Function(RewardedAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(LoadAdError)` | Load failed after retries |
| `showAd()` | `onUserEarnedReward` | `void Function(RewardItem)` | **Required** — user completed the ad |
| | `onAdDismissed` | `VoidCallback` | User closed the ad |
| | `onAdFailedToShow` | `VoidCallback` | Ad not ready or show error |

**App Open** (`AppOpenAdManager`):

| Method | Callback | Type | When |
|--------|----------|------|------|
| `loadAd()` | `onAdLoaded` | `void Function(AppOpenAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(LoadAdError)` | Load failed after retries |
| `showAdIfAvailable()` | `onAdDismissed` | `VoidCallback` | User closed the ad |
| | `onAdFailedToShow` | `VoidCallback` | Ad expired, not loaded, or show error |

**Native** (`NativeAdManager`):

| Method | Callback | Type | When |
|--------|----------|------|------|
| `loadAd()` | `onAdLoaded` | `void Function(NativeAd)` | Ad loaded successfully |
| | `onAdFailedToLoad` | `void Function(LoadAdError)` | Load failed after retries |

**Self-contained widgets** (`EasyBannerAd`, `EasyNativeAd`):

| Widget | Callback | Type | When |
|--------|----------|------|------|
| `EasyNativeAd` | `onAdLoaded` | `VoidCallback` | Ad loaded and displayed |
| | `onAdFailedToLoad` | `VoidCallback` | Load failed |

> `EasyBannerAd` handles all callbacks internally — no user callbacks needed.

### Status listeners

All managers support reactive status listeners. Use them to rebuild UI when ad state changes (loaded, loading, showing, etc.):

```dart
// Works with ANY manager: interstitial, rewarded, appOpen, banner, native
AdFlow.instance.interstitial.addStatusListener(() {
  setState(() {}); // Rebuild when ad state changes
});

// Clean up in dispose()
AdFlow.instance.interstitial.removeStatusListener(_onStatusChanged);
```

Status listeners fire after **any** state change: load started, load completed, load failed, ad showing, ad dismissed. This makes them ideal for reactive UI like loading indicators, "Watch Ad" buttons, etc.

---

## Troubleshooting

### Ads not loading

1. Check internet connection.
2. Verify ad unit IDs are correct.
3. New ad units can take **24–48 hours** to start serving.
4. Check logs for common error codes:
   - `Error 0` — Internal error
   - `Error 1` — Invalid request (wrong ad unit ID)
   - `Error 2` — Network error
   - `Error 3` — No fill (no ads available)

### Consent form not showing

- The form only shows in **GDPR regions** (EU/UK/Switzerland).
- Use a VPN to test from a GDPR region, or set `enableConsentDebug: true` in `AdFlowConfig`.

### iOS build errors

1. Run `cd ios && pod install`.
2. Ensure minimum iOS version is **13.0+**.
3. Verify `Info.plist` has the `GADApplicationIdentifier` key.

### Android build errors

1. Ensure `minSdkVersion` is **21+**.
2. Verify `AndroidManifest.xml` has the AdMob App ID.
3. Run `flutter clean && flutter pub get`.

### Ad Inspector

Open the Ad Inspector for real-time debugging of ad requests and mediation:

```dart
AdFlow.instance.openAdInspector();
```

---

## Release Checklist

- [ ] Replace test IDs with production ad unit IDs in `AdFlowConfig`
- [ ] Remove or empty `testDeviceIds`
- [ ] Set `enableConsentDebug: false`
- [ ] Test on real devices (not emulator)
- [ ] Test consent flow from a GDPR region (use VPN)
- [ ] Verify iOS ATT dialog appears
- [ ] Test all ad formats load and display
- [ ] Add a privacy policy to your app/store listing

---

## License

MIT — see [LICENSE](LICENSE).
