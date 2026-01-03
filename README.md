# ad_flow - Professional AdMob Integration for Flutter

A production-ready, fully compliant AdMob integration package for Flutter with GDPR, US Privacy, and iOS ATT support.

[![pub package](https://img.shields.io/pub/v/ad_flow.svg)](https://pub.dev/packages/ad_flow)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-blue.svg)](https://flutter.dev)
[![google_mobile_ads](https://img.shields.io/badge/google__mobile__ads-7.0.0-green.svg)](https://pub.dev/packages/google_mobile_ads)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## ✨ Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Banner Ads** | ✅ | Adaptive banners that fit any screen |
| **Collapsible Banners** | ✅ | Expandable banners for higher engagement |
| **Interstitial Ads** | ✅ | Full-screen ads with smart cooldown |
| **Rewarded Ads** | ✅ | Video ads that reward users |
| **App Open Ads** | ✅ | Ads on app launch/resume |
| **GDPR Consent** | ✅ | EU/UK/Switzerland compliance |
| **US Privacy** | ✅ | CCPA and state regulations |
| **iOS ATT** | ✅ | App Tracking Transparency |
| **Native Ads** | ✅ | Custom ads matching your app design |
| **Remove Ads** | ✅ | Built-in IAP support to disable ads |
| **Auto Preloading** | ✅ | Ads ready when you need them |
| **Retry Logic** | ✅ | Exponential backoff on failures |
| **Lazy Loading** | ✅ | Managers created only when used |
| **Error Handling** | ✅ | Centralized error stream for all ads |

---

## 📦 Installation

### 1. Add Dependency

```yaml
# pubspec.yaml
dependencies:
  ad_flow: ^1.3.2
```

### 2. Android Setup

**android/app/src/main/AndroidManifest.xml:**
```xml
<manifest>
    <application>
        <!-- AdMob App ID -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
    </application>
</manifest>
```

### 3. iOS Setup

<details>
<summary>📱 ios/Runner/Info.plist (click to expand)</summary>

```xml
<!-- AdMob App ID -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>

<!-- App Tracking Transparency -->
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
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>4pfyvq9l8r.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>2fnua5tdw4.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>ydx93a7ass.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>5a6flpkh64.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>p78aez3dza.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>v72qych5uu.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>c6k4g5qg8m.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>s39g8k73mm.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>3qy4746246.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>3sh42y64q3.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>f38h382jlk.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>hs6bdukanm.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>prcb7njmu6.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>wzmmz9fp6w.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>yclnxrl5pm.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>7ug5zh24hu.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>9rd848q2bz.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>n6fk4nfna4.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>kbd757ywx3.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>9t245vhmpl.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>4468km3ulz.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>m8dbw4sv7c.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>zmvfpc5aq8.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>ejvt5qm6ak.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>5lm9lj6jb7.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>44jx6755aq.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>t38b2kh725.skadnetwork</string>
    </dict>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>24t9a8vw3c.skadnetwork</string>
    </dict>
</array>
```

</details>

---

## 🚀 Quick Start

### ⚠️ Important: Initialize Only ONCE

**AdFlow is a singleton** - you only need to initialize it **once** for your entire app, typically on your first screen (splash or home page). All other pages can simply use `AdFlow.instance` to show ads.

```
┌─────────────────────────────────────────────────────────────┐
│  YOUR APP                                                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   Page 1     │    │   Page 2     │    │   Page 3     │   │
│  │  (Splash)    │    │   (Home)     │    │  (Details)   │   │
│  │              │    │              │    │              │   │
│  │ initialize() │───▶│ showBanner() │───▶│ showBanner() │   │
│  │    ✅        │    │     ✅        │    │     ✅        │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│         │                    │                    │          │
│         └────────────────────┴────────────────────┘          │
│                              │                               │
│                    ┌─────────▼─────────┐                    │
│                    │    AdFlow      │                    │
│                    │    (Singleton)    │                    │
│                    │                   │                    │
│                    │  • BannerManager  │                    │
│                    │  • Interstitial   │                    │
│                    │  • AppOpenAd      │                    │
│                    │  • Consent        │                    │
│                    └───────────────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

| Action | Where | How Often |
|--------|-------|-----------|
| `initialize()` | First page only | **Once per app launch** |
| Show ads | Any page | As needed |

### Initialize in main.dart

```dart
import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AdMob with your ad unit IDs
  await AdFlow.instance.initialize(
    config: AdFlowConfig(
      // Your production ad unit IDs from AdMob console
      androidBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER_ID',
      iosBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER_ID',
      androidInterstitialAdUnitId: 'ca-app-pub-YOUR_ID/INTERSTITIAL_ID',
      iosInterstitialAdUnitId: 'ca-app-pub-YOUR_ID/INTERSTITIAL_ID',
      androidRewardedAdUnitId: 'ca-app-pub-YOUR_ID/REWARDED_ID',
      iosRewardedAdUnitId: 'ca-app-pub-YOUR_ID/REWARDED_ID',
      androidAppOpenAdUnitId: 'ca-app-pub-YOUR_ID/APP_OPEN_ID',
      iosAppOpenAdUnitId: 'ca-app-pub-YOUR_ID/APP_OPEN_ID',
      androidNativeAdUnitId: 'ca-app-pub-YOUR_ID/NATIVE_ID',
      iosNativeAdUnitId: 'ca-app-pub-YOUR_ID/NATIVE_ID',
    ),
    onComplete: (canRequestAds) {
      debugPrint('Ads ready: $canRequestAds');
    },
  );

  runApp(const MyApp());
}
```

### Initialization Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `config` | `AdFlowConfig?` | `testMode()` | Your ad unit IDs configuration |
| `onComplete` | `Function(bool)?` | `null` | Callback when initialization completes |
| `preloadInterstitial` | `bool` | `false` | Preload interstitial ad on init |
| `preloadRewarded` | `bool` | `false` | Preload rewarded ad on init |
| `preloadAppOpen` | `bool` | `false` | Preload app open ad on init |
| `showAppOpenOnColdStart` | `bool` | `false` | Show app open ad on first launch |
| `enableAppOpenOnForeground` | `bool` | `false` | Show app open ad when app returns from background |
| `maxForegroundAdsPerSession` | `int` | `1` | Max app open ads per session (foreground only) |

### Advanced Initialization

```dart
// Full control over initialization
await AdFlow.instance.initialize(
  config: AdFlowConfig(
    androidBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER_ID',
    iosBannerAdUnitId: 'ca-app-pub-YOUR_ID/BANNER_ID',
    // ... other ad unit IDs
  ),
  onComplete: (canRequestAds) {
    debugPrint('Ads ready: $canRequestAds');
  },
  preloadInterstitial: true,       // Preload interstitial for faster display
  preloadRewarded: true,           // Preload rewarded for faster display
  preloadAppOpen: true,            // Preload app open ad
  showAppOpenOnColdStart: true,    // Show ad on first app launch
  enableAppOpenOnForeground: true, // Show ad when returning to app
  maxForegroundAdsPerSession: 2,   // Allow 2 foreground app open ads
);
```

### Test Mode (Development)

```dart
// For development/testing, use test mode:
await AdFlow.instance.initialize(
  config: AdFlowConfig.testMode(), // Uses Google's test ad IDs
);
```

---

## 📱 Usage Examples

### Banner Ads (Easiest Way)

```dart
import 'package:ad_flow/ad_flow.dart';

// Just drop this widget anywhere!
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: YourContent(),
    
    // One line for a banner ad:
    bottomNavigationBar: const EasyBannerAd(),
  );
}
```

### Banner Ads (With More Control)

```dart
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final BannerAdManager _bannerManager = BannerAdManager();

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
      body: YourContent(),
      bottomNavigationBar: _bannerManager.isLoaded
          ? _bannerManager.buildAdWidget()
          : const SizedBox.shrink(),
    );
  }
}
```

### Collapsible Banner Ads

```dart
// Using EasyBannerAd widget
const EasyBannerAd(collapsible: true)

