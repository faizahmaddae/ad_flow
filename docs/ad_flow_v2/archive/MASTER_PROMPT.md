# TASK — Rewrite the `ad_flow` Flutter package to v2 (plan → skill file → full implementation)

You are Claude (Fable 5) working **inside the `ad_flow` package repository** (github.com/faizahmaddae/ad_flow). The package is currently **v1.3.18**, pinned to `google_mobile_ads: ^7.0.0`. We are doing a **ground-up rewrite to v2** targeting **`google_mobile_ads: 9.0.0`**, with a clean, layered, testable architecture, full AdMob **policy compliance**, robust **UMP consent**, revenue-optimized ad loading, and **optional experimental Next-Gen SDK** support.

The maintainer is **Faiz**, a Flutter developer who monetizes many apps with AdMob and uses this package as his shared ad layer. He speaks Persian — you may converse with him in Persian, but **all code, comments, docs, and file contents must be in English**.

> The research in Section 1 was already done for you by another model and verified against primary sources on 2026-07-11. **Treat it as ground truth. Do NOT burn your capacity re-researching it** — spot-check only if something looks wrong or stale.

---

## 0. HOW TO WORK HERE — read this before anything else (CRITICAL)

This project is intentionally structured so that **if you (Fable 5) run out of weekly capacity mid-way, a smaller/cheaper model (Sonnet 5 or Opus) can pick up and finish at the same quality.** Everything below serves that goal.

1. **Front-load the irreplaceable thinking.** Your highest-value output is *not* code — it is the durable planning artifacts and the skill file (Section 4). **Write those to completion FIRST**, before deep implementation. If you must stop early, stop *after* the plan + decisions + architecture + skill file are complete, never before.
2. **Research-first, but the research is already provided.** Section 1 is your knowledge base. Save it verbatim to `docs/ad_flow_v2/RESEARCH.md`. Only go to the web if you hit something genuinely not covered — and if you do, append what you learn to `RESEARCH.md` so the next model inherits it.
3. **Isolate layers.** Build the package as independent layers (SDK seam → config → consent → policies → per-format controllers → lifecycle → facade → widgets). Each layer must be usable and testable on its own. This is what lets a smaller model safely work on one layer without understanding all the others.
4. **Verify by running.** After every slice: `flutter analyze` must be clean and `flutter test` must be green **before you move on**. Never leave the tree broken between slices. A broken build is the one thing that makes a handoff fail.
5. **Ship small vertical slices.** One controller, one policy, one widget at a time — implement + test + analyze + commit. Never a giant untested change.
6. **Never fabricate APIs.** Use only the `google_mobile_ads` 9.0.0 API surface documented in Section 1 (and the official docs it links). If you're unsure a symbol exists, grep the installed package source under the pub cache before using it.
7. **Update the handoff log constantly.** Keep `docs/ad_flow_v2/PROGRESS.md` current at the end of every work session (Section 8). Assume the next turn is a different, smaller model with no memory of this conversation.

---

## 1. RESEARCH BRIEF / GROUND TRUTH  → save verbatim to `docs/ad_flow_v2/RESEARCH.md`

### 1.1 Versions & requirements (verified 2026-07-11)
- **Latest upstream: `google_mobile_ads: 9.0.0`** (published 2026-06-09, Apache-2.0).
- **v9 minimum requirements:** Flutter **≥ 3.38.1**, Dart **≥ 3.10.0**, iOS deployment target **13.0**, Android **minSdk 24 / compileSdk 36**, Android Gradle Plugin **8.13.1**.
- Native SDKs bundled by v9: Android `play-services-ads` **25.3.0** (+ experimental Next-Gen `ads-mobile-sdk` **1.1.0** behind a build flag); iOS `Google-Mobile-Ads-SDK` **~13.3.0**; UMP Android **4.0.0** / iOS **3.1.0**.
- Platforms: **Android + iOS only.**
- Current `ad_flow` (v1.3.18) pins `google_mobile_ads: ^7.0.0` → **two majors behind**; it version-conflicts with any app on 8.x/9.x. Dart env `^3.10.3`, Flutter `>=3.27.0`.

