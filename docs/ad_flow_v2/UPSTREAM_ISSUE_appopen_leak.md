# Ready-to-file upstream issue (googleads/googleads-mobile-flutter)

Verified against google_mobile_ads 9.0.0 (newest) and `main` (2026-07-17); no
existing issue found. Post this when ready (external action — not filed by the
tooling). Low severity; the fix is a safe one-liner upstream.

---

**Title:** AppOpenAd leaks on load failure: `_invokeOnAdFailedToLoad` disposes every full-screen format except AppOpenAd

**Body:**

> **Plugin version:** 9.0.0 (also present on `main` as of 2026-07-17)
> **Platforms:** Android + iOS (Dart-layer bug, both affected)
>
> ### Bug
> In `lib/src/ad_instance_manager.dart`, `_invokeOnAdFailedToLoad` calls `ad.dispose()` before the failure callback for `RewardedAd`, `InterstitialAd`, `RewardedInterstitialAd`, and `AdManagerInterstitialAd` — but **not** for `AppOpenAd`:
>
> ```dart
> } else if (ad is AdManagerInterstitialAd) {
>   ad.dispose();
>   ad.adLoadCallback.onAdFailedToLoad.call(arguments['loadAdError']);
> } else if (ad is AppOpenAd) {
>   ad.adLoadCallback.onAdFailedToLoad.call(arguments['loadAdError']); // no dispose()
> }
> ```
>
> `AdInstanceManager.loadAppOpenAd` inserts the ad into `_loadedAds` before the platform call, and `dispose()` is the only removal path. Since `AppOpenAdLoadCallback.onAdFailedToLoad` receives only the `LoadAdError` (no ad reference), and `instanceManager` is not exported, **apps have no way to dispose the failed ad**. Every failed `AppOpenAd.load()` permanently retains one entry in the Dart `_loadedAds` map plus its native counterpart (the native `disposeAd` call is never sent).
>
> The 0.13.0 changelog established the contract "Removes need to call `Ad.dispose()` for Rewarded and Interstitial ads when they fail to load"; app-open support was added in 0.13.5 and its failure branch never received the same treatment.
>
> ### Steps to reproduce
> 1. Call `AppOpenAd.load(...)` against an ad unit that fails (no network / no-fill), retrying on failure.
> 2. In a debugger, observe `instanceManager._loadedAds` grow by one `AppOpenAd` per failure; no `disposeAd` method-channel call is ever emitted for those ids.
>
> ### Impact
> Unbounded (process-lifetime) memory growth for apps that retry app-open loads. The leaked Dart callback closures also retain whatever they capture.
>
> ### Proposed fix
> Add `ad.dispose();` before the callback in the `AppOpenAd` branch, matching the other full-screen formats. This cannot break existing apps: the failure callback provides no ad reference, so no caller can currently be disposing (or otherwise using) the ad in that path.