// Or with BannerAdManager
await _bannerManager.loadCollapsibleBanner(
  context: context,
  placement: CollapsibleBannerPlacement.bottom, // or .top
  onAdLoaded: (ad) => setState(() {}),
);
```

### Interstitial Ads

```dart
// Show interstitial (auto-preloaded on init)
await AdFlow.instance.interstitial.showAd(
  onAdDismissed: () {
    // Continue with your app
    Navigator.pushNamed(context, '/nextScreen');
  },
  onAdFailedToShow: () {
    // Ad not ready, proceed anyway
    Navigator.pushNamed(context, '/nextScreen');
  },
);

// Check if ready before showing
if (AdFlow.instance.interstitial.isLoaded) {
  AdFlow.instance.interstitial.showAd();
}
```

### Interstitial with Frequency Control

```dart
int _actionCount = 0;

void _onUserAction() {
  _actionCount++;
  
  // Show interstitial every 5 actions
  if (_actionCount % 5 == 0) {
    if (AdFlow.instance.interstitial.isLoaded) {
      AdFlow.instance.interstitial.showAd();
    }
  }
}
```

### Rewarded Ads

Rewarded ads let users watch video ads in exchange for in-app rewards (coins, extra lives, etc.):

```dart
// Load a rewarded ad (usually done at app start or before needed)
await AdFlow.instance.rewarded.loadAd(
  onAdLoaded: (ad) {
    print('Rewarded ad ready!');
  },
  onAdFailedToLoad: (error) {
    print('Failed to load rewarded ad: ${error.message}');
  },
);

