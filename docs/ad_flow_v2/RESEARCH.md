# RESEARCH — ground truth for ad_flow v2

Verified against primary sources on **2026-07-11** (pub.dev, googleads-mobile-flutter GitHub, developers.google.com/admob, support.google.com/admob). Treat this as the knowledge base. Do NOT re-research what is here — spot-check only if something looks stale, and if you learn something new, append it here so the next worker inherits it.

---

## 1. Versions & requirements

- **Latest upstream: `google_mobile_ads: 9.0.0`** (published 2026-06-09, Apache-2.0).
- **v9 minimum requirements:** Flutter **≥ 3.38.1**, Dart **≥ 3.10.0**, iOS deployment target **13.0**, Android **minSdk 24 / compileSdk 36**, Android Gradle Plugin **8.13.1**.
- Native SDKs bundled by v9: Android `play-services-ads` **25.3.0** (+ experimental Next-Gen `ads-mobile-sdk` **1.1.0** behind a build flag); iOS `Google-Mobile-Ads-SDK` **~13.3.0**; UMP Android **4.0.0** / iOS **3.1.0**.
- Platforms: **Android + iOS only.**
- The old `ad_flow` v1.3.18 pinned `google_mobile_ads: ^7.0.0` → two majors behind; it version-conflicts with any app on 8.x/9.x.

## 2. Migration deltas 7.x → 9.x (what actually changed)

The **core ad flow is stable** across 7→9: `load()` + `…LoadCallback` (`onAdLoaded` / `onAdFailedToLoad(LoadAdError)`), `fullScreenContentCallback` (`FullScreenContentCallback`), `show()`, `dispose()` are all unchanged. Concretely:

- **v8:** min Flutter → 3.38.1, Dart → 3.10.0. **iOS migrated to the `UISceneDelegate` protocol** — a custom `AppDelegate` (needed for app-open/scene lifecycle) must adopt the scene-based lifecycle. Swift Package Manager support added (CocoaPods still fine). **Adaptive-banner API deprecations:**
  - `AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width)` → **`AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)`**
  - `AdSize.getAnchoredAdaptiveBannerAdSize(orientation, width)` → **`AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(orientation, width)`**
  - New **`BannerAd.isCollapsible`** property.
- **v9:** native SDK bumps + Next-Gen experimental flag (see §4). Android fix to pending start/stop futures in `AppStateNotifier`.
- **The only Dart-level breakage is the adaptive-banner rename** (deprecated, not yet removed). Everything else is project-side (min versions, iOS scene lifecycle).

## 3. Current v9 API patterns per format

