# AdMob Mediation Setup Guide

This guide explains how to enable and configure **AdMob Mediation** with ad_flow to maximize your ad revenue by serving ads from multiple ad networks.

## What is Mediation?

AdMob Mediation allows you to serve ads from multiple ad networks (Unity Ads, AppLovin, Meta, etc.) through a single integration. AdMob automatically selects the highest-paying ad network for each impression, maximizing your revenue.

**Benefits:**
- 📈 Higher fill rates
- 💰 Increased eCPM through competition
- 🔄 Automatic waterfall/bidding optimization
- 🛠️ Single SDK integration point

## Supported Networks

ad_flow provides built-in support for:

| Network | Package | Consent Signals |
|---------|---------|-----------------|
| Unity Ads | `gma_mediation_unity` | GDPR, CCPA |
| AppLovin | `gma_mediation_applovin` | GDPR (hasUserConsent), CCPA (doNotSell) |

You can also register **custom adapters** for any other mediation network.

> **⚠️ Version Compatibility Note:**  
> ad_flow uses `google_mobile_ads ^7.0.0`. As of January 2026, the official mediation packages (`gma_mediation_unity`, `gma_mediation_applovin`) may still require `google_mobile_ads ^6.0.0`. Check pub.dev for updated versions that support ^7.0.0, or use a [dependency override](https://dart.dev/tools/pub/dependencies#dependency-overrides) if needed.

---

## Quick Start

### Step 1: Add Mediation Dependencies

Add the mediation packages you need to your `pubspec.yaml`:

```yaml
dependencies:
  ad_flow: ^1.3.14
  
  # Add only the networks you want to use:
  gma_mediation_unity: ^1.6.2      # Unity Ads
  gma_mediation_applovin: ^2.5.1   # AppLovin
```

Then run:
```bash
flutter pub get
```

### Step 2: Register Adapters Before Initialization

**⚠️ Critical:** Register mediation adapters **BEFORE** calling `AdFlow.instance.initialize()`.

```dart
import 'package:ad_flow/ad_flow.dart';
import 'package:gma_mediation_unity/gma_mediation_unity.dart';
import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Step 1: Create instances and register Unity Ads adapter
  final unity = GmaMediationUnity();
  MediationHelper.registerUnityWithCallbacks(
    setGDPRConsent: unity.setGDPRConsent,
    setCCPAConsent: unity.setCCPAConsent,
  );
  
  // Step 2: Create instance and register AppLovin adapter
  final applovin = GmaMediationApplovin();
  MediationHelper.registerApplovinWithCallbacks(
    setHasUserConsent: applovin.setHasUserConsent,
    setDoNotSell: applovin.setDoNotSell,
  );
  
  // Step 3: Initialize ad_flow (consent is auto-forwarded)
  await AdFlow.instance.initializeWithExplainer(
    config: AdFlowConfig(
      androidBannerAdUnitId: 'ca-app-pub-xxx/yyy',
      iosBannerAdUnitId: 'ca-app-pub-xxx/zzz',
      // ... other config
    ),
    context: navigatorKey.currentContext!,
  );
  
  runApp(MyApp());
}
```

### Step 3: That's It!

ad_flow automatically:
1. Gathers user consent (ATT on iOS, then UMP)
2. Forwards consent status to all registered mediation networks
3. Initializes the Google Mobile Ads SDK
4. Preloads ads as configured

---

## Detailed Configuration

### Using Only One Network

You don't need to use all networks. Just add the dependencies and register the adapters you need:

```dart
// Unity Ads only
import 'package:gma_mediation_unity/gma_mediation_unity.dart';

final unity = GmaMediationUnity();
MediationHelper.registerUnityWithCallbacks(
  setGDPRConsent: unity.setGDPRConsent,
  setCCPAConsent: unity.setCCPAConsent,
);
```

```dart
// AppLovin only
import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';

final applovin = GmaMediationApplovin();
MediationHelper.registerApplovinWithCallbacks(
  setHasUserConsent: applovin.setHasUserConsent,
  setDoNotSell: applovin.setDoNotSell,
);
```

### Custom Consent Configuration

By default, ad_flow reads consent status from `ConsentManager`. You can override this:

```dart
MediationHelper.forwardConsent(
  config: MediationConsentConfig(
    hasGdprConsent: true,  // Override GDPR consent
    hasCcpaConsent: false, // Override CCPA consent (user opted out)
  ),
);
```

### Registering Custom Adapters

For networks not built into ad_flow, use the generic `registerAdapter()` method:

```dart
MediationHelper.registerAdapter(
  networkName: 'meta_audience_network',
  forwarder: (config) async {
    // Forward consent to Meta Audience Network
    // Use their SDK's consent API here
    await MetaAudienceNetwork.setAdvertiserTrackingEnabled(config.hasGdprConsent);
    return true; // Return true on success
  },
);
```

### Checking Registration Status

```dart
// Check if any adapters are registered
if (MediationHelper.hasRegisteredAdapters) {
  print('Mediation is enabled');
}

// Get list of registered networks
List<String> networks = MediationHelper.registeredNetworks;
print('Registered: $networks'); // ['unity', 'applovin']
```

### Manual Consent Forwarding

Consent is automatically forwarded during initialization. To manually forward (e.g., after consent changes):

```dart
final summary = await MediationHelper.forwardConsent();

print('Forwarded to ${summary.successCount} networks');
print('Failed: ${summary.failureCount}');

for (final result in summary.results) {
  print('${result.networkName}: ${result.success ? "✓" : "✗"}');
  if (!result.success) {
    print('  Error: ${result.error}');
  }
}
```

---

## Platform-Specific Setup

### Android

Add the mediation adapter dependencies to `android/app/build.gradle.kts`:

```kotlin
dependencies {
    // Unity Ads
    implementation("com.google.ads.mediation:unity:4.12.4.0")
    
    // AppLovin
    implementation("com.google.ads.mediation:applovin:13.0.1.0")
}
```

### iOS

The Flutter packages handle CocoaPods integration automatically. Just run:

```bash
cd ios && pod install
```

---

## AdMob Console Configuration

After adding mediation packages, configure your ad units in the [AdMob Console](https://admob.google.com/):

1. Go to **Mediation** → **Mediation groups**
2. Create a new mediation group or edit existing
3. Add ad sources for your networks (Unity, AppLovin, etc.)
4. Configure eCPM floors and optimization settings
5. Link your network account credentials

Refer to Google's documentation for detailed console setup:
- [Unity Ads Mediation](https://developers.google.com/admob/flutter/mediation/unity)
- [AppLovin Mediation](https://developers.google.com/admob/flutter/mediation/applovin)

---

## Consent & Privacy

### How Consent Forwarding Works

1. **iOS ATT Prompt** → User grants/denies app tracking
2. **UMP Consent Form** → User provides GDPR/CCPA preferences
3. **ad_flow reads consent** → From `ConsentManager.canShowPersonalizedAds`
4. **Forwards to networks** → Each registered adapter receives consent status

### GDPR Consent Signal

- `true` → User consented to personalized ads
- `false` → User did NOT consent (serve non-personalized ads)

### CCPA Consent Signal

- `true` → User did NOT opt out of sale (can use data)
- `false` → User opted out (do not sell data)

**Note:** The CCPA signal is inverted from GDPR. ad_flow handles this automatically for built-in adapters.

---

## Troubleshooting

### Ads Not Filling from Mediation Networks

1. **Check registration order** – Adapters must be registered BEFORE `initialize()`
2. **Verify AdMob console** – Ensure mediation groups are configured correctly
3. **Check network credentials** – App IDs and ad unit IDs must match
4. **Test on real device** – Mediation may not work on emulators

### Consent Not Being Forwarded

```dart
// Debug: Check if adapters are registered
print('Has adapters: ${MediationHelper.hasRegisteredAdapters}');
print('Networks: ${MediationHelper.registeredNetworks}');

// Debug: Check consent status
print('Can show personalized: ${AdFlow.instance.consent.canShowPersonalizedAds}');
```

### Network-Specific Issues

**Unity Ads:**
- Ensure Game ID is set in AdMob console
- Test with Unity test ads first

**AppLovin:**
- Verify SDK key in AndroidManifest.xml / Info.plist
- Check AppLovin dashboard for integration status

---

## API Reference

### MediationHelper

| Method | Description |
|--------|-------------|
| `registerAdapter(networkName, forwarder)` | Register a custom mediation adapter |
| `registerUnityWithCallbacks(...)` | Register Unity Ads with consent callbacks |
| `registerApplovinWithCallbacks(...)` | Register AppLovin with consent callbacks |
| `forwardConsent([config])` | Forward consent to all registered adapters |
| `clearAdapters()` | Remove all registered adapters |
| `hasRegisteredAdapters` | Check if any adapters are registered |
| `registeredNetworks` | Get list of registered network names |

### MediationConsentConfig

| Property | Type | Description |
|----------|------|-------------|
| `hasGdprConsent` | `bool` | User consented to personalized ads (GDPR) |
| `hasCcpaConsent` | `bool` | User did NOT opt out of sale (CCPA) |

### MediationForwardSummary

| Property | Type | Description |
|----------|------|-------------|
| `results` | `List<MediationForwardResult>` | Results for each network |
| `successCount` | `int` | Number of successful forwards |
| `failureCount` | `int` | Number of failed forwards |
| `allSucceeded` | `bool` | True if all forwards succeeded |

---

## Example App

See the example app for a complete implementation:

```bash
cd example
flutter pub get
flutter run
```

The example demonstrates:
- Registering mediation adapters
- Initialization with consent flow
- Showing ads from mediated networks