// Show the rewarded ad when user clicks "Watch Ad" button
await AdFlow.instance.rewarded.showAd(
  onUserEarnedReward: (reward) {
    // Grant the reward to the user
    setState(() {
      _userCoins += reward.amount.toInt();
    });
    print('User earned ${reward.amount} ${reward.type}');
  },
  onAdDismissed: () {
    // Ad closed (whether reward earned or not)
    print('Rewarded ad dismissed');
  },
  onAdFailedToShow: () {
    // Ad not available
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No reward available. Try again later!')),
    );
  },
);
```

#### Preload Rewarded Ad on Init

```dart
// Add to your initialization for faster ad display
await AdFlow.instance.initialize(
  config: AdFlowConfig(...),
  preloadRewarded: true,  // Preload rewarded ad
);
```

#### Check Load Status & Listen for Changes

```dart
// Check if rewarded ad is ready
if (AdFlow.instance.rewarded.isLoaded) {
  // Show "Watch Ad" button
  ElevatedButton(
    onPressed: _watchAdForReward,
    child: const Text('Watch Ad for 50 Coins'),
  );
}

// Listen for ad load status changes (for reactive UI)
@override
void initState() {
  super.initState();
  AdFlow.instance.rewarded.addStatusListener(_onAdStatusChanged);
}

void _onAdStatusChanged() {
  setState(() {}); // Rebuild UI when ad loads/changes
}

@override
void dispose() {
  AdFlow.instance.rewarded.removeStatusListener(_onAdStatusChanged);
  super.dispose();
}
```

#### Manual Reload After Showing

```dart
// Rewarded ads auto-reload after being shown, but you can also manually reload:
if (!AdFlow.instance.rewarded.isLoaded && 
    !AdFlow.instance.rewarded.isLoading) {
  await AdFlow.instance.rewarded.loadAd();
}
```

### App Open Ads

App open ads are **automatically handled** when you set `enableAppOpenOnForeground: true` during initialization. They show when the user brings your app to the foreground.

```dart
// Manual control (if needed)
if (AdFlow.instance.appOpen.isAdAvailable) {
  await AdFlow.instance.appOpen.showAdIfAvailable(
    onAdDismissed: () {
      // App resumed
    },
  );
}
```

### Privacy Settings Button

```dart
// Check if user needs privacy options (GDPR regions)
if (AdFlow.instance.isPrivacyOptionsRequired) {
  IconButton(
    icon: const Icon(Icons.privacy_tip),
    onPressed: () {
      AdFlow.instance.showPrivacyOptions(
        onComplete: () {
          // User updated privacy settings
        },
      );
    },
  );
}
```

### Ad Inspector (Debug Mode)

```dart
// Open the Ad Inspector for debugging
AdFlow.instance.openAdInspector();
```

### Remove Ads (In-App Purchase)

Built-in support for "Remove Ads" purchases:

```dart
// After successful IAP purchase
await AdFlow.instance.disableAds();

// All ad widgets automatically hide!
// EasyBannerAd, EasyNativeAd, etc. respect this setting.
```

```dart
// Check if ads are enabled
if (AdFlow.instance.isAdsEnabled) {
  // Show ads
}

