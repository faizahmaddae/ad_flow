# DECISIONS — ad_flow

Architecture decision records. **ADR-001 … ADR-083** (v2 → 6.0, July →
November 2026) are archived in full in
[archive/DECISIONS_v2-v6.md](archive/DECISIONS_v2-v6.md). The index below has
their titles; when code or docs cite one (`ADR-028`), grep the archive for the
number. Settled decisions are not relitigated without new evidence (a real
app, a device log, the plugin's source).

New records go at the end of this file, numbered from ADR-084, each a few
lines: **Context** → **Decision** → **Rejected** → **Consequences**.

## Index — ADR-001 … ADR-083 (archived)

"→ revised by" marks a record a later one changed in part or in full —
read both.

- ADR-001 — Ground-up rewrite to v2 · accepted
- ADR-002 — Clean v2 public API + MIGRATION.md · accepted
- ADR-003 — Target `google_mobile_ads: ^9.0.0` · accepted
- ADR-004 — Dependency injection over global singletons · accepted
- ADR-005 — One reactive primitive: ChangeNotifier / ValueListenable · accepted
- ADR-006 — The SDK seam is the only door to google_mobile_ads · accepted
- ADR-007 — Foreground detection via AppStateEventNotifier · accepted
- ADR-008 — Exponential backoff + jitter for retries · accepted
- ADR-009 — FrequencyCapPolicy: per-format + global caps · accepted
- ADR-010 — Next-Gen SDK: opt-in, Android-only, default OFF · accepted
- ADR-011 — Manual preloading (no Flutter preload API) · accepted
- ADR-012 — Test ads only in code; production IDs via config · accepted
- ADR-013 — Add rewarded interstitial with mandatory intro/skip · accepted
- ADR-014 — Publish as 2.0.0 · accepted
- ADR-015 — v1 parked under `legacy/v1/`, excluded from analysis and publish · accepted
- ADR-016 — Seam refinements: UMP primitives live in AdSdk; view handles build their own widget · accepted
- ADR-017 — Hand-written immutables; no freezed/build_runner (resolves ADR-P1) · accepted
- ADR-018 — No `appId` field in AdFlowConfig · accepted
- ADR-019 — ATT handled by UMP; no `app_tracking_transparency` dependency · accepted
- ADR-020 — Consent flow degrades to `canRequestAds()` on failure, surfacing `lastError` · accepted
- ADR-021 — Interstitial user-action pacing activates on first `recordUserAction()` · accepted
- ADR-022 — Public surface: zero google_mobile_ads re-exports; FakeAdSdk ships via `ad_flow_testing.dart` (resolves ADR-P3) · accepted
- ADR-023 — Rewarded interstitial intro presenter is injected at `AdFlow.initialize` · accepted
- ADR-024 — Concurrency-safety pass: synchronous re-entry guards close three real races · accepted
- ADR-025 — Sequential invariant self-review (1,2,5,6,8,9) closes Phase 14, finds and fixes a real staleness bug · accepted
- ADR-026 — Independent code review (Opus, commit `3ede24d`): 1 blocker + 3 majors + 4 minors + 2 test-hardening items + nits, all fixed · accepted
- ADR-027 — `AdFlow._start()` bounds `sdk.initialize()` with a 30s timeout (example-app hang triage) · accepted → revised by ADR-028
- ADR-028 — the example-app freeze was ours after all: `updateRequestConfiguration` must run AFTER `initialize()`, never concurrently · accepted
- ADR-029 — never build banner/native controllers inside `build()`; harden the widgets against a controller swap · accepted
- ADR-030 — client-driven ATT + presenter-based consent/ATT explainers (restores v1's `initializeWithExplainer`) · accepted (amends ADR-019)
- ADR-031 — ATT denial must never suppress a REQUIRED GDPR form (compliance fix + rename) · accepted (corrects ADR-030)
- ADR-032 — non-blocking `AdFlow.initialize()`: return immediately, run startup in the background · accepted
- ADR-033 — config-before-load gate: no ad request before `updateRequestConfiguration`, even for on-demand first-frame loads (closes an ADR-032 regression) · accepted → revised by ADR-061
- ADR-034 — errors DEGRADE, never wedge: every boundary catches `Object`, not just `AdFlowError` · accepted
- ADR-035 — the consent flow is RETRIED, and the gate WAITS for it (weak-network revenue) · accepted (amends ADR-032/033)
- ADR-036 — adaptive banners follow the layout width (reload on rotation/fold) · accepted
- ADR-037 — a broken device clock must not permanently block every ad · accepted
- ADR-038 — package-supplied screens must scroll, because their dismiss control is mandatory · accepted
- ADR-039 — the GLOBAL frequency cap gates INVOLUNTARY ads only · accepted
- ADR-040 — the frequency gap runs from the previous ad's DISMISS, not its SHOW · accepted
- ADR-041 — client-side banner refresh OFF by default; a refresh never blanks the slot · accepted → revised by ADR-083
- ADR-042 — an app-open ad never stacks on a banner/native ad · accepted → revised by ADR-083
- ADR-043 — app-open shows on the FIRST genuine warm return · accepted
- ADR-044 — `AdFlow.initialize()` is idempotent · accepted
- ADR-045 — `AdBlockReason`: a diagnostic surface, NOT a new `AdLoadState` case · accepted
- ADR-046 — banner refresh/resize interleavings: defer, re-validate, reconcile · accepted
- ADR-047 — a handle swap must REMOUNT the plugin's AdWidget (ObjectKey per handle) · accepted
- ADR-048 — seam hardening: refresh survival, dispatch normalization, reactive dimensions · accepted
- ADR-049 — show() uses cheap live checks; the click latch gets a close-grace window · accepted
- ADR-050 — live ads come DOWN when no longer permitted (registry + recheckGate) · accepted
- ADR-051 — full-screen preloads expire: shared maxAdAge with proactive replacement · accepted
- ADR-052 — runtime SSV updates; observability (paid-event slot + AdResponseSummary) · accepted
- ADR-053 — fail-fast config validation; null-safe slot getters; primer first-frame wait · accepted
- ADR-054 — seeded random-interleaving fuzz as a permanent regression net · accepted
- ADR-055 — 3.0.0: the compat-forbidden cleanup, and the redesigns deliberately rejected · accepted
- ADR-056 — nothing throws its way into a wedge: gate containment + app-callback isolation · accepted
- ADR-057 — per-load watchdog (RetryConfig.loadTimeout) · accepted
- ADR-058 — SSV is fail-closed at load · accepted
- ADR-059 — rewarded-interstitial show is an atomic reservation; RI joins the global cap · accepted (revises ADR-039 for RI)
- ADR-060 — frequency caps are memory-authoritative; persistence is serialized write-behind · accepted
- ADR-061 — request configuration is a retried process with an explicit failure policy · accepted → revised by ADR-083
- ADR-062 — honest mediation surfaces; no "UMP handles it all" claim · accepted
- ADR-063 — 4.1.0 post-release audit: no silent failure, take two · accepted
- ADR-064 — consent forwarding + deferral fail CLOSED by default (5.0.0 release gate) · accepted (corrects ADR-063's degrade-open forwarding) → revised by ADR-065
- ADR-065 — remove deferMediationInit; forward consent BEFORE initialize; serialize the forwarder source; invalidate stale-consent ads (release gate) · accepted → revised by ADR-066, ADR-083
- ADR-066 — simplification pass: fold stale-consent invalidation into `recheckGate`; rename `failOpen → unsafeFailOpen` (5.0.0, post-redesign) · accepted → revised by ADR-083
- ADR-067 — App Open trigger modes + explicit one-shot cold-launch opportunity (5.1.0) · accepted → revised by ADR-083
- ADR-068 — runtime SSV: finalize the loaded handle BEFORE publishing AdLoaded; generation-serialize updates (5.1.0) · accepted (hardens ADR-058 / the 4.1 runtime-SSV mixin) → revised by ADR-083
- ADR-069 — native ads expire (~55 min) and reload through the normal gate (5.1.0) · accepted (generalizes ADR-051 to native)
- ADR-070 — Remove-Ads collapses view ads to zero; deterministic adaptive pre-load placeholder (5.1.1) · accepted (corrects the ADR-050 kill-switch layout + the review-finding-#8 placeholder estimate)
- ADR-071 — never load while Mobile Ads init is in flight (incl. the forwardConsent path); close the disableAds() in-flight-load race; operationally-correct SSV docs (5.2.0) · accepted (hardens ADR-032/033/061 init-settle; extends ADR-050 kill-switch)
- ADR-072 — cached-consent startup fast path; final full-screen dispatch guard (5.2.1) · accepted (extends ADR-035 consent-as-a-process; extends ADR-024/050/071 same-turn revocation)
- ADR-073 — anchored adaptive banners are sized from the PLATFORM's post-load size; per-format sample ad units; opt-in opaque slot background (5.3.0) · accepted (corrects ADR-003's premise; completes the loaded-state half ADR-070 left open)
- ADR-074 — a native ad holds ONE box in every state: the full width it is given, at the reserved height (5.3.1) · accepted (completes ADR-070's native half; the native counterpart of ADR-073's width handling)
- ADR-075 — an ad the show engine will not show is dropped in the same turn as the claim release, never rolled back to `AdLoaded` first (5.3.1) · accepted (closes an ADR-024-class double load in ADR-072's final guard)
- ADR-076 — a closed gate is re-checked at most once a second, whatever `RetryConfig` says (5.3.1) · accepted (closes the config-induced case the ADR-035 addendum left open; ADR-053's validation unchanged)
- ADR-077 — a load that keeps failing re-arms at most once a second, whatever `RetryConfig.cooldown` says (5.3.1) · accepted (closes the failure-path case ADR-076 left open; ADR-053's validation unchanged)
- ADR-078 — `google_mobile_ads: ^9.2.0` is the floor; anchored banners are now Google's LARGE format for real (5.4.0) · accepted (amends ADR-003; closes the upstream half of ADR-073) → revised by ADR-081
- ADR-079 — an anchored banner reserves the height earlier banners of its width rendered at (5.4.0) · accepted (amends ADR-070's anchored placeholder; follows ADR-078)
- ADR-080 — integration boilerplate becomes one argument: `Screen.presenter(navigatorKey)` and `AdFlowBanner(safeArea:)` (5.4.0) · accepted (additive; keeps ADR-023/030's presenter pattern and ADR-070's zero footprint)
- ADR-081 — an opt-in classic anchored size: `BannerConfig.anchoredSize` (5.4.0) · accepted
- ADR-082 — the GDPR flow first, Apple's tracking question last; none after a purpose-1 refusal (5.5.0) · accepted (corrects ADR-030's ATT-first order; keeps ADR-031)
- ADR-083 — 6.0.0: the public surface follows what the apps do; unused machinery goes · accepted

## ADR-084 — The main library exports only what app code uses · accepted (2026-11-18)

**Context.** The 2026-11 review (F7) counted 105 exported types at 5.4,
internals included — the whole seam, the policy collaborators — so every
internal fix risked a major (2.0 → 5.0 in six days). ADR-083 moved the policy
collaborators out; 100 remained. The nine apps' `lib/` and `test/` use none of
the seam's handles, events or load specs, `FullScreenAdControllerBase`,
`BannerHeightMemory`, `SharedPrefsKeyValueStore` or `toRequestConfig()`;
`InMemoryKeyValueStore` only in tests that already import
`ad_flow_testing.dart`. `AdSdk`, `KeyValueStore`, `AdPlatform`,
`currentAdPlatform` and `asAdFlowError` do appear in app `lib/` code.

**Decision.** `package:ad_flow/ad_flow.dart` exports 71 types and 4 helpers:
the seam as `show AdSdk` (the `sdk:` injection type), `ad_sdk_types.dart`
through an explicit show-list (a new seam type is internal by default),
`key_value_store.dart` as `show KeyValueStore`. `ad_flow_testing.dart` adds
everything a test double needs (seam types, the full-screen engine,
`BannerHeightMemory`, `InMemoryKeyValueStore`, the policy collaborators).
`AdFlowConfig.toRequestConfig()` became the hidden top-level
`requestConfigFrom()`. `test/architecture/public_api_test.dart` pins the
75 names.

**Rejected.** The review's "~30 types": the apps really use the `AdLoadState`
family, the consent types, the controller classes and `AdPaidEvent`; hiding
them would break nine apps for nothing. `@internal` (package:meta) on the
controllers' `handle` getters — a new dependency for a marker the testing
library already gives. Moving `AdSdk` as well — app services take
`AdSdk? sdk` in `lib/`, and importing the testing library from app code would
be worse.

**Consequences.** Part of the 6.0.0 break (CHANGELOG, MIGRATION). An addition
to the main library needs an app that uses it; otherwise it goes in
`ad_flow_testing.dart`. That library is still public (app tests use
`FakeAdSdk`), so semver applies to it too. `BannerAdController.handle` /
`NativeAdController.handle` still return seam types (the widgets need them);
no app uses them.

## ADR-085 — A placement whose slot is not configured renders nothing · accepted (2026-11-18)

**Context.** Since 6.0 a slot may exist on one platform only: its full-screen
getter is null elsewhere. `AdFlowBanner(adFlow:)` / `AdFlowNativeAd(adFlow:)`
instead called `ads.banner()` / `ads.native()` in `initState`, which throw
`AdFlowError(invalidConfig)` without a config or an ID for the platform — a red
screen in debug and a grey error box in release, in front of users. Faiz left
the call to Claude.

**Decision.** In `adFlow` mode both widgets mint through
`mintPlacement()` (`lib/src/widgets/placement_mint.dart`): an
`invalidConfig` error means "no slot here", the widget renders
`SizedBox.shrink()` (safe-area inset included) and a debug build
`debugPrint`s the reason once per mount. A later config that has an ID
mounts and loads; losing it drops the owned controller. The controller
factories still throw — a direct call is a programming error.
Guarded by `test/widgets/unconfigured_placement_test.dart` (4, neuter-checked).

**Rejected.** `FlutterError.reportError` for the missing ID: it fails app
widget tests and floods crash reporting for an intentional one-platform slot.
A nullable `banner()` / `native()`: the `…OrNull` shape ADR-083 removed, and
the widget path is the recommended one. Asserting in debug: debug and release
would differ again (ADR-083 addendum).

**Consequences.** A forgotten ID shows as an empty slot plus one debug log
line, not a crash. Other `AdFlowError`s still propagate.

**Addendum (final review, 2026-11-18).** A per-placement `config:` skipped
the checks `initialize()` gives the global one, and the ID-less placeholder
resolved under the automatic debug default: `PlatformAdUnitId()` showed a
sample ad in debug and — with this ADR swallowing the release error — an
empty slot in release, silently. Now `banner()` / `native()` run
`validateBannerConfig` / `validateNativeConfig` (shared with
`AdFlowConfig.validate`) on a per-placement config, and `resolveAdUnitId`
treats an ID-less slot as a placeholder only with an explicit
`testMode: true`. Debug and release agree again. Guarded in
`unconfigured_placement_test.dart` and `ad_flow_config_test.dart`
(neuter-checked).

## ADR-086 — No primer before the GDPR form · accepted (2026-11-18)

**Context.** Review open decision 4. Since ADR-082 the order is GDPR first,
ATT last, so an EU user on iOS with both primers met four privacy screens in
a row: consent primer → UMP form → ATT primer → Apple's prompt. dehkhoda's App
Store reviewer read primer + prompts as asking twice. The default primer copy
also asked for consent before the form did ("we'd like your consent on the next
screen"), which a regulator can read as nudging. Four apps pass
`consentExplainer` (novels, jadval, nahjal_balagha, dehkhoda). Faiz left the
call to Claude.

**Decision.** The consent primer goes: `consentExplainer`,
`consentExplainerContent`, `ConsentExplainerScreen`, `ConsentExplainerContent`,
`ConsentExplainerPresenter`, and the gateway's primer step. The UMP form is
the first thing the user sees; the app's wording belongs in the message
itself (Privacy & messaging). The ATT primer stays: Apple allows a screen
that explains the prompt, and it now runs after the GDPR flow. The seam keeps
`getConsentStatus()` / `isConsentFormAvailable()` (UMP primitives a custom
gateway may use). The public API drops to 68 types + 4 helpers (ADR-084's
pin updated).

**Rejected.** Keeping it opt-in: every app that used it got the four-screen
start, and its removal costs each of them one argument in a migration they
make anyway.

**Consequences.** Breaking (6.0.0; CHANGELOG, MIGRATION). The ordering test in
`consent_gateway_test.dart` now also asserts that nothing of the app runs
before the form.

## ADR-087 — `showAtLaunch` stops waiting when the load fails · accepted (2026-11-18)

**Context.** The Android device check (emulator, profile build): the wait
for the launch ad ended only on ready, a definite refusal, or `maxWait`. A
first load that FAILED (offline, no fill) kept the loading screen up for the
rest of `maxWait`, waiting on a request that had already failed (with the
default retry timing no retry lands inside 3 s). The same check measured a cold start
where the SDK finished initializing at ~2.2 s and the ad was ready at ~4 s,
so a 3 s `maxWait` missed it there (iOS simulator: shown within 3 s).

**Decision.** `_waitUntilReady` also completes on `AdFailed`, including a
failure that happened before `showAtLaunch` was called; the refused show then
returns `blocked(notReady)` and kicks off the next load for a warm return.
The default `maxWait` stays 3 s (ADR-083): the README now says a slow device
may need a longer one when the loading screen stays up anyway.

**Rejected.** Raising the default to 5 s on one emulator run: an emulator
starts the Google SDK slower than a phone, and the cost — a longer loading
screen on every cold launch where the ad is slow — lands on every app.

**Consequences.** Offline or no-fill launches enter the app as soon as the
load fails. Guarded by `app_open_launch_test.dart` ("a load that FAILS …",
neuter-checked).

**Addendum (final review, 2026-11-18).** With a long `maxWait` and a fast
retry an ad could still have arrived inside the window; entering the app on
the first failure is the deliberate choice, and the docs now say so instead
of claiming no ad could come. Disposing the manager now also ends a pending
wait (it used to run until `maxWait`) — "disposed WHILE waiting" in the same
suite, neuter-checked.