### 1.2 Migration deltas 7.x → 9.x (what actually changed)
The **core ad flow is stable** across 7→9: `load()` + `…LoadCallback` (`onAdLoaded` / `onAdFailedToLoad(LoadAdError)`), `fullScreenContentCallback` (`FullScreenContentCallback`), `show()`, `dispose()` are all unchanged. Concretely you must handle:
- **v8:** min Flutter → 3.38.1, Dart → 3.10.0. **iOS migrated to the `UISceneDelegate` protocol** — if the example app has a custom `AppDelegate` (needed for app-open/scene lifecycle), adopt the scene-based lifecycle. Swift Package Manager support added (CocoaPods still fine). **Adaptive-banner API deprecations** (old still works, migrate to the new names):
  - `AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width)` → **`AdSize.getLargeAnchoredAdaptiveBannerAdSize(width)`**
  - `AdSize.getAnchoredAdaptiveBannerAdSize(orientation, width)` → **`AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(orientation, width)`**
  - New **`BannerAd.isCollapsible`** property.
- **v9:** native SDK bumps + Next-Gen experimental flag (see 1.4). Android fix to pending start/stop futures in `AppStateNotifier`.
- **The only Dart-level breakage is the adaptive-banner rename** (deprecated, not yet removed). Everything else is project-side (min versions, iOS scene lifecycle).

### 1.3 Current v9 API patterns per format (use these exact shapes)
- **Banner:** `BannerAd(adUnitId, size, request: AdRequest(), listener: BannerAdListener(onAdLoaded, onAdFailedToLoad: (ad, LoadAdError e), onAdOpened, onAdClosed, onAdImpression, onAdClicked)).load();` render via `AdWidget(ad: bannerAd)` inside a `SizedBox`/`ConstrainedBox` sized to `bannerAd.size`; `dispose()` on removal.
- **Adaptive banner (anchored, current):** `final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(MediaQuery.sizeOf(context).width.truncate());` (may be null). Orientation-specific variant: `getLargeAnchoredAdaptiveBannerAdSizeWithOrientation`. **Inline adaptive** via `AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(...)` / `InlineAdaptiveSize`.
- **Collapsible banner:** request an (adaptive-sized) banner with `AdRequest(extras: {'collapsible': 'top' /* or 'bottom' */})`; after load check `(_ad as BannerAd).isCollapsible`. Google-demand only (does not fill via mediation); auto-refresh will NOT re-request a collapsible ad — reload manually.
- **Interstitial:** `InterstitialAd.load(adUnitId, request, InterstitialAdLoadCallback(onAdLoaded:, onAdFailedToLoad:))`; in `onAdLoaded` set `ad.fullScreenContentCallback = FullScreenContentCallback(onAdShowedFullScreenContent:, onAdDismissedFullScreenContent:, onAdFailedToShowFullScreenContent:, onAdImpression:, onAdClicked:)` then `ad.show()`. **Single-use**; `dispose()` in dismiss/fail.
- **Rewarded:** `RewardedAd.load(...)` with `RewardedAdLoadCallback`; set `fullScreenContentCallback`; `ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) { /* grant reward.amount of reward.type */ })`. High-value rewards → **server-side verification** via `ServerSideVerificationOptions`. Single-use.
- **Rewarded interstitial:** identical to rewarded but `RewardedInterstitialAd.load(...)` + `RewardedInterstitialAdLoadCallback`, `show(onUserEarnedReward:)`. **Policy requires an intro/announcement screen with clear reward messaging and a skip option BEFORE it plays** (no tap-to-watch opt-in like standard rewarded).
- **Native:** `NativeAd(adUnitId, request, listener: NativeAdListener(onAdLoaded, onAdFailedToLoad, onAdImpression, onAdClicked, onPaidEvent, ...), ...)` rendered via `AdWidget`. Two styles: **(a) Native templates (Dart-only, preferred)** via `nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small | TemplateType.medium, mainBackgroundColor:, cornerRadius:, primaryTextStyle:/secondaryTextStyle:/tertiaryTextStyle:/callToActionTextStyle: NativeTemplateTextStyle(...))` (small ≈ min 320×90, medium ≈ min 320×320); **(b) Platform views** via a native-registered `NativeAdFactory` + `factoryId:`.
- **App open:** `AppOpenAd.load(adUnitId, request, AppOpenAdLoadCallback(onAdLoaded:, onAdFailedToLoad:))`; set `fullScreenContentCallback`; `show()`. **A loaded ad expires after 4 hours** — store load time, discard/reload if stale. Foreground detection via **`AppStateEventNotifier.appStateStream`** (this is the official, correct signal — see 1.7). Single-use; dispose + preload next on dismiss.
- **Init:** `await MobileAds.instance.initialize()` → `Future<InitializationStatus>` (completes on init or a 30s timeout; `adapterStatuses` map reports mediation readiness). Configure via `MobileAds.instance.updateRequestConfiguration(RequestConfiguration(testDeviceIds:, tagForChildDirectedTreatment:, tagForUnderAgeOfConsent:, maxAdContentRating:))`.
- **Impression-level revenue:** every ad listener exposes **`onPaidEvent`** (`OnPaidEventCallback` → `PaidEvent` with value/currency/precision). Wire this for revenue analytics.
- **Preloading:** **the Flutter plugin has NO preload API even in 9.0.0** (verified — no `PreloadConfiguration`/`PreloadCallback`/preload manager). "Preloading" = manual: `load()` ahead of time, cache the instance, `show()` later, and **reload the next in `onAdDismissedFullScreenContent`/`onAdFailedToLoad`.**