// Re-enable ads (e.g., restore purchase failed)
await AdFlow.instance.enableAds();
```

```dart
// Reactive UI with StreamBuilder
StreamBuilder<bool>(
  stream: AdFlow.instance.adsEnabledStream,
  builder: (context, snapshot) {
    final adsEnabled = snapshot.data ?? true;
    if (!adsEnabled) return const SizedBox.shrink();
    return const EasyBannerAd();
  },
)
```

### Error Handling

Centralized error handling for all ad operations:

```dart
// Stream-based (recommended for reactive apps)
AdFlow.instance.errorStream.listen((error) {
  print('Ad error: ${error.type} - ${error.message}');
  
  // Log to analytics
  analytics.logEvent('ad_error', {
    'type': error.type.name,      // bannerLoad, interstitialLoad, etc.
    'code': error.code,           // Error code from SDK
    'message': error.message,     // Human-readable message
    'adUnitId': error.adUnitId,   // Which ad unit failed
  });
});

// Callback-based (simpler alternative)
AdFlow.instance.setErrorCallback((error) {
  crashlytics.recordError(error.originalError ?? error.message);
});

// Clear callback when done
AdFlow.instance.clearErrorCallback();
```

**Error Types:**
| Type | Description |
|------|-------------|
| `consent` | Consent gathering failed |
| `bannerLoad` | Banner ad failed to load |
| `interstitialLoad` | Interstitial failed to load |
| `interstitialShow` | Interstitial failed to show |
| `appOpenLoad` | App open ad failed to load |
| `appOpenShow` | App open ad failed to show |
| `rewardedLoad` | Rewarded ad failed to load |
| `rewardedShow` | Rewarded ad failed to show |
| `nativeLoad` | Native ad failed to load |
| `sdkInitialization` | SDK initialization failed |

### Native Ads Setup

Native ads require platform-specific factory code. See the full guide:

📖 **[Native Ads Setup Guide](doc/NATIVE_ADS_SETUP.md)**

Quick overview:
1. Create native ad factories (Kotlin for Android, Swift for iOS)
2. Register factories in `MainActivity.kt` / `AppDelegate.swift`
3. Create layout XML (Android) or XIB files (iOS)
4. Use in Flutter with `factoryId`

```dart
// Load native ad
await AdFlow.instance.native.loadAd(
  factoryId: 'medium_template',  // Must match registered factory
  onAdLoaded: (ad) => setState(() {}),
);

// Display
if (AdFlow.instance.native.isLoaded) {
  SizedBox(
    height: 300,
    child: AdWidget(ad: AdFlow.instance.native.nativeAd!),
  )
}
```

### Privacy Settings Button (GDPR Requirement)

GDPR requires providing users a way to modify their consent. Use these widgets in your settings screen:

```dart
// Simple button - auto shows/hides based on GDPR requirement
EasyPrivacySettingsButton()

// With custom text
EasyPrivacySettingsButton(
  text: 'Manage Privacy',
  icon: Icons.shield,
)

// For settings screens - ListTile version
PrivacySettingsListTile(
  title: 'Privacy Settings',
  subtitle: 'Manage your ad preferences',
)

// Always visible (ignores GDPR check)
PrivacySettingsListTile(
  alwaysShow: true,
)

// Fully custom widget
EasyPrivacySettingsButton(
  child: YourCustomWidget(),
  onFormDismissed: () {
    print('User updated privacy settings');
  },
)
```

---

## 📂 Package Structure

```
lib/
├── ad_flow.dart                    # Barrel export (import this)
└── src/
    ├── ad_config.dart              # Configuration & ad unit IDs
    ├── ad_error_handler.dart       # Centralized error handling
    ├── ad_service.dart             # Main AdFlow service (singleton)
    ├── ads_enabled_manager.dart    # Remove Ads feature
    ├── consent_manager.dart        # GDPR/ATT consent handling
    ├── consent_explainer_dialog.dart   # Pre-consent explainer dialogs
    ├── consent_explainer_localizations.dart # Multi-language support
    ├── banner_ad_manager.dart      # Banner ad management
    ├── easy_banner_widget.dart     # Drop-in banner widget
    ├── easy_privacy_settings_button.dart # GDPR privacy settings button
    ├── interstitial_ad_manager.dart    # Interstitial ad management
    ├── rewarded_ad_manager.dart    # Rewarded ad management
    ├── app_open_ad_manager.dart    # App open ad management
    ├── app_lifecycle_reactor.dart  # App state monitoring
    ├── native_ad_manager.dart      # Native ad management
    └── native_ad_widget.dart       # Drop-in native ad widgets