- **Banner:** `BannerAd(adUnitId, size, request: AdRequest(), listener: BannerAdListener(onAdLoaded, onAdFailedToLoad: (ad, LoadAdError e), onAdOpened, onAdClosed, onAdImpression, onAdClicked)).load();` render via `AdWidget(ad: bannerAd)` inside a `SizedBox`/`ConstrainedBox` sized to `bannerAd.size`; `dispose()` on removal.
- **Adaptive banner (anchored, current):** `final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(MediaQuery.sizeOf(context).width.truncate());` (may be null). Orientation variant: `getLargeAnchoredAdaptiveBannerAdSizeWithOrientation`. **Inline adaptive** via `AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(...)` / `InlineAdaptiveSize`. **Anchored adaptive height bounds** (web-verified, added while fixing review finding #8 — not in the plugin's Dart source since the exact value is computed natively): minimum 50dp; maximum is `min(90dp, 15% of device height)`. There is **no pure-width formula** — the exact height also depends on device/screen aspect ratio, so a client-side placeholder can only ever be an estimate within these documented bounds, never exact, without an actual `getLargeAnchoredAdaptiveBannerAdSize` round trip.
- **Collapsible banner:** request an (adaptive-sized) banner with `AdRequest(extras: {'collapsible': 'top' /* or 'bottom' */})`; after load check `(_ad as BannerAd).isCollapsible`. Google-demand only (no mediation fill); auto-refresh will NOT re-request a collapsible ad — reload manually.
- **Interstitial:** `InterstitialAd.load(adUnitId, request, InterstitialAdLoadCallback(onAdLoaded:, onAdFailedToLoad:))`; in `onAdLoaded` set `ad.fullScreenContentCallback = FullScreenContentCallback(onAdShowedFullScreenContent:, onAdDismissedFullScreenContent:, onAdFailedToShowFullScreenContent:, onAdImpression:, onAdClicked:)` then `ad.show()`. **Single-use**; `dispose()` in dismiss/fail.
- **Rewarded:** `RewardedAd.load(...)` with `RewardedAdLoadCallback`; set `fullScreenContentCallback`; `ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) { /* grant reward.amount of reward.type */ })`. High-value rewards → **server-side verification** via `ServerSideVerificationOptions`. Single-use.
- **Rewarded interstitial:** identical to rewarded but `RewardedInterstitialAd.load(...)` + `RewardedInterstitialAdLoadCallback`, `show(onUserEarnedReward:)`. **Policy requires an intro/announcement screen with clear reward messaging and a skip option BEFORE it plays** (no tap-to-watch opt-in like standard rewarded).
- **Native:** `NativeAd(adUnitId, request, listener: NativeAdListener(onAdLoaded, onAdFailedToLoad, onAdImpression, onAdClicked, onPaidEvent, ...), ...)` rendered via `AdWidget`. Two styles: **(a) Native templates (Dart-only, preferred)** via `nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small | TemplateType.medium, mainBackgroundColor:, cornerRadius:, primaryTextStyle:/secondaryTextStyle:/tertiaryTextStyle:/callToActionTextStyle: NativeTemplateTextStyle(...))` (small ≈ min 320×90, medium ≈ min 320×320); **(b) Platform views** via a native-registered `NativeAdFactory` + `factoryId:`.
- **App open:** `AppOpenAd.load(adUnitId, request, AppOpenAdLoadCallback(onAdLoaded:, onAdFailedToLoad:))`; set `fullScreenContentCallback`; `show()`. **A loaded ad expires after 4 hours** — store load time, discard/reload if stale. Foreground detection via **`AppStateEventNotifier.appStateStream`** (the official, correct signal). Single-use; dispose + preload next on dismiss.
- **Init:** `await MobileAds.instance.initialize()` → `Future<InitializationStatus>` (completes on init or a 30s timeout; `adapterStatuses` reports mediation readiness). Configure via `MobileAds.instance.updateRequestConfiguration(RequestConfiguration(testDeviceIds:, tagForChildDirectedTreatment:, tagForUnderAgeOfConsent:, maxAdContentRating:))`.
- **Impression-level revenue:** every ad listener exposes **`onPaidEvent`** (`OnPaidEventCallback` → `PaidEvent` with value/currency/precision). Wire this for revenue analytics.
- **Preloading:** **the Flutter plugin has NO preload API even in 9.0.0** (no `PreloadConfiguration`/`PreloadCallback`/preload manager). "Preloading" = manual: `load()` ahead, cache the instance, `show()` later, and **reload the next in `onAdDismissedFullScreenContent`/`onAdFailedToLoad`.**

## 4. Next-Gen SDK — the facts (Flutter)

- Next-Gen GMA SDK is **GA on native Android (2026-07-06)**, **does not exist for iOS yet**, and is **NOT GA in Flutter**. Full Flutter support is "targeting summer 2026 (subject to change)" (tracking issue #1404).
- Flutter today: an **experimental, Android-only, build-time opt-in** in plugin **v9.0.0**. The plugin's Android `build.gradle` reads a Dart define `USE_NEXT_GEN_SDK`; when true it swaps the native dependency (`ads-mobile-sdk` instead of `play-services-ads`). Enable with `--dart-define=USE_NEXT_GEN_SDK=true`.
- **The Dart API is identical either way** — same `MobileAds`, `BannerAd`, `InterstitialAd`, imports, callbacks. The flag swaps only the native Android implementation; iOS ignores it. Supporting Next-Gen from a Flutter *wrapper* is therefore mostly: target v9, don't depend on legacy-only native internals, document the flag, provide an example build variant.
- Android beta gains Google published: up to **27% faster** banner latency, **17% smaller** size, **+50% ARPU**, **+91.5% ARPDAU**, **+16% fill**, **+36.7% eCPM**, ~⅓ fewer ANRs. (No Flutter-specific numbers yet.)
- Risks: not GA, Android-only, **no Android TV** under Next-Gen, early-maturity bugs, mediation adapters must be Next-Gen-compatible. **Legacy vs Next-Gen is all-or-nothing per build** (chosen by the flag); the same plugin version supports both. **Avoid the third-party `admob_nextgen` pub package** — unofficial.

## 5. UMP / consent — correct 2026 flow

- API (all in `package:google_mobile_ads/google_mobile_ads.dart`): `ConsentInformation.instance.requestConsentInfoUpdate(ConsentRequestParameters, onSuccess, onError)` (call **every launch**); `canRequestAds()` (the gate); `getConsentStatus()`; `getPrivacyOptionsRequirementStatus()`; `isConsentFormAvailable()`; `reset()` (**testing only**). Forms: `ConsentForm.loadAndShowConsentFormIfRequired(onDismiss)` (modern one-shot) and `ConsentForm.showPrivacyOptionsForm(onDismiss)` (manage-consent entry point). Params: `ConsentRequestParameters(tagForUnderAgeOfConsent:, consentDebugSettings:)`, `ConsentDebugSettings(debugGeography:, testIdentifiers:)`.
- **Rule: consent first, then load ads only when `canRequestAds()` is true.** `MobileAds.initialize()` may run in parallel (init sends no ad request), but **no `load()` before the gate is true.** `canRequestAds()` is false until `requestConsentInfoUpdate` runs once; true when status is `obtained` OR `notRequired` (non-EEA). **Guard double-loading with a boolean** (update callback and form-dismiss callback can both report the gate open).
- **Privacy options:** if `getPrivacyOptionsRequirementStatus() == required`, expose a persistent "Manage consent / Privacy settings" control calling `ConsentForm.showPrivacyOptionsForm(...)`. (GDPR: EEA + UK + Switzerland.)
- **ATT (iOS):** add `NSUserTrackingUsageDescription` to `Info.plist`; link AppTrackingTransparency. UMP can present the ATT explainer then the system prompt (configure the IDFA message in the AdMob console); the system prompt fires once per install when status is `notDetermined`. Ads still serve if denied (no IDFA). Don't double-prompt if the app also uses `app_tracking_transparency`.
- **Testing:** `ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea, testIdentifiers: ['HASHED-ID'])`; hashed ID printed to console on first run; `reset()` to re-show the form (remove before release); emulators/simulators auto-treated as test devices, but ATT re-prompts only after uninstall/reinstall.

## 6. AdMob policy + revenue rules to bake into defaults

- **app-ads.txt is required (since Jan 2025).** Newly configured apps must verify an `app-ads.txt` file or they cannot fully serve ads. Call this out prominently in the README.
- **App-open:** never on the first cold launch while still loading (show only from a dedicated splash/loading gate, else proceed without it); warm start / foreground return only; respect the **4h expiry**; frequency-cap; never layer over content that also shows a banner; never in "Designed for Families" apps.
- **Interstitial:** only at **natural transitions/breaks**; **≤ 1 per 2 user actions**; never on app launch or exit; never immediately after another ad closes; never interrupt an active task. Preload so it doesn't pop in late.
- **Rewarded interstitial:** mandatory **intro screen + skip** before showing.
- **Banner:** prefer **adaptive (anchored `Large…`)** over fixed 320×50; keep an ad on screen **≥ 60s** before refresh; reserve fixed space to avoid layout shift → accidental clicks; keep a buffer from buttons/nav.
- **Invalid traffic / accidental clicks:** never click your own live ads (use test ads); no encouraging clicks; ads flush against buttons or that shift content trigger "Layout Encourages Accidental Clicks" enforcement; publisher liable even for third-party invalid traffic. Consequences: serving limits → suspension.
- **Mediation & bidding:** raises fill + eCPM; adapters added in native `build.gradle`/`Podfile`; register partners in Privacy & messaging for consent; iOS mediation needs partner `SKAdNetworkItems` in `Info.plist` (Google's own SKAdNetwork IDs are bundled automatically).
- **Test ads:** required during development — Google sample IDs or a registered test device (renders a "Test Ad" label). Replace with production IDs before release.

## 7. Analysis of the old v1 package (what to keep / what to fix)

**Keep (good ideas):** the ergonomic facade + drop-in widgets; the thin testable SDK seam (`ad_sdk.dart`); the strong test culture (~1000 tests); the Remove-Ads/`disableAds` concept; cancellable-`Timer` retries; typed error handling; the consent wrapper modeled on Google's sample; test-mode with official test IDs; modern null-safe Dart.

**Fix (v1 weakness → v2 requirement):**

| # | v1 weakness | v2 requirement |
|---|---|---|
| 1 | Everything is a **singleton**; config is a **static global** read by every manager → forces elaborate `reset()` test plumbing | **Dependency injection.** Config and collaborators constructed and passed in. Keep a convenience facade, but no static global state. |
| 2 | Pinned to `google_mobile_ads ^7.0.0` | Target **`^9.0.0`**; use the `Large…` adaptive-banner API. |
| 3 | **Rewarded interstitial missing** (dead test-ID constant, no manager) | Implement fully, **with the required intro/skip screen**. |
| 4 | **Hand-rolled observer** + a duplicate broadcast stream | Idiomatic **`ChangeNotifier` / `ValueListenable`**; one notification channel. |
| 5 | **Lifecycle bug:** treats iOS `inactive` AND `paused` as backgrounded → app-open can fire after Control Center / permission dialogs; patched with brittle static suppression | Detect foreground via **`AppStateEventNotifier.appStateStream`**; suppress app-open while a full-screen ad shows via clean shared state, not statics. |
| 6 | **Static cross-object signaling**; two reactors can exist and fight | Single owner of app-open/foreground state; injected `FullScreenAdCoordinator`. Two reactors impossible by construction. |
| 7 | **Linear backoff, no jitter** | **Exponential backoff + jitter**, max attempts, cooldown, then **auto re-arm**. |
| 8 | **No auto-recovery after cooldown** for banner/native | Controllers re-arm a load after cooldown, not only on widget remount. |
| 9 | **No impression/global frequency cap** | `FrequencyCapPolicy`: per-format time + count caps AND a global cross-format cap. |
| 10 | Consent path fights the UMP callback API (`Completer` + void callbacks + multiple 60s timeouts) | A clean `ConsentGateway` wrapping UMP callbacks into `Future`s once. |
| 11 | `isUsingTestAds` false positives (unconfigured formats fall back to test IDs) | Compute test-mode from explicit config/flag, not resolved IDs. |
| 12 | Dangling doc/file references; silent `catchError((_){})` swallowing | Accurate docs; log-and-surface errors through one typed channel. |

---

### Primary sources
- pub.dev: https://pub.dev/packages/google_mobile_ads · versions: https://pub.dev/packages/google_mobile_ads/versions · API docs: https://pub.dev/documentation/google_mobile_ads/latest/
- CHANGELOG: https://github.com/googleads/googleads-mobile-flutter/blob/main/packages/google_mobile_ads/CHANGELOG.md
- Flutter guides: https://developers.google.com/admob/flutter/quick-start (+ /banner, /banner/collapsible, /interstitial, /rewarded, /rewarded-interstitial, /native, /native/templates, /app-open, /privacy, /privacy/gdpr, /privacy/idfa, /mediation, /test-ads)
- Next-Gen: https://developers.google.com/admob/android/next-gen/sdk · https://ads-developers.googleblog.com/2026/07/announcing-google-mobile-ads-next-gen.html · Flutter issue #1404
- Policy: https://support.google.com/admob (app-ads.txt: /answer/14538460 · app-open policy: /answer/9341964 · interstitial: /answer/6201362 · invalid traffic: /answer/3342054 · policy change log: /answer/9391084)
