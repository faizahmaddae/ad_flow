# MIGRATION — ad_flow v1 → v2

For apps currently on `ad_flow` 1.3.x. This grows as the v2 API solidifies; sections marked _(finalize during build)_ are filled in as controllers land. Keep it accurate — a consumer should be able to migrate from this file alone.

## 1. Project / platform prerequisites (from `google_mobile_ads` 9.x)
- **pubspec:** `ad_flow: ^2.0.0` (pulls `google_mobile_ads: ^9.0.0`).
- **Flutter ≥ 3.38.1, Dart ≥ 3.10.0.**
- **iOS:** deployment target **13.0**; adopt the **`UISceneDelegate`** lifecycle if you have a custom `AppDelegate` (needed for app-open). Add to `Info.plist`: `GADApplicationIdentifier`, and `NSUserTrackingUsageDescription` (ATT).
- **Android:** `minSdk 24`, `compileSdk 36`, AGP compatible with **8.13.1**; keep the `com.google.android.gms.ads.APPLICATION_ID` meta-data in `AndroidManifest.xml`.
- **app-ads.txt:** ensure your published `app-ads.txt` is verified (required since Jan 2025 for full serving).

## 2. Initialization
**v1**
```dart
await AdFlow.instance.initialize(config: myConfig, /* preload…, enableAppOpenOnForeground: */);
```
**v2** — `initialize` builds and returns the instance (dependency-injected; no static global config):
```dart
final ads = await AdFlow.initialize(myConfig);      // consent-gated internally
// keep `ads` (or use the convenience accessor if you opt into it)
```
Consent is gathered and `canRequestAds`-gated automatically; you no longer sequence UMP yourself.

## 3. Configuration object
- v1's single flat `AdFlowConfig(androidBannerAdUnitId:, iosBannerAdUnitId:, …)` becomes **per-format config objects** with `PlatformAdUnitId(android:, ios:)`, plus per-format frequency caps and a global cap. _(finalize during build — provide a field-by-field table.)_
- **Test mode:** `AdFlowConfig.test()` (uses Google sample ids). Test-mode is now an explicit flag, not inferred from ids.

## 4. Ad access & showing _(finalize during build)_
| v1 | v2 |
|---|---|
| `AdFlow.instance.banner…` / `EasyBannerAd(...)` | `ads.banner(...)` controller + `AdFlowBanner(...)` widget |
| `AdFlow.instance.interstitial…` | `ads.interstitial` (`InterstitialAdController`) — `load()` / `show()` |
| `AdFlow.instance.rewarded…` | `ads.rewarded` — `show(onReward:)` |
| _(missing in v1)_ | `ads.rewardedInterstitial` — shows the intro/skip screen automatically |
| `AdFlow.instance.appOpen…` / `enableAppOpenOnForeground` | `ads.appOpen` (`AppOpenAdManager`, single owner) |
| native widget | `AdFlowNativeAd(...)` (template or factory) |
| `EasyPrivacySettingsButton` | `PrivacyOptionsButton` |
| `disableAds()/enableAds()` | same names on the facade |
| broad `google_mobile_ads` re-export | a **minimal** curated re-export (ADR-P3) — import `google_mobile_ads` directly if you need more |

State is now exposed as `ValueListenable<AdLoadState>` (use `ValueListenableBuilder`) instead of v1's manual listeners/streams.

## 5. Behavior changes to know
- **App-open** now shows on true foreground-return only (via `AppStateEventNotifier`), never on the first cold launch mid-load, and never while another full-screen ad is visible. If you relied on v1's `inactive`-triggered behavior, expect (correctly) fewer, better-timed app-open shows.
- **Frequency caps** are enforced per-format and globally; tune them in config.
- **Retries** use exponential backoff + jitter and auto re-arm after cooldown.
- **Rewarded interstitial** always shows an intro/skip screen first.

## 6. Next-Gen SDK (optional, experimental, Android-only)
No code change. To try it: build with `--dart-define=USE_NEXT_GEN_SDK=true` (Android only; iOS ignores it; legacy stays the default). See README.

## 7. Removed / renamed _(finalize during build)_
List each removed v1 symbol and its v2 replacement here as the API lands, so consumers get a mechanical checklist.