```

---

## ⚙️ Configuration

### Behavior Settings

Customize ad behavior via `AdFlowConfig`:

```dart
await AdFlow.instance.initialize(
  config: AdFlowConfig(
    // Your ad unit IDs...
    androidBannerAdUnitId: 'ca-app-pub-xxx/xxx',
    iosBannerAdUnitId: 'ca-app-pub-xxx/xxx',
    
    // Behavior settings
    appOpenAdMaxCacheDuration: Duration(hours: 4), // Google recommends max 4 hours
    minInterstitialInterval: Duration(seconds: 30), // Cooldown between interstitials
    maxLoadRetries: 3,                              // Retry failed loads
    retryDelay: Duration(seconds: 5),               // Delay between retries
    
    // Testing & debug
    testDeviceIds: ['YOUR_DEVICE_HASHED_ID'],       // Avoid invalid impressions
    enableConsentDebug: false,                       // Test GDPR in non-EU regions
  ),
);
```

### Test Device IDs

Add your test device ID to avoid invalid impressions during development:

```dart
config: AdFlowConfig(
  // ... ad unit IDs
  testDeviceIds: ['YOUR_DEVICE_HASHED_ID'],
),
```

Find your device ID in the console logs:
```
I/Ads: Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("YOUR_DEVICE_ID"))
```

---

## 🔒 Privacy & Compliance

### GDPR (Europe)
- ✅ Automatically shows consent form for EU/UK/Switzerland users
- ✅ Uses Google's certified UMP SDK
- ✅ Stores consent for future sessions
- ✅ Respects user's privacy choices

### US Privacy (CCPA)
- ✅ Supports US state privacy regulations
- ✅ Handles opt-out requests

### iOS ATT (App Tracking Transparency)
- ✅ Integrated with consent flow
- ✅ Shows system permission dialog
- ✅ Respects user's tracking choice

### How It Works

```
App Start
    │
    ▼
┌─────────────────────┐
│ Check Consent Status │
└─────────────────────┘
    │
    ▼ (if GDPR region)
┌─────────────────────┐
│ Show Consent Form   │
└─────────────────────┘
    │
    ▼ (if iOS)
┌─────────────────────┐
│ ATT Permission      │
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Initialize Ads SDK  │
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ Preload Ads         │
└─────────────────────┘
```

### Pre-Consent Explainer (Better UX)

For a friendlier user experience, you can show an explainer dialog **before** the official consent popups appear. This gives users context about why they're being asked for consent.

```dart
// Option 1: Initialize with explainer (recommended for better UX)
class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    // Show explainer after first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdFlow.instance.initializeWithExplainer(
        context: context,
        onComplete: (canRequestAds) {
          debugPrint('Ads ready: $canRequestAds');
        },
      );
    });
  }
}

// Option 2: Standard initialization (consent popups appear immediately)
await AdFlow.instance.initialize(
  onComplete: (canRequestAds) {
    // Ready
  },
);
```

The explainer shows:
- 🎯 **General privacy explainer** - "Your Privacy Matters" with benefits
- 📱 **iOS ATT explainer** - Brief explanation before the system ATT popup

You can also show the dialogs manually:

```dart
// Show the general consent explainer
await ConsentExplainerDialog.show(context);

// Show the iOS ATT explainer (iOS only)
await ATTExplainerDialog.show(context);
```

### Multi-Language Support

Built-in localized texts for consent explainers:

| Language | Consent Texts | ATT Texts |
|----------|---------------|-----------|
| English (default) | `kDefaultConsentExplainerTexts` | `kDefaultATTExplainerTexts` |
| Persian (فارسی) | `kPersianConsentExplainerTexts` | `kPersianATTExplainerTexts` |
| Spanish (Español) | `kSpanishConsentExplainerTexts` | `kSpanishATTExplainerTexts` |

```dart
// Use pre-defined language texts
AdFlow.instance.initializeWithExplainer(
  context: context,
  consentTexts: kPersianConsentExplainerTexts,
  attTexts: kPersianATTExplainerTexts,
  onComplete: (canRequestAds) {
    debugPrint('Ads ready: $canRequestAds');
  },
);
```

```dart
// Or get texts by language code
final (consentTexts, attTexts) = getExplainerTextsForLanguage('es');