### 1.4 Next-Gen SDK — the facts (Flutter)
- Next-Gen GMA SDK is **GA on native Android (2026-07-06)**, **does not exist for iOS yet**, and is **NOT GA in Flutter**. Full Flutter support is "targeting summer 2026 (subject to change)" (tracking issue #1404).
- What exists for Flutter today: an **experimental, Android-only, build-time opt-in** in plugin **v9.0.0**. The plugin's Android `build.gradle` reads a Dart define `USE_NEXT_GEN_SDK`; when true it swaps the native dependency (`ads-mobile-sdk` instead of `play-services-ads`). Enable with `flutter run/build --dart-define=USE_NEXT_GEN_SDK=true`.
- **The Dart API is identical either way** — same `MobileAds`, `BannerAd`, `InterstitialAd`, imports, callbacks. The flag swaps only the native Android implementation; iOS ignores it. So supporting Next-Gen from a Flutter *wrapper* is mostly: target v9, don't depend on legacy-only native internals, document the flag, and provide an example build variant.
- Android beta gains Google published: up to **27% faster** banner latency, **17% smaller** size, **+50% ARPU**, **+91.5% ARPDAU**, **+16% fill**, **+36.7% eCPM**, ~⅓ fewer ANRs. (No Flutter-specific numbers yet.)
- Risks: not GA, Android-only, **no Android TV** under Next-Gen, early-maturity bugs, mediation adapters must be Next-Gen-compatible. **Legacy vs Next-Gen is all-or-nothing per build** (chosen by the flag); the same plugin version supports both. **Avoid the third-party `admob_nextgen` pub package** — it is unofficial.

### 1.5 UMP / consent — correct 2026 flow
- API (all in `package:google_mobile_ads/google_mobile_ads.dart`): `ConsentInformation.instance.requestConsentInfoUpdate(ConsentRequestParameters, onSuccess, onError)` (call **every launch**); `ConsentInformation.instance.canRequestAds()` (the gate); `getConsentStatus()`; `getPrivacyOptionsRequirementStatus()`; `isConsentFormAvailable()`; `reset()` (**testing only**). Forms: `ConsentForm.loadAndShowConsentFormIfRequired(onDismiss)` (modern one-shot) and `ConsentForm.showPrivacyOptionsForm(onDismiss)` (the "manage consent" entry point). Params: `ConsentRequestParameters(tagForUnderAgeOfConsent:, consentDebugSettings:)`, `ConsentDebugSettings(debugGeography:, testIdentifiers:)`.
- **Rule: consent first, then load ads only when `canRequestAds()` is true.** `MobileAds.initialize()` may run in parallel with consent gathering (init sends no ad request), but **no `load()` before the gate is true.** `canRequestAds()` is false until `requestConsentInfoUpdate` has run once; it returns true when status is `obtained` OR `notRequired` (non-EEA). **Guard against double-loading** with a boolean (both the update callback and the form-dismiss callback can report the gate is open).
- **Privacy options:** if `getPrivacyOptionsRequirementStatus() == required`, you MUST expose a persistent, always-available "Manage consent / Privacy settings" entry point that calls `ConsentForm.showPrivacyOptionsForm(...)`. (GDPR: EEA + UK + Switzerland.)
- **ATT (iOS):** add `NSUserTrackingUsageDescription` to `Info.plist`; link AppTrackingTransparency. UMP can present the ATT explainer then the system prompt (configure the IDFA message in the AdMob console); the system prompt fires once per install when status is `notDetermined`. Ads still serve if denied (no IDFA). Don't double-prompt if the app also uses `app_tracking_transparency`.
- **Testing:** `ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea, testIdentifiers: ['HASHED-ID'])`; hashed ID is printed to console on first run; `reset()` to re-show the form (remove before release); emulators/simulators are auto-treated as test devices, but ATT only re-prompts after uninstall/reinstall.

### 1.6 AdMob policy + revenue rules to bake into defaults
- **app-ads.txt is required (since Jan 2025).** Newly configured apps must verify an `app-ads.txt` file or they cannot fully serve ads. Document this prominently in the README setup.
- **App-open:** never on the very first cold launch while still loading (show only from a dedicated splash/loading gate, else proceed without it); show on **warm start / foreground return** only; respect the **4h expiry**; frequency-cap; never layer over content that also shows a banner; never in "Designed for Families" apps.
- **Interstitial:** only at **natural transitions/breaks**; **≤ 1 per 2 user actions**; never on app launch or app exit; never immediately after another ad closes; never interrupt an active task. Preload so it doesn't pop in late.
- **Rewarded interstitial:** mandatory **intro screen + skip** before showing.
- **Banner:** prefer **adaptive (anchored `Large…`)** over fixed 320×50; keep an ad on screen **≥ 60s** before refresh; reserve fixed space to avoid layout shift → accidental clicks; keep a buffer from buttons/nav.
- **Invalid traffic / accidental clicks:** never click your own live ads (use test ads); no encouraging clicks; ads flush against buttons or that shift content trigger "Layout Encourages Accidental Clicks" enforcement; publisher is liable even for third-party invalid traffic. Consequences: serving limits → suspension.
- **Mediation & bidding:** raises fill + eCPM; adapters added in native `build.gradle`/`Podfile`; register partners in Privacy & messaging for consent; iOS mediation needs partner `SKAdNetworkItems` in `Info.plist` (Google's own SKAdNetwork IDs are bundled automatically).
- **Test ads:** required during development — Google sample IDs or a registered test device (renders a "Test Ad" label). Replace with production IDs before release.

### 1.7 Analysis of the current v1 package (what to keep, what to fix)
**Keep (good ideas):** the ergonomic facade + drop-in widgets (`EasyBannerAd`, native widget, privacy button); the thin testable SDK seam (`ad_sdk.dart`); the strong test culture (~1000 tests); the Remove-Ads/`disableAds` concept; cancellable-`Timer` retries; typed error handling; consent wrapper modeled on Google's sample; test-mode with official test IDs; modern null-safe Dart.

**Fix (v1 weaknesses → v2 requirement):**

| # | v1 weakness | v2 requirement |
|---|---|---|
| 1 | Everything is a **singleton**; config is a **static global** (`AdFlowConfig.current`) read directly by every manager → forces elaborate `reset()` test plumbing | **Dependency injection.** Config and collaborators are constructed and passed in. Keep a convenience `AdFlow` facade, but internals take explicit config — no static global state. |
| 2 | Pinned to `google_mobile_ads ^7.0.0` | Target **`^9.0.0`**; use the `Large…` adaptive-banner API. |
| 3 | **Rewarded interstitial missing** (dead test-ID constant, no manager) | Implement it fully, **with the required intro/skip screen** helper. |
| 4 | **Hand-rolled observer** (`AdStatusNotifier` = manual `List<VoidCallback>`) + a second duplicate broadcast stream in `AdsEnabledManager` | Use idiomatic **`ChangeNotifier` / `ValueListenable`**; expose `ValueListenable<AdState>` per controller. One notification channel. |
| 5 | **Lifecycle bug:** treats iOS `inactive` AND `paused` as "backgrounded" → app-open ad can fire after Control Center / permission dialogs / app-switcher; patched with brittle static suppression | Detect foreground via **`AppStateEventNotifier.appStateStream`** (official). Suppress app-open while a full-screen ad is showing via clean shared state, **not static globals**. |
| 6 | **Static cross-object signaling** (`AppLifecycleReactor.notifyFullscreenAdShowing()`); two reactors can exist and fight | Single owner of foreground/app-open state; inject a shared `AdVisibility`/`FullScreenAdCoordinator`. Make "two reactors" impossible by construction. |
| 7 | **Linear backoff, no jitter** | **Exponential backoff + jitter**, max attempts, then cooldown, then **auto re-arm**. |
| 8 | **No auto-recovery after cooldown** for banner/native | After cooldown, controllers re-arm a load automatically (not only on widget remount). |
| 9 | **No impression/global frequency cap** (interstitial has time-cooldown only) | A **`FrequencyCapPolicy`**: per-format time + count caps AND a global cross-format cap. |
| 10 | Consent path fights the UMP callback API (`Completer` + void callbacks + multiple 60s timeouts + a documented prior bug) | A clean **`ConsentGateway`** that wraps UMP callbacks into `Future`s once, exposing `Future<bool> ensureCanRequestAds()` + `showPrivacyOptions()`. |
| 11 | `isUsingTestAds` false positives (unconfigured formats fall back to test IDs) | Compute test-mode from explicit config/flag, not from resolved IDs. |
| 12 | Dangling doc/file references; silent `catchError((_){})` swallowing | Accurate docs; log-and-surface errors through one typed error channel. |

---

## 2. DECISIONS ALREADY MADE (with the maintainer) → record in `docs/ad_flow_v2/DECISIONS.md`

1. **Ground-up rewrite to v2** with a clean, layered architecture. Reuse *battle-tested logic* from v1 (retry timers, consent-sample flow, test-mode) but not its global-singleton structure.
2. **Clean v2 public API + a `MIGRATION.md` guide.** Breaking changes are allowed and expected; document each one. Do not contort the design for source-compatibility with v1.
3. **Next-Gen SDK: build the capability, keep it an opt-in option, default OFF.** Target v9; make sure nothing depends on legacy-only native internals; document `--dart-define=USE_NEXT_GEN_SDK=true` as an **experimental, Android-only** option; add an example build variant/flavor that turns it on; **legacy `play-services-ads` stays the default.** Never enable it by default. (Dart API is unchanged, so this is mostly compatibility + docs + example.)
4. **Test ads only in the example app.** The library itself never hardcodes production IDs; the consumer supplies per-platform ad-unit IDs via config. Keep a `testMode` that uses Google's official sample IDs.
5. **Versioning:** publish as **`2.0.0`**. Keep a clear `CHANGELOG.md`.

---

## 3. TARGET ARCHITECTURE → write to `docs/ad_flow_v2/ARCHITECTURE.md`

Follow this unless you find a concrete reason not to — if you deviate, record why in `DECISIONS.md`.

**Design principles:** dependency injection over global state; one idiomatic reactive primitive (`ChangeNotifier`/`ValueListenable`); each layer independently testable behind an interface; policy-compliant, revenue-optimized defaults; the SDK seam hides whether legacy or Next-Gen native code is running.

**Layers (bottom-up — also the build order):**

1. **SDK seam** — `AdSdk` (interface) + `GmaAdSdk` (real impl wrapping `google_mobile_ads`) + `FakeAdSdk` (tests). All plugin calls go through here. Nothing else imports `google_mobile_ads` directly except this seam and the widgets that need `AdWidget`.
2. **Config** — immutable `AdFlowConfig` (global knobs + per-format sub-configs: `BannerConfig`, `InterstitialConfig`, `RewardedConfig`, `RewardedInterstitialConfig`, `NativeConfig`, `AppOpenConfig`), each carrying per-platform ad-unit IDs, caps, and timing. A `testMode` factory using official sample IDs. Platform resolution behind an injectable `Platform` abstraction. **No static global config.**
3. **Consent** — `ConsentGateway` wrapping UMP: `Future<bool> ensureCanRequestAds()`, `Future<void> showPrivacyOptions()`, `bool get isPrivacyOptionsRequired`, ATT coordination. Wraps callbacks into Futures once; timeouts handled internally.
4. **Policies (cross-cutting)** — `RetryPolicy` (exponential backoff + jitter + max attempts + cooldown + auto re-arm), `FrequencyCapPolicy` (per-format time+count caps and a global cross-format cap, persisted via injected key-value store), and `AdGate` composing: ads-enabled? + `canRequestAds()`? + frequency cap OK? A `FullScreenAdCoordinator` tracks "a full-screen ad is on screen" so app-open won't double-fire.
5. **Per-format controllers** — a common `AdController` contract exposing `Future<void> load()`, `ValueListenable<AdLoadState>` (sealed: `idle | loading | loaded | showing | failed`), and (for full-screen) `Future<bool> show(...)`. Concrete: `BannerAdController`, `InterstitialAdController`, `RewardedAdController`, `RewardedInterstitialAdController`, `NativeAdController`, `AppOpenAdController`. Each owns its load/retry/preload/dispose lifecycle and consults `AdGate` before loading/showing. Full-screen controllers **reload the next ad on dismiss** and keep one warm.
6. **Lifecycle** — `AppOpenAdManager` subscribing to `AppStateEventNotifier.appStateStream`; shows app-open on foreground-return only, respects 4h expiry, frequency cap, and `FullScreenAdCoordinator` suppression. Exactly one owner of this behavior.
7. **Facade + widgets** — `AdFlow` composes the above and exposes the ergonomic API: `AdFlow.initialize(config)`, `.banner/.interstitial/.rewarded/.rewardedInterstitial/.native/.appOpen`, `.consent`, `disableAds()/enableAds()`, `openAdInspector()`, revenue callback hook (`onPaidEvent`). Drop-in widgets: `AdFlowBanner`, `AdFlowNativeAd`, `PrivacyOptionsButton`. Provide a convenience singleton accessor **backed by an injectable instance** (so tests construct their own).

**Public API sketch:** put a concrete Dart sketch of `AdFlowConfig`, `AdController`, the sealed `AdLoadState`, and the `AdFlow` facade in `ARCHITECTURE.md` so a smaller model implements to a fixed contract.

---

## 4. DELIVERABLES TO PRODUCE FIRST (before deep coding)

Create these now, in this order, and **finish all seven before starting Phase 2 implementation.** They are the "safety net" that lets a smaller model continue if you stop.

1. `docs/ad_flow_v2/RESEARCH.md` — Section 1 verbatim (your knowledge base).
2. `docs/ad_flow_v2/DECISIONS.md` — Section 2 + every architecture decision, ADR-style (context → decision → rationale → consequences). Append new ADRs as you make choices.
3. `docs/ad_flow_v2/ARCHITECTURE.md` — Section 3 expanded, with the concrete Dart API sketch and a module/layer map.
4. `docs/ad_flow_v2/PLAN.md` — the phased checklist from Section 6, with acceptance criteria per phase and check-boxes you tick as you go.
5. `docs/ad_flow_v2/MIGRATION.md` — v1→v2 migration guide; start it now (API mapping table) and grow it as the API solidifies.
6. `.claude/skills/ad-flow-builder/SKILL.md` — **THE SKILL FILE** (spec in Section 5). This is the single most important artifact for the handoff goal.
7. `docs/ad_flow_v2/PROGRESS.md` — the living handoff log (template in Section 8).

When 1–7 exist and are complete, **pause and show Faiz the PLAN and the skill file for a quick sanity check** before Phase 2 — unless he told you to run autonomously, in which case continue.

---

## 5. THE SKILL FILE SPEC → `.claude/skills/ad-flow-builder/SKILL.md`

> Faiz's instruction, verbatim: **"Write a skill file that teaches a smaller model to work the way you work here."** The point: a smaller model (Sonnet 5 / Opus) reads this skill + the docs and produces the same quality you would. Write it as a real, self-contained operating manual — not a summary of this prompt. Model it on the proven "teach HOW to work" pattern: **research-first, verify-by-running, isolate layers, ship simple, hand off cleanly.**

Structure it exactly like this:

```markdown
---
name: ad-flow-builder
description: Operating method for building and maintaining the ad_flow v2 Flutter AdMob package. Use this whenever ANY model works on ad_flow — it teaches HOW to work (research-first, verify-by-running, isolate layers, ship simple, hand off cleanly) so a smaller/cheaper model produces the same quality as a larger one and work can be handed between models without losing quality. Read this together with docs/ad_flow_v2/RESEARCH.md, DECISIONS.md, ARCHITECTURE.md, PLAN.md, and PROGRESS.md before writing any code.
---

# ad_flow builder — how to work here

## 0. Orient before you touch anything (every session, no exceptions)
Read, in order: PROGRESS.md (where we are) → PLAN.md (what's next) → ARCHITECTURE.md (the contract) → DECISIONS.md (why) → RESEARCH.md (ground truth). Never write code before doing this. If they conflict, PROGRESS/PLAN win for "what next", DECISIONS/ARCHITECTURE win for "how", RESEARCH wins for "facts about the SDK".

## 1. The method
- **Research-first, but don't re-research.** RESEARCH.md is the SDK/policy knowledge base. Trust it. Only hit the web for something genuinely uncovered, and append what you learn back to RESEARCH.md.
- **Isolate layers.** Work on ONE layer at a time (SDK seam → config → consent → policies → controllers → lifecycle → facade → widgets). Never reach across layer boundaries; depend only on the interface below you.
- **Verify by running.** `flutter analyze` clean + `flutter test` green before you move on. If you can't run them, say so in PROGRESS.md and stop — do not guess.
- **Ship small vertical slices.** One controller / policy / widget per slice: implement → test → analyze → update PROGRESS.md → commit. Never a big untested change.
- **Never fabricate an API.** Only use google_mobile_ads 9.0.0 symbols documented in RESEARCH.md. If unsure, grep the package source in the pub cache. A hallucinated API is worse than asking.

## 2. Non-negotiable invariants (AdMob-specific — violating these loses money or gets accounts banned)
- Never `load()` an ad before ConsentGateway says `canRequestAds()` is true.
- App-open ads: warm-start/foreground only (never first cold launch mid-load), 4h expiry enforced, never over another full-screen ad.
- Interstitials: only at natural breaks, global+per-format frequency cap enforced, never on launch/exit.
- Rewarded interstitial: always the intro+skip screen first.
- Test ads only; production IDs come from config; never hardcode a real ad-unit ID in the library.
- Every full-screen controller reloads the next ad on dismiss and disposes single-use ads.
- All plugin calls go through the AdSdk seam; only the seam + AdWidget hosts import google_mobile_ads.

## 3. Definition of done for a slice
Compiles; analyze clean; unit tests written and green (use FakeAdSdk); public API dartdoc'd; DECISIONS.md updated if you made a choice; PROGRESS.md updated; MIGRATION.md updated if public API changed; committed with a clear message.

## 4. Handoff protocol (you may be replaced by a smaller model mid-task)
End EVERY session by updating PROGRESS.md: what you finished, what's in-progress (exact file + the very next step), what's next, and how to verify (`flutter test path`). Leave the tree green. Never stop mid-slice with a broken build. Write PROGRESS.md as if the next worker has no memory of you — because it doesn't.

## 5. When stuck
State the blocker in PROGRESS.md, make the smallest safe assumption, record it in DECISIONS.md, and continue — or stop cleanly at a green state and ask Faiz. Never leave a broken build to "fix later".

## 6. Common pitfalls here (learned from v1)
[List the concrete traps: iOS `inactive` is NOT backgrounding — use AppStateEventNotifier; UMP callbacks must be wrapped into Futures, not fought with Completers+timeouts; unconfigured formats falling back to test IDs breaks test-mode detection; two lifecycle reactors fighting; linear backoff hammering the SDK; etc. Add to this list whenever you hit a new trap.]
```

Fill every `[...]` with real content. The skill must be usable standalone by a model that has never seen this prompt.

---

## 6. EXECUTION PLAN (phased, dependency-ordered) → the body of `PLAN.md`

Each phase = implement + unit tests (with `FakeAdSdk`) + `flutter analyze` + `flutter test` + update `PROGRESS.md` + commit. Give each phase explicit acceptance criteria in `PLAN.md`.

- **Phase 1 — Planning artifacts.** Produce deliverables 1–7 (Section 4). *Done when all seven files exist and are complete.*
- **Phase 2 — Scaffold + SDK seam.** New `lib/` layout, `pubspec` on `google_mobile_ads: ^9.0.0` (Flutter ≥3.38.1 / Dart ≥3.10), barrel export, `AdSdk` interface + `GmaAdSdk` + `FakeAdSdk`, CI-friendly `flutter analyze`/`flutter test` skeleton. *Done when the empty package compiles and a trivial seam test passes.*
- **Phase 3 — Config.** `AdFlowConfig` + per-format configs + `testMode` + platform resolution, fully unit-tested.
- **Phase 4 — Consent.** `ConsentGateway` (UMP wrapped in Futures), privacy-options, ATT coordination, debug settings; tests with a fake UMP.
- **Phase 5 — Policies.** `RetryPolicy` (exp backoff+jitter), `FrequencyCapPolicy` (per-format + global, persisted), `AdGate`, `FullScreenAdCoordinator`; heavily unit-tested (this is where correctness lives).
- **Phase 6 — Banner** (adaptive `Large…` default, collapsible, inline) + `AdFlowBanner` widget.
- **Phase 7 — Interstitial** (preload, reload-on-dismiss, gate + caps).
- **Phase 8 — Rewarded + Rewarded-interstitial** (SSV option; the **mandatory intro/skip screen** helper).
- **Phase 9 — Native** (templates + factory path) + `AdFlowNativeAd` widget.
- **Phase 10 — App-open + lifecycle** (`AppStateEventNotifier`, 4h expiry, coordinator suppression, cold-vs-warm handling).
- **Phase 11 — Facade + widgets** (`AdFlow`, `PrivacyOptionsButton`, `onPaidEvent` revenue hook, `disableAds`).
- **Phase 12 — Example app** (all formats, real UMP, a build variant with `--dart-define=USE_NEXT_GEN_SDK=true`, correct Android manifest App ID + iOS `GADApplicationIdentifier` + `NSUserTrackingUsageDescription` + UISceneDelegate).
- **Phase 13 — Docs** (README with setup incl. **app-ads.txt**, native ad factory setup, ATT, mediation notes; per-format docs; a **policy-compliance checklist**; finalize `MIGRATION.md`; `CHANGELOG.md`).
- **Phase 14 — Final verification** (full `flutter analyze` + `flutter test`, example builds on Android & iOS, `dart pub publish --dry-run` clean, pana score check, self-review against the Section 1 policy list).

---

## 7. GUARDRAILS & DEFINITION OF DONE (whole project)

- Package compiles and **`flutter analyze` is clean + `flutter test` is green at every commit.** Never commit red.
- **No fabricated `google_mobile_ads` APIs** — only the v9 surface in Section 1 / verified against the pub-cache source.
- **Consent-gated:** no `load()` before `canRequestAds()`; privacy-options entry point when required.
- **Policy-compliant defaults** for every format (Section 1.6) — frequency caps on, app-open warm-start-only + 4h expiry, interstitial break-points + caps, rewarded-interstitial intro/skip.
- **Test ads only in code/examples;** production IDs strictly via config.
- Every full-screen format **preloads + reloads on dismiss**; controllers auto re-arm after cooldown.
- Strong tests (aim to match/beat v1's coverage) via the `FakeAdSdk` seam; widget/golden tests for drop-in widgets.
- Docs + `MIGRATION.md` + `CHANGELOG.md` kept current; `dart pub publish --dry-run` clean at the end.

---

## 8. HANDOFF PROTOCOL (so Sonnet 5 / Opus can finish with Fable-5 quality)

The whole design assumes you may be swapped for a smaller model at any point. Make that safe:

- **`PROGRESS.md` is sacred.** Update it at the end of every session. Template:
  ```markdown
  # PROGRESS — ad_flow v2
  ## Current phase: <n> — <name>
  ## Done: <bullet list of completed slices + commit hashes>
  ## In progress: <exact file(s) + the very next concrete step>
  ## Next: <ordered next slices>
  ## How to verify current state: <exact commands, e.g. `flutter test test/policies/`>
  ## Open questions / assumptions: <anything a fresh model must know>
  ## Traps hit this session: <append to skill file section 6 too>
  ```
- **Always leave the tree green** and never stop mid-slice with a broken build.
- A resuming model's first action is: read the six docs (Section 5 step 0), run `flutter analyze` + `flutter test` to confirm the green baseline, then continue from `PROGRESS.md`.
- Front-load: if capacity is running low, prioritize (a) finishing the current slice to green, (b) updating PROGRESS.md + the skill file's traps list, over starting anything new.

---

## 9. KICKOFF — do this now

1. Confirm you're in the `ad_flow` repo; print `flutter --version` and the current `pubspec.yaml` google_mobile_ads constraint.
2. Create `docs/ad_flow_v2/` and `.claude/skills/ad-flow-builder/`.
3. Write deliverables 1–7 (Section 4) to completion — RESEARCH, DECISIONS, ARCHITECTURE (with the Dart API sketch), PLAN, MIGRATION (initial), the **SKILL file**, and PROGRESS.
4. Then pause and show Faiz the `PLAN.md` + `SKILL.md` for a quick check (skip the pause only if he says run autonomously), and begin **Phase 2**.

Remember the prime directive: **your scarce capacity is best spent making the plan, decisions, architecture, and skill file so good that a smaller model can build the rest at your level.** Build that safety net first, then start coding.
