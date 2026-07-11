# PLAN — ad_flow v2

Phased, dependency-ordered. Each phase = implement + unit tests (with `FakeAdSdk`) + `flutter analyze` (clean) + `flutter test` (green) + update `PROGRESS.md` + commit. Tick boxes as you go. Do not start a phase until the previous one meets its acceptance criteria.

> Phase 1 was pre-authored and shipped in this bundle — see PROGRESS.md. A resuming model normally starts at **Phase 2**.

---

## Phase 1 — Planning artifacts  ✅ (shipped in bundle)
- [x] RESEARCH.md, DECISIONS.md, ARCHITECTURE.md, PLAN.md, MIGRATION.md, PROGRESS.md
- [x] `.claude/skills/ad-flow-builder/SKILL.md`
**Acceptance:** all seven files exist and are internally consistent. ✅

## Phase 2 — Scaffold + SDK seam
- [ ] New `lib/` layout per ARCHITECTURE.md; `pubspec.yaml` → `google_mobile_ads: ^9.0.0`, env Flutter ≥ 3.38.1 / Dart ≥ 3.10.0.
- [ ] `analysis_options.yaml` (flutter_lints + `unawaited_futures`, `close_sinks`, `cancel_subscriptions`, `avoid_print`).
- [ ] `AdSdk` interface + handles + `GmaAdSdk` (real) + `FakeAdSdk` (test).
- [ ] Barrel `ad_flow.dart` exporting only the intended public surface.
**Acceptance:** package compiles; a trivial `FakeAdSdk` test passes; `flutter analyze` clean.

## Phase 3 — Config
- [ ] `AdFlowConfig` + per-format configs + `PlatformAdUnitId` + `FrequencyCap` + `AdFlowConfig.test()`.
- [ ] Injectable `AdPlatform` + id resolution; explicit `testMode`.
**Acceptance:** config unit tests (resolution, test-mode from flag not ids) green.

## Phase 4 — Consent (ConsentGateway)
- [ ] Wrap UMP into `ensureCanRequestAds()`, `showPrivacyOptions()`, `isPrivacyOptionsRequired`, ATT coordination, debug options, internal timeouts.
**Acceptance:** tests with a fake UMP cover: non-EEA (gate true, no form), EEA (form then gate), error fallback, privacy-options-required.

## Phase 5 — Policies
- [ ] `RetryPolicy` (exp backoff + jitter + max + cooldown), `KeyValueStore` (+ in-memory fake), `FrequencyCapPolicy` (per-format + global), `AdGate`, `FullScreenAdCoordinator`.
**Acceptance:** heavy unit tests — backoff math, cap windows (session/hour/minGap), gate composition, coordinator enter/exit. This is where correctness lives.

## Phase 6 — Banner
- [ ] `BannerAdController` (adaptive `Large…` default, inline, collapsible, fixed) + auto re-arm + `AdFlowBanner` widget (reserved height, no layout shift, dispose on unmount).
**Acceptance:** controller + widget tests green; ≥ 60s refresh guidance honored.

## Phase 7 — Interstitial
- [ ] `InterstitialAdController` (preload, gate + caps, reload-on-dismiss, `minActionsBetween`).
**Acceptance:** tests: no show before gate; cap enforced; reloads after dismiss; never double-shows.

## Phase 8 — Rewarded + Rewarded-interstitial
- [ ] `RewardedAdController` (SSV option, `onUserEarnedReward`).
- [ ] `RewardedInterstitialAdController` + `RewardedIntroScreen` (disclosure + skip; ad only if not skipped).
**Acceptance:** reward callback fires exactly once; intro/skip enforced by test.

## Phase 9 — Native
- [ ] `NativeAdController` (template + factory paths) + `AdFlowNativeAd` widget; `onPaidEvent` wired.
**Acceptance:** template render test; factory path documented; dispose verified.

## Phase 10 — App-open + lifecycle
- [ ] `AppOpenAdController` (4h expiry) + `AppOpenAdManager` (`appForegroundEvents`, gate, coordinator suppression, cold-start rule).
**Acceptance:** tests: no show on cold start; shows on warm foreground; suppressed while a full-screen ad is visible; expired ad discarded+reloaded. Verifies the v1 `inactive` bug cannot recur.

## Phase 11 — Facade + widgets
- [ ] `AdFlow.initialize` composition root; `enableAds/disableAds`; `onPaidEvent`; `openAdInspector`; `PrivacyOptionsButton`; finalize the public re-export list (ADR-P3).
**Acceptance:** an end-to-end `FakeAdSdk` test drives init → consent → load → show → revenue callback.

## Phase 12 — Example app
- [ ] All formats; real UMP; correct Android `APPLICATION_ID` meta-data; iOS `GADApplicationIdentifier` + `NSUserTrackingUsageDescription` + `UISceneDelegate`; a build variant / documented command with `--dart-define=USE_NEXT_GEN_SDK=true`.
**Acceptance:** example builds on Android and iOS; Next-Gen variant builds on Android.

## Phase 13 — Docs
- [ ] README (setup incl. **app-ads.txt**, native-ad factory, ATT, mediation, Next-Gen flag); per-format docs; a **policy-compliance checklist**; finalize `MIGRATION.md`; `CHANGELOG.md` for 2.0.0.
**Acceptance:** a new user can integrate from the README alone.

## Phase 14 — Final verification
- [ ] Full `flutter analyze` + `flutter test`; example builds; `dart pub publish --dry-run` clean; `pana` score check; self-review against RESEARCH.md §6 policy list and every ARCHITECTURE invariant.
**Acceptance:** publish-dry-run clean; all invariants have a guarding test; policy checklist all ticked.

---
### Global definition of done (every phase)
Compiles · analyze clean · tests written & green via `FakeAdSdk` · public API dartdoc'd · DECISIONS/MIGRATION/PROGRESS updated · committed with a scoped message · tree left green.