AdFlow.instance.initializeWithExplainer(
  context: context,
  consentTexts: consentTexts,
  attTexts: attTexts,
);
```

```dart
// Create custom texts for any language
const myCustomTexts = ConsentExplainerTexts(
  title: 'Your Title',
  description: 'Your description...',
  benefitRelevantAds: 'Relevant ads',
  benefitDataSecure: 'Data stays secure',
  benefitKeepFree: 'Keeps app free',
  settingsHint: 'Change anytime in Settings.',
  continueButton: 'Continue',
  skipButton: 'Decide later',
);
```

---

## 💰 Revenue Optimization Tips

### 1. Ad Placement Best Practices

| Do ✅ | Don't ❌ |
|-------|---------|
| Place banners at natural content breaks | Cover content with ads |
| Show interstitials at natural pauses | Show interstitials during gameplay |
| Use app open ads on cold start | Show too many app open ads |
| Test different placements | Ignore user experience |

### 2. Interstitial Frequency

```dart
// Default cooldown is 30 seconds (configurable via AdFlowConfig)
// Recommended: Show at natural breaks, not too frequently
minInterstitialInterval: Duration(seconds: 30),
```

### 3. Banner Refresh

Banners automatically refresh every 60 seconds (AdMob default). Don't manually refresh more frequently.

### 4. Fill Rate Optimization

- ✅ Use adaptive banners (auto-sizes)
- ✅ Keep HTTP timeout at 30 seconds
- ✅ Implement retry logic (included)
- ✅ Test on real devices

### 5. eCPM Optimization

- ✅ Enable all ad formats
- ✅ Use mediation (optional, advanced)
- ✅ Target appropriate content rating
- ✅ Maintain high user engagement

---

## 🔍 API Reference

### AdFlow

```dart
// Singleton instance
AdFlow.instance

// Properties
bool isInitialized              // SDK initialized?
bool isMobileAdsInitialized     // Mobile Ads ready?
bool isPrivacyOptionsRequired   // Show privacy button?
bool isAdsEnabled               // Ads enabled? (Remove Ads)
bool isAdsDisabled              // Ads disabled?

// Managers
ConsentManager consent          // Consent handling
BannerAdManager banner          // Banner ads
InterstitialAdManager interstitial  // Interstitial ads
RewardedAdManager rewarded      // Rewarded ads
AppOpenAdManager appOpen        // App open ads
NativeAdManager native          // Native ads

// Methods
Future<void> initialize({...})  // Initialize everything
Future<void> disableAds()       // Disable ads (Remove Ads)
Future<void> enableAds()        // Re-enable ads
void showPrivacyOptions({...})  // Show privacy form
void openAdInspector()          // Debug tool

// Streams
Stream<bool> adsEnabledStream   // Reactive ads enabled state
```

### BannerAdManager

```dart
// Properties
bool isLoaded                   // Banner ready?
bool isLoading                  // Loading in progress?
BannerAd? bannerAd             // The ad object

// Methods
Future<void> loadAdaptiveBanner({...})    // Load adaptive banner
Future<void> loadCollapsibleBanner({...}) // Load collapsible banner
Widget? buildAdWidget()                    // Get AdWidget
void dispose()                             // Clean up
```

### InterstitialAdManager

```dart
// Properties
bool isLoaded                   // Ad ready?
bool isLoading                  // Loading in progress?
bool isShowing                  // Currently displayed?
bool canShowAd                  // Cooldown passed?

// Methods
Future<void> loadAd({...})     // Load interstitial
Future<bool> showAd({...})     // Show interstitial
void dispose()                  // Clean up
```

### AppOpenAdManager

```dart
// Properties
bool isLoaded                   // Ad loaded?
bool isAdAvailable             // Ready & not expired?

// Methods
Future<void> loadAd({...})           // Load app open ad
Future<void> showAdIfAvailable({...}) // Show if available
void dispose()                        // Clean up
```

### RewardedAdManager

```dart
// Properties
bool isLoaded                   // Ad ready?
bool isLoading                  // Loading in progress?
bool isShowing                  // Currently displayed?

