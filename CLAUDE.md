# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`ad_flow` (v2.0.0) — a Flutter package that wraps **`google_mobile_ads ^9.0.0`** (AdMob) into a policy-compliant, DI-based ad layer: banner, interstitial, rewarded, rewarded-interstitial, native and app-open ads, plus UMP consent and (opt-in) iOS ATT. Android + iOS only. Also depends on `app_tracking_transparency` (iOS ATT, opt-in mode) and `shared_preferences` (frequency-cap persistence).

v2 is a ground-up rewrite: **no global singletons** (config and collaborators are injected). Public entry point is `AdFlow.initialize(config, {...}) → Future<AdFlow>`; `AdFlow.instance` is only a thin convenience pointer to the last-initialized instance.

> Ignore `.github/copilot-instructions.md` — it documents the **v1** architecture (singleton `*AdManager`s, `EasyBannerAd`, `MediationHelper`, `google_mobile_ads ^7.0.0`, blocking sequential init) and is **wrong** for v2. It should be deleted or rewritten.

## Read these FIRST (the real operating manual)

Before writing any code, **load the `ad-flow-builder` skill** and read, in order:
`docs/ad_flow_v2/PROGRESS.md` (where things stand + next step) → `PLAN.md` → `ARCHITECTURE.md` (the layer contract) → `DECISIONS.md` (ADR log — settled decisions + the *why*; do not relitigate) → `RESEARCH.md` (ground-truth `google_mobile_ads` 9.x / UMP / AdMob-policy facts — trust it, don't re-research). The skill's §2 (invariants) and §6 (traps) are load-bearing. `MIGRATION.md` maps v1→v2 public API.

## Commands

```bash
flutter analyze                                   # MUST be clean (0 issues) before moving on
flutter test                                      # full suite (~272 tests)
flutter test --concurrency=2                      # use if the runner OOM-kills (exit 137)
flutter test test/facade/ad_flow_test.dart        # one file
flutter test --plain-name 'CONFIG-BEFORE-LOAD'    # one test/group by name substring
dart format .                                     # required before publish (pana scores it)
cd example && flutter build apk --debug           # verify the example builds (Android)
dart pub publish --dry-run                        # publish check (docs/ + .claude/ excluded via .pubignore)
pana --no-warning .                               # package score (target 160/160)
```

Lints (in `analysis_options.yaml`, on top of `flutter_lints`): `unawaited_futures`, `close_sinks`, `cancel_subscriptions`, `avoid_print`, `prefer_final_locals`. `legacy/**` is excluded from analysis (and pubignored).

Workflow: **verify by running** — after each change, `flutter analyze` clean + `flutter test` green before continuing. Ship small vertical slices; commit per slice; keep the tree green. Update `PROGRESS.md` at session end (skill §4 handoff protocol). Commit messages end with the `Co-Authored-By` trailer.

## Architecture (the big picture)

Layered, bottom-up — **also the build order**. A layer may depend only on the layers below it, through their interfaces:

```
widgets      AdFlowBanner, AdFlowNativeAd, PrivacyOptionsButton, {Att,Consent,RewardedIntro}Screen
facade       AdFlow (composition root + ergonomic API)          lib/src/facade/ad_flow.dart
lifecycle    AppOpenAdManager (foreground detection)
controllers  Banner/Interstitial/Rewarded/RewardedInterstitial/Native/AppOpen (+ FullScreenAdControllerBase)
policies     RetryPolicy · FrequencyCapPolicy · AdGate · FullScreenAdCoordinator · KeyValueStore
consent      ConsentGateway (UmpConsentGateway) — wraps UMP + client-driven ATT
config       AdFlowConfig + per-format configs, AdPlatform
seam         AdSdk  (GmaAdSdk real · FakeAdSdk test)   ← the ONLY door to google_mobile_ads
```

**The SDK seam is the single most important structural rule (invariant 8).** `lib/src/seam/gma_ad_sdk.dart` is the *only* file that imports `google_mobile_ads` (and `app_tracking_transparency`). Everything above it talks to the interface `AdSdk` and is fully unit-testable with `FakeAdSdk` (shipped publicly in `lib/ad_flow_testing.dart`). This is enforced by `test/architecture/seam_boundary_test.dart` — respect it, or those tests fail.

`AdFlow.initialize` is the composition root: it builds the whole graph (seam → consent → policies → controllers → lifecycle), then runs startup in the background. `lib/ad_flow.dart` is the public barrel — export new public API there.

### Invariants (non-negotiable — each maps to real revenue or a policy/ban risk; full text in skill §2, each has a guarding test)

1. Consent gates every load — no `load()` before `canRequestAds()` is true (and, since ADR-033, before request configuration is applied — see below).
2. Privacy-options entry point surfaced when UMP requires it (reactive, via `ValueListenable`).
3. App-open: warm-start only, 4h expiry, never over another full-screen ad / banner.
4. Interstitials at natural breaks only; per-format + global frequency caps.
5. Rewarded interstitial: mandatory intro + skip screen first (enforced by construction).
6. No hardcoded production ad-unit IDs in `lib/`; test-mode from an explicit flag, not resolved IDs.
7. Single-use full-screen ads: show once, dispose in the dismiss/fail callback, reload the next immediately.
8. The SDK seam is the only door to the plugin (above).
9. No global mutable state (the sole sanctioned static is the `AdFlow._instance` pointer).

## Repo-specific behavior a new instance won't guess

- **Init is NON-BLOCKING (ADR-032/033).** `AdFlow.initialize()` builds the graph synchronously and its `Future` completes on the next microtask, **before** consent — consent/ATT/SDK-init/request-config all run in the background. **Never gate the first frame on it** (that was v1's splash hang). Render your UI immediately; ads/consent/ATT appear over it. `AdFlow.whenReady` (`Future<bool>`) is the optional await for the consent result — never required, never gate UI on it. No ad request goes out before request configuration is applied **and** the consent gate opens — `AdGate.canLoad` awaits a `_configApplied` gate (bounded by a timeout so a hung config degrades open, never hangs).
- **Presenter pattern, never `BuildContext`.** Consent/ATT/rewarded-intro screens are shown via app-supplied `Future` callbacks (`attExplainer`, `consentExplainer`, `rewardedIntroPresenter`) that resolve `navigatorKey.currentContext` *themselves*. The package never holds a `BuildContext`. A broken presenter is caught, recorded on `lastError`, and the real prompt/form still proceeds.
- **Create banner/native controllers ONCE** (a `State` field, never inside `build()`) — each `ads.banner()`/`ads.native()` mints a fresh controller and starts a new load (ADR-029). The widgets defend against a swap via `didUpdateWidget`, but one stable controller per placement is the correct usage.
- **`updateRequestConfiguration` must run AFTER `initialize()` completes**, never concurrently — the plugin services it synchronously on the platform thread and racing init's background bootstrap deadlocks a cold device (ADR-028; this cost a multi-round misdiagnosis — see skill §6).
- **Concurrency guards are synchronous-check-then-synchronous-write.** A check-then-`await`-then-write is a race (ADR-024); load/show guards write state before the first `await`, and the `FullScreenAdCoordinator` uses a synchronous `tryEnter()`.
- **`ink_sparkle.frag ... Expected 2, got 1` on a widget test = stale shader cache**, not a regression — `flutter clean && flutter pub get`, then re-run.
- Testing the real `GmaAdSdk` seam needs the plugin's own private test infrastructure (mock method-channel on a fresh `AdInstanceManager`) — see `test/seam/gma_ad_sdk_test.dart`. Most logic is tested at the `FakeAdSdk` level instead.