// Methods
Future<void> loadAd({...})     // Load rewarded ad
Future<bool> showAd({...})     // Show rewarded ad
void addStatusListener(cb)     // Listen for load status
void removeStatusListener(cb)  // Remove listener
void dispose()                  // Clean up
```

### EasyBannerAd Widget

```dart
const EasyBannerAd({
  bool collapsible = false,  // Use collapsible format?
})
```

### NativeAdManager

```dart
// Properties
bool isLoaded                   // Ad loaded?
bool isLoading                  // Loading in progress?
NativeAd? nativeAd             // The ad object

// Methods
Future<void> loadAd({...})     // Load native ad
void dispose()                  // Clean up
```

### EasyNativeAd Widget

```dart
const EasyNativeAd({
  required String factoryId,   // Native ad factory ID
  required double height,      // Ad height
  double? width,               // Ad width (optional)
  Widget? loadingWidget,       // Loading placeholder
  Widget? errorWidget,         // Error placeholder
  bool hideOnLoading = true,   // Collapse while loading
  bool hideOnError = true,     // Collapse on error/no fill
  EdgeInsets padding,          // Padding around ad
  Color? backgroundColor,      // Background color
  BorderRadius? borderRadius,  // Corner radius
  VoidCallback? onAdLoaded,    // Callback when ad loads
  VoidCallback? onAdFailedToLoad, // Callback on load failure
})
```

**Collapse Behavior (v1.3.6+):** By default, `EasyNativeAd` collapses to zero height when loading or when an ad fails to load (e.g., no fill). This prevents empty white space in fixed-height layouts like `bottomNavigationBar`. Set `hideOnLoading: false` or `hideOnError: false` to show placeholder widgets instead.

**Example with callbacks:**
```dart
EasyNativeAd(
  factoryId: 'medium_template',
  height: 300,
  onAdLoaded: () => debugPrint('Native ad loaded!'),
  onAdFailedToLoad: () => debugPrint('Native ad failed to load'),
)
```

### AdsEnabledManager

```dart
// Singleton instance
AdsEnabledManager.instance

// Properties
bool isEnabled                 // Ads enabled?
bool isDisabled                // Ads disabled?

// Methods
Future<void> disableAds()      // Disable all ads
Future<void> enableAds()       // Re-enable ads
void addListener(callback)     // Listen for changes
void removeListener(callback)  // Remove listener

// Stream
Stream<bool> stream            // Reactive state changes
```

---

## 🐛 Troubleshooting

### Ads Not Loading

1. **Check internet connection**
2. **Verify ad unit IDs** are correct
3. **Wait 24-48 hours** after creating new ad units
4. **Check logs** for error codes:
   - Error 0: Internal error
   - Error 1: Invalid request
   - Error 2: Network error
   - Error 3: No fill

### Consent Form Not Showing

1. Form only shows in **GDPR regions** (EU/UK/Switzerland)
2. Use **VPN** to test from GDPR region
3. Add test device ID for consent debugging

### iOS Build Errors

1. Run `pod install` in ios folder
2. Update minimum iOS version to 13.0+
3. Ensure Info.plist has all required keys

### Android Build Errors

1. Check `minSdkVersion` is 21+
2. Ensure AndroidManifest.xml has App ID
3. Run `flutter clean && flutter pub get`

---

## 📋 Checklist Before Release

- [ ] Use `AdFlowConfig` with your production ad unit IDs
- [ ] Remove `testDeviceIds` or leave empty
- [ ] Set `enableConsentDebug: false`
- [ ] Test on real devices
- [ ] Test consent flow in GDPR region (use VPN)
- [ ] Verify iOS ATT dialog appears
- [ ] Test all ad formats load and display
- [ ] Check ads don't block UI elements
- [ ] Review AdMob policies compliance
- [ ] Add privacy policy to app/store listing

---

## 📜 License

MIT License - Feel free to use in any project.

---

## 🙏 Credits

Built with:
- [google_mobile_ads](https://pub.dev/packages/google_mobile_ads) - Official Google Mobile Ads SDK
- [Flutter](https://flutter.dev) - Google's UI toolkit

---

## 📞 Support

For issues or questions:
1. Check [AdMob Help Center](https://support.google.com/admob)
2. Review [google_mobile_ads documentation](https://pub.dev/packages/google_mobile_ads)
3. See [Flutter AdMob samples](https://github.com/googleads/googleads-mobile-flutter)

---

**Happy Monetizing! 💰**
