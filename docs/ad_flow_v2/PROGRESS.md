# PROGRESS — ad_flow v2/v3/v4/v5

## Current phase
**Phase 26 — 5.1.1 view-ad layout bug-fix (2026-07-20)** — ✅ **SHIPPED &
PUBLISHED (2026-07-21).** Merged, tagged, on pub.dev. A focused, backward-
compatible layout fix prompted by real emulator screenshots. No API change, no
migration. ADR-070.

**Release record.** PR [#11](https://github.com/faizahmaddae/ad_flow/pull/11)
squash-merged to `main` (admin bypass of the 1-review requirement only, all CI
green) at 2026-07-21T02:52:35Z → squash commit **`991b650`** (single commit
atop v5.1.0 `1dd6640`; `1dd6640` unchanged). Annotated tag **`v5.1.1`** (object
`8306ada`) → `991b650`. Published to pub.dev via the tag-triggered OIDC workflow
(run 29797262645, success) — **5.1.1 is live and Latest** on
https://pub.dev/packages/ad_flow. GitHub Release
[v5.1.1](https://github.com/faizahmaddae/ad_flow/releases/tag/v5.1.1) published,
Latest, non-draft/non-prerelease. Pre-merge CI 29796467895 ✓, post-merge main CI
29796986042 ✓, publish 29797262645 ✓ (only Node.js-20 deprecation annotations,
no failures). Verified: 537 tests, analyze clean, coverage 87.3%, pana 160/160,
dry-run 0 warnings, Android + iOS example builds, Android emulator runtime smoke
(enabled/disabled/re-enabled) — iOS was build-verified only, not interactively
runtime-tested.

The fix, as landed (ADR-070):

1. **Remove-Ads reclaims layout space.** `AdFlowBanner`/`AdFlowNativeAd` now
   collapse to a **zero footprint** while ads are disabled (was: kept reserving
   placeholder height). Widget-first mode listens to `adFlow.adsEnabled` for a
   **synchronous** collapse (no wait for the async `recheckGate`); advanced
   controller mode collapses on `AdBlocked(adsDisabled)`. `adsDisabled`
   overrides an explicit `placeholderHeight`. Re-enable reloads normally — one
   reload, no dup requests / reminting / handle leaks.
2. **Deterministic adaptive pre-load placeholder.** Removed the speculative
   "15% device height, clamp 50–90dp" estimate. Loaded → exact
   `handle.dimensions`. Pre-load: fixed → exact configured; large anchored
   adaptive → documented **50dp floor** then exact loaded size; inline adaptive
   → **0** (unknown until `onAdLoaded`). `placeholderHeight: 0` opts into fully
   collapsed pre-load; never honoured while `adsDisabled`.
3. **Example.** `bottomNavigationBar` returns `SizedBox.shrink()` BEFORE
   `SafeArea` (no empty inset bar); native `Card` (title/padding/border) hidden
   entirely; the Remove-Ads switch stays accessible; re-enable reconstructs
   both. Corrected the stale App Open subtitle (`launchAndResume`, not "never on
   a cold launch").

Files: `lib/src/widgets/ad_flow_banner.dart`,
`lib/src/widgets/ad_flow_native_ad.dart`,
`lib/src/controllers/banner_ad_controller.dart` (dartdoc only),
`example/lib/main.dart`, `test/widgets/ad_flow_banner_test.dart`,
`test/widgets/ad_flow_native_ad_test.dart`,
`example/test/home_screen_test.dart` (new), CHANGELOG/README/DECISIONS/pubspec
(→ **5.1.1**). Tests fail-first + neuter-verified (9 fail against reverted
widgets). See "How to verify" for the publish-gate results.

## Previous phase
**Phase 25 — 5.1.0 release-gate follow-up (2026-07-20)** — ✅ on branch
**`hardening-5.1.0`** (NOT pushed/tagged/merged/published). A focused gate on
the Phase-24 work before merge; no redesign. Findings, all fixed + fail-first:

1. **Semver break (CONFIRMED).** `FullScreenAdControllerBase` is exported, so
   `onLoaded()` is PUBLIC API — Phase 24 renamed it to `finalizeLoadedHandle`,
   which is breaking. RESTORED `onLoaded()` (post-publish) and KEPT
   `finalizeLoadedHandle()` as the additive pre-publish hook. New
   `public_api_compat_test.dart` (external-style subclass via the public barrel;
   neuter-verified the post-publish ordering).
2. **Launch latch (production path).** Removed the public `LaunchOpportunity`
   class + injected param; the one-shot is a private `static bool` in the
   internal, non-exported `LaunchLatch` (`launch_latch.dart`, allow-listed). Its
   test reset is `ad_flow_testing.dart`'s `resetAppOpenLaunchOpportunity()` — NOT
   a `@visibleForTesting` member on the exported manager (that would be
   production-public since `@visibleForTesting` ≠ private; corrected in the final
   API-hygiene pass). Tests exercise the REAL default path (facade `initialize` +
   reinit), not an injected surrogate.
3. **launchOnly inventory retirement.** After its single launch, launchOnly now
   retires inventory (`AppOpenAdController.retire()` → base `retireInventory()`)
   — no more dismiss/expiry/resume reloads of an ad it can never show.
   launchAndResume/resumeOnly unchanged. Request-count assertions; neuter-verified.
4. **Value semantics.** `NativeConfig.maxAdAge` ==/hashCode/validation tested;
   `AppOpenConfig` has no `==` so `triggerMode` needs none.
5. **Docs (release gate).** README install/migration → `^5.1.0`, stale v2/v3
   prompt rewritten, App Open cold-vs-warm + 3-mode examples + "can't guarantee
   cold launch without delaying the user"; ADR-067/068 corrected (onLoaded kept,
   private latch); `version_consistency_test.dart` docs-drift guard.

Verify: `dart format` clean, `flutter analyze` clean, **530 tests** green,
public API delta below. Public delta v5.0.0→HEAD is now — MAIN barrel
(`package:ad_flow/ad_flow.dart`): `+AppOpenTriggerMode`,
`+AppOpenConfig.triggerMode`, `+AppOpenAdManager.showAtLaunchIfReady`,
`+AppOpenAdController.retire`,
`+FullScreenAdControllerBase.{finalizeLoadedHandle,retireInventory}` (@protected),
`+NativeConfig.maxAdAge`, `+AdFlowConfig.test(appOpenTriggerMode:)`. TESTING
barrel (`package:ad_flow/ad_flow_testing.dart`):
`+FakeAdSdk.onFullScreenHandleCreated`, `+resetAppOpenLaunchOpportunity()`.
The main barrel gains NO launch-latch reset (the `LaunchLatch` state + its
reset are in an internal, non-exported file). `onLoaded` unchanged. No
removals, no breaking changes.

## Previous phase
**Phase 24 — 5.1.0 reliability + App Open UX pass (2026-07-20)** — ✅
implemented on branch **`hardening-5.1.0`** (off `main` at v5.0.0; NOT pushed/
tagged/merged/published — Faiz reviews). A focused, additive, backward-compatible
minor. Four coherent slices, each fail-first + neuter-verified:

1. **Runtime SSV readiness race (ADR-068).** A rewarded/RI ad could be
   externally ready/showable carrying a STALE SSV payload — the base published
   `AdLoaded` then re-attached a runtime override afterwards (unawaited), and
   concurrent updates had no ordering guard. Fixed: `onLoaded()` → awaited
   `finalizeLoadedHandle()` runs BEFORE `AdLoaded` (throw → fail closed);
   `showEngine` gates on `isReady`; the mixin overrides `isReady` during a warm
   re-attach and generation-serializes updates (latest wins on reverse-order
   native completion). `runtime_ssv_race_test.dart` (5 cases). Hypothesis
   CONFIRMED.
2. **Native ad expiration (ADR-069).** `NativeConfig.maxAdAge` (default 55min,
   null-disables). Timestamp loads, arm expiry on the shared `_timer`, drop +
   reload through the gate exactly once. `native_ad_expiry_test.dart` (7 cases).
3. **App Open trigger modes (ADR-067).** `AppOpenTriggerMode {launchOnly,
   resumeOnly (default), launchAndResume}` + `AppOpenAdManager.showAtLaunchIfReady()`
   — an explicit, one-shot, never-waits cold-launch path (cold launch is NOT
   faked from a lifecycle event). One-shot survives reinit via a process-global
   `LaunchOpportunity` (invariant-9's 2nd sanctioned exception, allow-listed).
   Example gains a real `StartupScreen`. `app_open_trigger_mode_test.dart` (17
   cases). Chosen shape = the recommended enum; `showAtLaunchIfReady` on the
   already-exposed manager (no new facade method).
4. **Cheap hardening.** Contained `startListening()` rejection (seam);
   `enableAds`/`disableAds` inert after dispose (were an explosive
   write-after-dispose); `AppOpenAdManager` `_disposed` guard.

Verify: `dart format` clean, `flutter analyze` clean, **522 tests** green
(+28). Version **5.1.0**. Public delta: +`AppOpenTriggerMode`,
+`AppOpenConfig.triggerMode`, +`AppOpenAdManager.showAtLaunchIfReady`,
+`LaunchOpportunity`, +`NativeConfig.maxAdAge`, +`AdFlowConfig.test(appOpenTriggerMode:)`,
+`FakeAdSdk.onFullScreenHandleCreated` (test infra). No breaking changes.
ADR-067/068/069. See "How to verify" for the remaining publish-gate steps.

## Previous phase
**Phase 23 — 5.0.0 simplification / maintainability pass (2026-07-19)** — ✅
implemented on branch **`post-release-audit-4.1`** (off tag `v4.0.0`; NOT
merged/tagged/published — Faiz reviews). The ADR-065 redesign is accepted and
correct; this pass removes accidental complexity from its final diff without
touching the verified privacy/ordering invariants. ADR-066:

1. **Folded stale-consent invalidation into the existing `recheckGate()`.**
   Removed `AdController.invalidateForConsentChange()` + all 3 impls + the
   facade's `_invalidateLoadedAdsForConsentChange` fan-out. Each controller now
   stamps `_loadedGeneration` on install and `recheckGate` drops-and-reloads a
   generation-stale `AdLoaded` (before the permission check). `recheckGate`
   already ran after every consent mutation, so `_afterConsentMutation` calls
   only `_recheckAll()`. **Net: the `AdController` interface is unchanged vs
   v4.0.0** (no new public method); one owner for "re-evaluate a loaded ad."
2. **Renamed `MediationConsentFailurePolicy.failOpen → unsafeFailOpen`** (free
   rename, unreleased 5.0 enum). The `unsafe` prefix makes the opt-out hard to
   select by accident — no machinery added. `RequestConfigFailurePolicy.failOpen`
   (shipped 4.0) is untouched.
3. **Retained (deliberate):** `_loadedGeneration` per controller;
   `AdGate.consentGeneration` optional callback (public because the gate class
   already is, and per-file-library privacy forces it — defaults to `0`/no-op,
   never an integration step); un-timeout'd `_forwardSource` serialization (a
   permanently-hung source fails CLOSED forever by design — documented, no
   cancellation framework). Invariants in ADR-066.

Verify: `dart format` + `flutter analyze` clean, **494 tests** green, pana
160/160, dry-run 0 warnings, Android + iOS example builds. Version stays
**5.0.0**. Public API delta from v4.0.0 in ADR-066's Consequences.

---

**Phase 22 — 5.0.0 mediation-lifecycle release gate #2 (2026-07-19)** — ✅
implemented on branch **`post-release-audit-4.1`** (off tag `v4.0.0`; NOT
merged/tagged/published — Faiz reviews). A second release-gate review
(verified against current Google Android/iOS docs + the plugin's native
source) found the 5.0-draft forwarding design had upstream-semantics and
lifecycle errors. Fixed as ADR-065 (supersedes ADR-064's request-time model):

1. **`deferMediationInit` REMOVED.** `disableMediationInitialization` is a
   session-wide DISABLE of Google mediation (docs: "noop once initialize() or
   the first ad request is made"; "for... an A/B test"), NOT a defer/resume —
   conceptually invalid and revenue-harming.
2. **`forwardConsent` runs BEFORE `MobileAds.initialize()`.** Adapters read
   their flag DURING GMA init (AppLovin/Meta), so init is gated on forwarding.
   Fail-closed: forward failure → SDK not initialized + loads blocked +
   retried; init/serving recover on success. `unsafeFailOpen` initializes
   anyway. UI non-blocking (`initialize()` returns immediately).
3. **Forwarder source serialized across the timeout boundary.** `Future.timeout`
   does not cancel its source; the un-timeout'd invocation is tracked so at
   most one runs and older→newer external side effects are strictly ordered.
4. **Stale-consent ad invalidation** (later folded into `recheckGate` by
   ADR-066): a warm full-screen / visible banner/native loaded under old
   consent is dropped+reloaded on a mutation; a showing full-screen ad is not
   interrupted.

Verify (at Phase 22): `flutter analyze && flutter test` → clean. Version stays
**5.0.0**. ADR-065; docs (README/CHANGELOG/MIGRATION/MEDIATION_SETUP)
reconciled to forward-before-init + removal.

---

**Phase 21 — 5.0.0 release-gate correction (2026-07-19)** — folded into
Phase 22 above. The release-gate review found the 4.1 consent-forwarding
barrier degraded OPEN on failure — a mediation partner could receive an ad
request without its required privacy signal. Redesigned **fail-CLOSED by
default** (mirrors ADR-061's request-config policy): forwarding failures now
BLOCK mediation-capable loads (`AdBlockReason.consentNotForwarded`, new enum
case → major), retried in the background, recovering when forwarding
succeeds; explicit `MediationConsentFailurePolicy.unsafeFailOpen` is the only
(unsafe) way to serve anyway. Generation-guarded. Plus adversarial proofs
(fail-first + non-vacuity) for SSV latest-value-wins/dispose-races, cap-merge
dedup, and async-rejection containment through the REAL public void-typed
callbacks. ADR-064.

---

**Phase 21-orig — 5.0.0 release-gate correction (2026-07-19)** — ✅ implemented on
branch **`post-release-audit-4.1`** (off tag `v4.0.0`; NOT merged/tagged/
published — Faiz reviews). **Version bumped 4.1.0 → 5.0.0**: the release-gate
review found the 4.1 consent-forwarding barrier degraded OPEN on failure —
a mediation partner could receive an ad request without its required privacy
signal. Redesigned **fail-CLOSED by default** (mirrors ADR-061's request-
config policy): `forwardConsent`/`deferMediationInit` failures now BLOCK
mediation-capable loads (`AdBlockReason.consentNotForwarded`, new enum case →
major), retried in the background, recovering when forwarding succeeds; UI
never blocked; explicit `MediationConsentFailurePolicy.unsafeFailOpen` is the only
(unsafe) way to serve anyway. Barrier moved out of the consent chain into a
dedicated `AdGate` gate barrier; generation-guarded so mutations re-establish
it before newly-permitted loads and a stale forward can't satisfy a new
generation. Plus adversarial proofs (fail-first + non-vacuity) for SSV
latest-value-wins/dispose-races, cap-merge dedup, and async-rejection
containment through the REAL public void-typed callbacks. ADR-064.
Verify: `flutter analyze && flutter test` → clean, **483 tests**; pana
160/160; dry-run 0 warnings; Android + iOS example builds ✓; coverage 84.8%.

---

**Phase 20 — 4.1.0 post-release audit (2026-07-19)** — folded into 5.0.0
above. An independent adversarial re-audit (multi-agent workflow: 31
findings, 24 confirmed, 11 survived refutation) verified the supplied
hypotheses and hunted same-class issues. Six coherent slices, each
fail-first (+ neuter-verified where a debug repro exists):

1. Isolation: `guardedCallback` contains ASYNC callback rejections;
   refreshed-banner paid events routed through the guard; `safeUnawaited`
   for teardown dispose/cancel rejections.
2. `validate()` mirrors every constructor assert (release strips asserts).
3. Cap late-hydration MERGE guard (a store resuming past the 5s timeout no
   longer overwrites memory-authoritative caps).
4. Runtime SSV `RuntimeSsvController` mixin: re-apply on in-flight load
   completion; drop the stale warm ad on update failure.
5. Rewarded-interstitial re-validates live permission + expiry after the
   unbounded intro.
6. Awaited `forwardConsent` barrier (the headline): the first ad load waits
   for consent forwarding; bounded + contained; `deferMediationInit`
   failure now reported; docs reconciled (README `^3.0.0→^4.0.0`, the two
   4.0 AdBlockReason cases, MEDIATION_SETUP forwardConsent path);
   `MediationNetworkExtras` empty-name guard. ADR-063.

Verify: `flutter analyze && flutter test --concurrency=2` → clean, **466
tests**. Also green: `dart format`, `pana` **160/160**, `dart pub publish
--dry-run` (0 warnings), example Android APK + iOS simulator builds,
coverage **84.5%** (was 83.9%), and an iOS-simulator smoke run (iPhone 16
Pro): all six formats `ready` through the restructured consent/SSV paths,
native validator clean, live test banner. NOT externally verified: real
mediation consent-forwarding end-to-end (needs partner SDKs/accounts) and an
interactive rewarded-interstitial tap on device (the post-intro re-check is
unit-tested + neuter-verified).

## Previous phase
**Phase 19 — 4.0.0 independent production audit + hardening (2026-07-17)** —
✅ implemented on branch **`production-audit-3.x`** (7 slices, committed;
NOT merged, NOT tagged, NOT published — Faiz reviews/merges/tags when
ready). Version **4.0.0**. An adversarial audit of published 3.0.0 confirmed
7 externally-suggested findings (all fixed) and the fixes ship as coherent
invariants, each with fail-first tests:

1. Containment (ADR-056): gate never throws; app callbacks isolated;
   `AdBlockReason.internalError`; indeterminate never drops a live ad.
2. Per-load watchdog (ADR-057): `RetryConfig.loadTimeout` 60s; late
   completions disposed, never installed.
3. SSV fail-closed (ADR-058): `AdFlowErrorKind.ssv`; un-attachable SSV =
   failed load; plugin ack limits documented honestly.
4. RI atomic reservation (ADR-059): preflight before the intro, claim held
   through it; RI now under the global cap (classic rewarded stays exempt).
5. Memory-authoritative caps (ADR-060): sync decisions, serialized
   write-behind, bounded hydration.
6. Request-config failure policy (ADR-061): retried process;
   auto/failOpen/failClosed; `AdBlocked(requestConfigNotApplied)`; never
   dispatches while init in flight (ADR-028 hardening).
7. Honest mediation surfaces (ADR-062): per-slot request options,
   `MediationNetworkExtras`, `onConsentChanged`, `deferMediationInit`;
   MEDIATION_SETUP/README rewritten off the "UMP handles it all" overclaim.

Verify: `flutter analyze && flutter test --concurrency=2` → clean, **448
tests**. Also green this session: `dart format` (committed), `dart pub
publish --dry-run` (0 warnings), `pana` **160/160**, example
`flutter build apk --debug` ✓ and `flutter build ios --simulator --debug` ✓,
coverage **83.9%** (was 81.2%), and an on-simulator smoke run (iPhone 16
Pro, iOS 18.6): HomeScreen rendered, interstitial/rewarded/RI all `ready`
through the NEW config-settle machinery, native validator "No
implementation issues found", live adaptive test banner. NOT re-verified
on-device this session: the RI intro interactive flow (its presenter is
unchanged from the 3.0 on-device pass; only the pure-Dart ordering
changed, which is fakeAsync-covered) and Android runtime. Docs updated:
CHANGELOG 4.0.0, MIGRATION 3.x→4.0, README claims softened to
"policy-aware", MEDIATION_SETUP rewritten honest, NATIVE_ADS_SETUP
widget-first, garbled `slotName` dartdoc prose fixed, pubspec 4.0.0, CI
gained an iOS example build job.

## Open items for Faiz (4.0.0)
- Review + merge `production-audit-3.x`; tag `v4.0.0` when ready (tag
  auto-publishes). The v3.0.0 tag is untouched.
- Optional on-device sanity: one rewarded-interstitial interactive cycle
  (intro → watch → reward) and one Android emulator session.
- If you use mediation partners today: wire `onConsentChanged` per the new
  doc/MEDIATION_SETUP.md §4 (Unity/Meta/AppLovin signals are yours).

## Previous phase
**Phase 18 — 3.0.0 API cleanup (2026-07-17)** — shipped, merged, tagged
v3.0.0, published. ADR-055 records what 3.0 broke and the redesigns it
deliberately rejected.

## Previous phase
**Phase 17 — production-hardening audit + fixes (2026-07-17)** — ✅ shipped on
branch `production-hardening-2.2.0` (11 commits). Version 2.2.0 (never
published; folded into 3.0.0).

## What landed (Phase 17)
A 7-dimension multi-agent audit (61 agents, adversarial verification: 25
confirmed findings, 1 refuted, 21 improvement notes) + a full manual core read.
Every confirmed finding fixed, each as a fail-first slice with tests. ADRs
046–054 carry the full detail; CHANGELOG 2.2.0 + MIGRATION describe the
app-visible surface. Highlights, in commit order:

1. `fix(banner)` — refresh/resize interleaving races (leaked live BannerAd,
   stale-width stomp, wedged recovery timer) — ADR-046.
2. `fix(widgets)` — KeyedSubtree(ObjectKey(handle)): a swap now actually
   remounts the plugin AdWidget (it cannot re-point its platform view; a swap
   used to leave a permanently dead slot still buying ads) — ADR-047.
   ⚠️ Needs one on-device sanity pass with `minRefresh` set (platform-view
   identity is untestable in widget tests).
3. `fix(seam)` — inline-adaptive refresh no longer tears down the live ad on a
   size-query failure; load-dispatch throws normalized + cleaned up;
   `BannerHandle.dimensions` listenable; app-open failed-load plugin leak
   documented (upstream, unfixable here) — ADR-048.
4. `fix(policy)` — show() no longer holds the coordinator across a consent
   settle; view-ad click latch gets a 3s close-grace (iOS overlay clicks no
   longer eat the next warm return) — ADR-049.
5. `feat(facade)` — live ads DROP on disableAds/dispose/reinit/consent
   withdrawal (minted-controller registry + `recheckGate()` + graph-aware
   consent wrapper) — ADR-050.
6. `feat(fullscreen)` — `maxAdAge` expiry for interstitial/rewarded/RI
   (default 55min; Google documents ~1h) with proactive replacement; app-open
   unified onto the same mechanism — ADR-051.
7. `feat(rewarded)` — runtime `setServerSideVerification` (userId after
   login, per-show customData; applies to the warm ad; throws on failure).
8. `feat(observability)` — `AdPaidEvent.slot`/`adSourceName` +
   `AdResponseSummary` (`controller.response`) — ADR-052.
9. `feat(api)` — `AdFlowConfig.validate()` fail-fast, `…OrNull` getters,
   primer first-frame wait, PrivacyOptionsButton error surfacing — ADR-053.
10. `test` — seam coverage for all six formats through the real channel,
    seeded random-interleaving fuzz (ADR-054), ADR-040/042 gap tests,
    type-corrupt store tolerance, reinit cap continuity.
11. `docs/ci/release` — v1→v2 rewrite of the SHIPPED `doc/` folder (it still
    taught MediationHelper/^7.0.0!), README (kill switch, Families note,
    both-platform snippet, 2.2.0 APIs), CHANGELOG/MIGRATION, CI (example
    build + pana + coverage jobs), `.pubignore` (internal prompt file),
    version 2.2.0.

## How to verify the current state
`flutter analyze && flutter test --concurrency=2` — expect clean, **414 tests
passing**. Also green this session: `dart format` (0 changes),
`dart pub publish --dry-run` (0 warnings), `pana` 160/160,
`cd example && flutter build apk --debug`. Coverage: 81.2% → re-run
`flutter test --coverage` after merge if you want fresh numbers.

## Open items for Faiz
- Review + merge `production-hardening-2.2.0`, then tag `v2.2.0` (tag
  auto-publishes).
- **On-device sanity pass** (the one thing unit tests cannot see): set
  `minRefresh: Duration(seconds: 60)` on the example banner and confirm the
  creative visibly changes after a refresh cycle (ADR-047), then revert.
- Optional: file the plugin's app-open failed-load leak upstream
  (RESEARCH §3, ADR-048) — re-check at the next `google_mobile_ads` bump.
- Two audit findings intentionally NOT acted on: interstitial default hourly
  cap left as-is (minGap 30s already bounds it; an added ceiling would
  surprise legit integrations — document-only), and no-fill (code 3) retry
  differentiation (3 attempts + backoff is not hammering; revisit if request
  volume ever matters).

---

# Phase 16 and earlier (history)

**Phase 16 — the 8 judgment calls (2026-07-14)** — ✅ all shipped. Version **2.1.0**,
**NOT tagged, NOT published** (a tag auto-publishes; Faiz tags when ready).

## What landed
Faiz approved all eight items the 2.0.2 audit deferred to him. Each is a fail-first
test → fix → green slice, with an ADR:

| # | Item | ADR | Test |
|---|------|-----|------|
| 1 | Global cap no longer blocks user-initiated rewarded / rewarded-interstitial | ADR-039 | `test/controllers/cap_semantics_test.dart` |
| 2 | Client-side banner refresh OFF by default (AdMob console does it) | ADR-041 | `test/controllers/banner_refresh_test.dart` |
| 3 | A banner refresh keeps the current ad until the next one loads | ADR-041 | same |
| 4 | App-open never stacks on a banner click / a declared blocking banner | ADR-042 | `test/lifecycle/app_open_placement_test.dart` |
| 5 | Frequency gap measured from DISMISS, not show | ADR-040 | `test/controllers/cap_semantics_test.dart` |
| 6 | App-open shows on the FIRST genuine warm return | ADR-043 | `test/lifecycle/app_open_placement_test.dart` |
| 7 | `initialize()` is idempotent (no leaked graph/reactors) | ADR-044 | `test/facade/reinitialize_test.dart` |
| 8 | `AdBlockReason` diagnostics (non-breaking, NOT a new AdLoadState case) | ADR-045 | `test/facade/diagnostics_test.dart` |

**Version: 2.1.0**, not 2.0.2 — new public API (`AdBlockReason`, `onAdBlocked`,
`lastBlockReason`, `setBlockingViewAdVisible`, `RewardedConfig.cap`,
`globalCapExemptSlots`, `BannerAdController.revision`) **and** meaningful default
changes (`minRefresh` off; global cap scope; dismiss-based gaps). **No breaking API
changes** — every existing call site still compiles. `AppOpenConfig.showOnColdStart`
is `@Deprecated` and ignored.

## Note for the next session
Item 8 was explicitly kept non-breaking. A new `AdLoadState` case (e.g. `AdBlocked`)
would be the "cleaner" model but `AdLoadState` is `sealed`, so it breaks every
exhaustive `switch` in every consuming app — do NOT ship that in a minor. If it is
ever wanted, it is a 3.0.0 change.

## How to verify the current state
`flutter analyze` && `flutter test --concurrency=2`
Expected: analyze clean, **313 tests passing**.

## Traps hit this session
Appended to SKILL.md §6 — chiefly: "a `ValueNotifier` will not notify you that a
handle was swapped, because `AdLoaded == AdLoaded`", and "when you delete a latch,
the tests that PRIMED that latch all lie".

---

# Earlier phases (2–14) — complete

## Done
- Phase 1 — Planning artifacts (committed `4e4132e`).
- Phase 2 — Scaffold + SDK seam ✅
  - v1 parked under `legacy/v1/` (ADR-015); pubspec → `google_mobile_ads: ^9.0.0` (resolves 9.0.0), env Flutter ≥ 3.38.1 / Dart ^3.10.0, version 2.0.0-dev.1; lint set per PLAN (`0a152ff`)
  - `core/`: `AdFlowError` (typed, throwable) + sealed `AdLoadState` (`18e907d`)
  - `seam/`: `AdSdk` interface + seam value types + drivable `FakeAdSdk` (`e7cf7d0`)
  - `seam/gma_ad_sdk.dart`: real impl — every symbol grep-verified against the pub-cache 9.0.0 source; pure mappers unit-tested; barrel exports core + seam (`2d8ba11`)
- Phase 3 — Config ✅ (this commit)
  - `config/ad_platform.dart`: injectable `AdPlatform` + `adPlatformOf` (throws `invalidConfig` off-mobile)
  - `config/ad_flow_config.dart`: `AdFlowConfig` + per-format configs, `PlatformAdUnitId`, `FrequencyCap`, `RetryConfig` (ports v1 timing: 3 attempts / 5s base / 5min cooldown), `ServerSideVerification`, `RewardIntroContent`, `TestAdUnitIds` (v1's verified Google sample IDs), `AdFlowConfig.test()`, explicit `testMode`, per-format effective-ID resolution, `toRequestConfig()`
  - ADR-017 (hand-written immutables, no freezed/copyWith), ADR-018 (no runtime appId field) (`69b2ca9`)
- Phase 4 — Consent ✅ (this commit)
  - `consent/consent_gateway.dart`: `ConsentGateway` interface + `UmpConsentGateway` — info update (30s timeout) → unconditional `loadAndShowConsentFormIfRequired` (plugin no-ops when not required) → `canRequestAds()`; degrades on failure with typed `lastError` (ADR-020); in-flight join as the double-load guard; `isPrivacyOptionsRequired` refreshed after update AND after form dismissal
  - ADR-019: ATT is UMP's job — no `app_tracking_transparency` dependency (resolves the Phase 4 open question)
  - `FakeAdSdk` gained `consentUpdateHold` (hang simulation) for the timeout test (`c1a491b`)
- Phase 5 — Policies ✅ (this commit)
  - `policy/key_value_store.dart`: `KeyValueStore` (getInt/setInt/getHistory/setHistory) + `SharedPrefsKeyValueStore` (`SharedPreferencesAsync`, `ad_flow.` namespace, corrupt-entry tolerant) + `InMemoryKeyValueStore` — ADR-P2 confirmed
  - `policy/retry_policy.dart`: exp backoff ×2 from `baseDelay`, ±jitter, `maxDelay` cap, injectable RNG; `shouldRetry` budget matches v1 semantics (3 = 3 total attempts)
  - `policy/full_screen_ad_coordinator.dart`: depth-counted `enter/exit` with clamped exit (can't wedge), `ValueListenable<bool>`
  - `policy/frequency_cap_policy.dart`: `StoredFrequencyCapPolicy` — session counts in-memory, hourly window via pruned persisted history, `minGap` via a separately persisted last-impression timestamp (works for gaps > 1h), global `_global` slot recorded on every impression
  - `policy/ad_gate.dart`: `canLoad` = enabled && canRequestAds (cheap current check, NOT the consent flow); `canShow` = coordinator && canLoad && caps (`2ee9464`)
- Phase 6 — Banner ✅ (this commit)
  - `core/ad_controller.dart`: `AdController` + `FullScreenAdController` contracts
  - `controllers/banner_ad_controller.dart`: gate-checked `load({width})` (width remembered for refresh/re-arm), retry-with-backoff → cooldown → auto re-arm, minRefresh refresh loop (clamped ≥30s) that disposes the old handle, paid-event forwarding, dispose-safe mid-flight loads
  - `widgets/ad_flow_banner.dart`: reserves height first frame (no layout shift), kicks the first load with real layout width, hosts `handle.buildWidget()`, `ownsController` disposal
  - `FakeAdSdk` gained `loadHold` (in-flight load simulation) (`9c7f2d7`)
- Phase 7 — Interstitial ✅ (this commit)
  - `controllers/full_screen_ad_controller_base.dart`: shared engine for ALL full-screen formats — gate-checked load, retry→cooldown→re-arm, show() with double-show guard, coordinator enter on Showed / exit on Dismissed+Failed (tracked via `_enteredCoordinator` so it can't decrement someone else's depth), `recordImpression` on Showed, dispose-handle-and-reload-immediately on dismiss/fail
  - `controllers/interstitial_ad_controller.dart`: thin subclass adding opt-in user-action pacing (ADR-021: dormant until first `recordUserAction()`)
  - `FakeFullScreenAdHandle.dispose` now defers stream close one microtask (controllers dispose handles from their own dismiss event — sync-close threw "Cannot fire new event") (`026b790`)
- Phase 8 — Rewarded + rewarded interstitial ✅ (this commit)
  - Seam: `ServerSideVerification` moved to seam types; `loadRewarded`/`loadRewardedInterstitial` take `{ssv}`; `GmaAdSdk` attaches it via `ad.setServerSideOptions(...)` (verified pub-cache: lines 1323/1418) BEFORE completing the load; `FakeAdSdk` records `rewardedSsvs`/`rewardedInterstitialSsvs`
  - Base engine: reward callback wrapped exactly-once (SDK misfire defense)
  - `controllers/rewarded_ad_controller.dart`: thin subclass, SSV from config
  - `controllers/rewarded_interstitial_ad_controller.dart`: injected `RewardedIntroPresenter`; intro precedes ad by construction; skip → no ad, stays warm; no intro when no warm ad; re-entrant intro rejected
  - `widgets/rewarded_intro_screen.dart`: material intro screen + static `show(context, content)` presenter (route-dismiss counts as skip) (`1d86014`)
- Phase 9 — Native ✅ (this commit)
  - `controllers/native_ad_controller.dart`: template + factory paths from `NativeConfig`, banner-style retry/cooldown/re-arm, NO refresh loop, manual `reload()`, `reservedHeight` per rendering path (small 90 / medium 320 / factory 100)
  - `widgets/ad_flow_native_ad.dart`: fixed reserved height, load on init, hosts `handle.buildWidget()`, `ownsController` disposal (`44d75c9`)
- Phase 10 — App-open + lifecycle ✅ (this commit)
  - Base gained `onLoaded()` hook + protected `discardCurrentAd()`
  - `controllers/app_open_ad_controller.dart`: load timestamp via injectable clock; `isExpired` on the 4h `AppOpenConfig.expiry`; `show()` discards-and-reloads stale ads instead of showing
  - `lifecycle/app_open_ad_manager.dart`: single owner of foreground behavior; subscribes seam foreground events; FIRST event after start() never shows (platform emits a foreground event on cold start too) unless `showOnColdStart`; all other policy (gate/caps/coordinator/expiry) delegated to the controller; idempotent start, stop, dispose
  - Tests verify: no cold-start show, warm-return shows, coordinator suppression, expiry discard+reload, cap pacing, stop unsubscribes — the v1 `inactive` bug cannot recur (foreground comes only from the seam's `AppStateEventNotifier` mapping) (`0da0f49`)
- Phase 11 — Facade + widgets ✅ (this commit)
  - `facade/ad_flow.dart`: `AdFlow.initialize` composition root — SDK init ∥ consent (init failure tolerated), `updateRequestConfiguration` once the gate opens, app-open manager started, configured full-screen formats preloaded; `enableAds/disableAds` (reactive `adsEnabled`), `onPaidEvent` dispatcher wired to every controller, `banner()`/`native()` per-placement factories (testMode-aware), throwing getters for unconfigured slots, `openAdInspector`, `dispose`, thin `AdFlow.instance` pointer (cleared on dispose)
  - `widgets/privacy_options_button.dart`: renders nothing unless required; tap → `showPrivacyOptions()` (invariant 2)
  - `lib/ad_flow_testing.dart`: public testing barrel shipping `FakeAdSdk` (ADR-022)
  - ADR-022 resolves ADR-P3 (zero gma re-exports); ADR-023 (intro presenter injected at initialize, fail-fast)
  - End-to-end FakeAdSdk test: init → EEA consent → preloads → show → paid callback; plus closed-gate, remove-ads, global-cap-across-formats, factories, instance lifecycle

- Phase 12 — Example app ✅ (this commit)
  - Fresh `example/` (android+ios): all six formats over `AdFlowConfig.test()`, non-blocking init (runApp first, `AdFlow.initialize` behind a FutureBuilder), navigatorKey + `RewardedIntroScreen.show` presenter, action-pacing demo, Remove-Ads toggle, `PrivacyOptionsButton`, paid-event logging, Ad Inspector button, bottom banner
  - Android manifest sample `APPLICATION_ID`; iOS `GADApplicationIdentifier` + `NSUserTrackingUsageDescription` (template already scene-based — `UIApplicationSceneManifest` with SceneDelegate, satisfying gma v8+'s UISceneDelegate requirement)
  - **Verified builds:** `flutter build apk --debug` ✓ · `flutter build apk --debug --dart-define=USE_NEXT_GEN_SDK=true` ✓ · `flutter build ios --simulator --debug` ✓

- Phase 13 — Docs ✅ (this commit)
  - `README.md` rewritten for v2: app-ads.txt front and center, platform setup, per-format usage, consent/ATT per ADR-019, Remove-Ads/revenue/inspector, FakeAdSdk testing, Next-Gen flag, mediation pointer, policy checklist
  - `MIGRATION.md` finalized: config field table + removed/renamed symbol table (from `legacy/v1` barrel)
  - `CHANGELOG.md`: 2.0.0 entry prepended (NEW/IMPROVED/FIXED/BREAKING)
  - `legacy/v1/` removed — porting complete (`a70b313`)
- Phase 14 (in progress) — Final verification: concurrency-safety pass ✅ (this commit)
  - A background multi-agent review (5 finder dimensions, adversarial verify) mostly hit a spend-limit mid-run — 3/5 finders completed, nearly all verifier agents errored, so its "confirmed: []" result is **not trustworthy** (absence of confirmation ≠ absence of bugs; most verify votes never ran). Do not cite that run's output directly.
  - However the finder agents had ALSO written 3 hand-crafted repro tests directly into the working tree before erroring out. Ran them manually and **independently confirmed 3 real concurrency bugs** (see ADR-024 for full detail): double-load (two concurrent `load()` calls both hit the SDK, leaking a handle), double-show (two concurrent `show()` calls both invoked `handle.show()` on one single-use ad), and a cross-controller coordinator race (an interstitial and an app-open controller could both pass `canShow` and both display, since `coordinator.enter()` fired only after `handle.show()` resolved — too late to block a same-turn sibling). A 4th repro exposed a design gap: a banner blocked once by a closed gate never retried, even after the gate reopened.
  - **Fixed all four**, root-caused as "synchronous check, asynchronous write" races — see ADR-024 for the exact mechanism and why the coordinator fix specifically required a new synchronous `FullScreenAdCoordinator.tryEnter()` (moving `coordinator.enter()` earlier inside `show()` was tried first and did NOT close the race — the window is between two *different* controller instances, not within one).
  - Probe/repro files deleted; permanent regression tests added: `full_screen_ad_coordinator_test.dart` (`tryEnter` group), `interstitial_ad_controller_test.dart` (`concurrency safety` group), new `cross_controller_coordinator_test.dart`, `banner_ad_controller_test.dart` (`gate-blocked recovery` group).
  - 194 tests green, analyze clean, example still builds (Android debug + Next-Gen flag).
- Phase 14 continued — sequential manual invariant self-review (1, 2, 5, 6, 8, 9) ✅ (this commit, ADR-025)
  - Done as a focused, SEQUENTIAL review (no parallel subagents — that's what hit the spend limit last time): state invariant → cite enforcing code → check every path (including the ADR-024 "check → await → act" race pattern, seam bypasses, static state, hardcoded ids) → write a failing repro first for any hole → fix → green; add/confirm a regression test either way.
  - **Invariant 1** (consent gates every load): solid. Gap: no per-format "no load while closed" test for rewarded/rewarded-interstitial/app-open (only interstitial covered the shared mechanism) — added to all three test files.
  - **Invariant 2** (privacy options entry point): **REAL BUG, fixed.** `PrivacyOptionsButton` read a plain `bool` getter once at build time — a widget mounted before the first `ensureCanRequestAds()` resolved (or across a later re-check) never rebuilt when the requirement later became true, permanently hiding the required control. `ConsentGateway` gained `ValueListenable<bool> get privacyOptionsRequired` + `dispose()`; `PrivacyOptionsButton` now uses `ValueListenableBuilder`; `AdFlow` tracks `_ownsConsent` and only disposes a self-created gateway, never an injected one.
  - **Invariant 5** (rewarded interstitial intro+skip): solid — structurally enforced by Dart's per-file `_handle` privacy (the base's private field is unreachable from the subclass's file, so `super.show()` — which the override always gates behind the intro — is the ONLY path to a real show). Added a missing dispose-mid-intro test (already safe).
  - **Invariant 6** (no hardcoded prod ids): solid, confirmed by grep across `lib/` and `example/`; testMode-with-platform-gap already covered.
  - **Invariant 8** (seam is the only plugin door): solid (exactly one importing file). Now has a permanent executable guard: `test/architecture/seam_boundary_test.dart` (verified it actually catches a violation).
  - **Invariant 9** (no global mutable state): solid (`AdFlow._instance` is the only mutable static, correctly the sanctioned ADR-004 pointer). Now has `test/architecture/no_global_state_test.dart` (verified it catches a violation too).
  - **seam-api dimension closed**: re-verified remaining `GmaAdSdk` mappings against pub-cache (AppOpenAd genuinely has no SSV support unlike Rewarded/RewardedInterstitial; NativeAd.customOptions type; AdWidget/FullScreenContentCallback generics; rewarded `show()`'s required callback always satisfied). No new bugs.
  - **test-gaps dimension closed**: added tests for `AdFlow.dispose()` idempotency, `_ownsConsent` disposal semantics (self-created gateway provably disposed, injected one provably survives), and banner-in-unbounded-width (confirmed already-correct behavior: no load attempted, no crash).
  - 205 tests green, analyze clean, example still builds.
- Phase 14 closed out — publish readiness ✅ (this commit, ADR-025 continued)
  - `dart pub publish --dry-run`: clean except the expected "CHANGELOG doesn't mention 2.0.0-dev.1" note (intentional — resolves when actually bumping to `2.0.0` at publish time).
  - `pana`: started at 140/160 (pubspec description over 180 chars losing 10/10 on "valid pubspec.yaml"; `dart format` flagging 8 files losing 10/50 on static analysis). Trimmed the description to fit, ran `dart format .` (27 files reformatted, whitespace/wrapping only — no logic changes), fixed 2 dartdoc unresolved-reference warnings (`[sdk]`/`[config]` referred to private constructor param names `_sdk`/`_config`, not the doc'd names — reworded to avoid the mismatch). **Final score: 160/160.**
  - No further code changes; this was polish only, not a correctness pass — the correctness work is entirely in the invariant self-review above (ADR-025).
- Independent code review (Opus, `docs/ad_flow_v2/REVIEW_FINDINGS.md`, commit `3ede24d`) — 1 blocker + 3 majors + 4 minors + 2 test-hardening items + nits, all fixed ✅ (ADR-026)
  - **#1 BLOCKER**: rejected `handle.show()` had no try/catch → wedged the shared coordinator (and every full-screen format) for the rest of the session. Fixed with try/catch + rollback through the existing `AdFailed`+reload path (`9aa14c4`).
  - **#2 MAJOR**: `GmaAdSdk._finishBannerLoad` completed its `Completer` on every AdMob auto-refresh, not just the first load → `Bad state: Future already completed` every ~60s. Fixed with an `isCompleted` guard. Started `test/seam/gma_ad_sdk_test.dart` — the first real platform-channel test for `GmaAdSdk` (`ff90681`).
  - **#3 MAJOR**: stale retry timers stomped a since-recovered `AdLoaded`/`AdShowing` state, leaking a handle + subscription. Fixed in `FullScreenAdControllerBase`/`NativeAdController`/`BannerAdController` (`74d59e7`).
  - **#4 MAJOR**: `NativeAdController.reload()` reopened the ADR-024 double-load race by resetting to `AdIdle` even mid-flight. Fixed as a no-op while `AdLoading`; same guard added to `discardCurrentAd()` (`c50c0f2`).
  - **#9/#10**: expanded `gma_ad_sdk_test.dart` to interstitial load/dismiss/load-error/rejected-show + `appForegroundEvents`→`startListening`; hardened `FakeAdSdk` (2nd `show()` → `AdFailedToShowEvent`, impossible orderings throw) (`dddc471`).
  - **#5**: `updateRequestConfiguration` was gated on consent at init — sends no ad request, so a late-resolving gate meant test-device/COPPA/rating settings never reached the SDK. Now runs unconditionally (`0ceccf3`).
  - **#6**: `AdGate.canShow` re-embodied the ADR-024 race with no caller. Kept (public API) but doc now warns explicitly + a test proves the race (`2e582c7`).
  - **#7**: app-open could fire immediately behind another format's dismiss (only an app-configurable, possibly-zero `minGap` prevented it). `FullScreenAdCoordinator` gained `lastExitAt`; `AppOpenAdManager` gained an optional `coordinator` + 1s `postDismissSuppression` (`d0547f1`).
  - **#8**: adaptive banners reserved a flat 50dp placeholder; Google's real bounds are 50–90dp (verified via web search, appended to RESEARCH.md). `AdFlowBanner` now reserves `(deviceHeight * 0.15).clamp(50, 90)` (`7f8c5a4`).
  - **#11**: `no_global_state_test`'s regex exempted `static final <UpperType>`, missing the realistic violation shape (`static final ValueNotifier... = ValueNotifier(...)`). Tightened to exempt only `static const` (`6041677`).
  - **#12**: added `test/architecture/no_hardcoded_ad_ids_test.dart`, mirroring `seam_boundary_test.dart` for invariant 6 (`68565f1`).
  - **Nits**: banner/native seam handles now close their `StreamController`s on load failure too; `DebugGeography` spellings verified correct; `AdFlowConfig.copyWith` intentionally still absent per ADR-017 (`0d302a4`).
  - 228 tests green (up from 205 at the end of ADR-025), analyze clean, example still builds. Full mechanism writeup: DECISIONS.md ADR-026.
- Example-app hang triage: `AdFlow._start()` gained a 30s timeout around `sdk.initialize()` ✅ (ADR-027)
  - Reported: "the v2 example has a problem." Reproduced with `flutter run -d emulator-5554 -v` (full trace) — app never got past the native launch splash. `adb`/`dumpsys` confirmed a genuine indefinite native hang (0% CPU for 5.5 min, no ANR, no crash), traced via logcat to Google Play Services' own Chimera/Dynamite module loader for `com.google.android.gms.ads.dynamite`, which fires automatically at Android process start — **before Flutter's Dart isolate runs at all**. That specific freeze is not fixable in `ad_flow` (confirmed: re-ran with the fix already applied, hung identically at the identical log line) — it's this emulator's Play-Services state (0 Google accounts signed in). Checked and ruled out every upgrade-related suspect: Android AGP 8.11.1/minSdk/compileSdk built and ran clean; iOS Podfile's commented `platform :ios, '13.0'` line auto-resolved to 13.0 via the already-correct `IPHONEOS_DEPLOYMENT_TARGET`, `pod install` + `flutter build ios --no-codesign` both succeeded with zero errors.
  - Tracing the hang surfaced a real, separate, fixable gap: `_sdk.initialize()` inside `_start()`'s `Future.wait` had no timeout (unlike `ConsentGateway`'s existing `infoUpdateTimeout`), so a native init call that's merely *slow* rather than *frozen* — a real case on cold networks/first-run Play Services warmup, not just this broken emulator — would wedge the example's `FutureBuilder`-gated home screen forever with zero error. Fixed with a private `_initTimeout = Duration(seconds: 30)`. Repro-first: added `FakeAdSdk.initializeHold` (mirrors `consentUpdateHold`), a `fakeAsync` test in `ad_flow_test.dart` proved the hang before the fix and passes after. 229 tests green, analyze clean. Full writeup: DECISIONS.md ADR-027.
- Example-app hang triage, round 2: same freeze re-reported after ADR-027 landed — re-diagnosed from scratch, no code change ✅ (see ADR-027 addendum below)
  - Reproduced again on the same AVD with fresh `flutter run -v` + parallel `adb logcat`. Screen stuck on the *native* Flutter splash (not even the Dart `CircularProgressIndicator` from `main.dart`'s `FutureBuilder` painted) — a stronger symptom than round 1's report suggested. Instrumented `AdFlow._start` and `UmpConsentGateway._run` with temporary `debugPrint`s bracketing every step; only `_start begin` and `consent: requestConsentInfoUpdate begin` ever printed — never a DONE/ERR for anything, including the branch with the existing 30s `.timeout()`.
  - That last part is the real finding: queried the Dart VM service directly (`getIsolate` over HTTP) and it **timed out too** (5s, no response). A Dart-level `.timeout(Duration)` relies on the isolate's own timer queue running — if the isolate itself can't service a safepoint query, it can't service its own timeout timer either. So this is not "one `Future` among three is slow"; the whole main isolate is wedged, almost certainly because the native Play Services Ads-Dynamite module bootstrap (`ChimeraMobileAdsSettingManagerCreatorImpl` — identical log line both rounds) is blocking synchronously on Android's platform/UI thread, which the Flutter engine needs serviced to keep the Dart isolate's own scheduler moving.
  - Consequence: ADR-027's `_initTimeout` is real and correct for a native call that's slow-but-still-async (its documented purpose), but it cannot rescue this specific failure mode — a synchronously-blocked platform thread stalls the whole isolate, timers included, and no amount of Dart-side timeout wrapping can reach around that. There is no `ad_flow`-level fix for a plugin's native bootstrap blocking the platform thread; confirmed this is 100% this AVD's Play-Services state (0 Google account signed in, likely a half-initialized Ads Dynamite module cache), not a regression from any review-fix commit. Reverted the diagnostic `debugPrint`s; tree confirmed green (`git diff` empty, analyze clean) with no code change needed.
- Example-app hang triage, round 3: user restarted the whole computer and used a brand-new emulator — same freeze, stronger evidence, still no code change ✅ (see ADR-027 addendum, round 3)
  - Fresh "Pixel 10 Pro" AVD with a "Google Play" image (not "Google APIs"), created after a full host restart — rules out stale AVD state as round 1/2's remediation assumed. Froze at the identical `ChimeraMobileAdsSettingManagerCreatorImpl` log line a third time. Confirmed real network reachability first (`dumpsys connectivity`: both WiFi and cellular `EVER_VALIDATED&IS_VALIDATED`) — not a connectivity problem. Re-instrumented with a `Timer.periodic(3s)` heartbeat in `ExampleApp` (independent of `AdFlow` itself) plus `build()`/`FutureBuilder`/`_start` prints (all reverted, `git diff` on `example/lib/main.dart` empty after). `build()` ran, `_start` began, `FutureBuilder` reached `waiting` — but the heartbeat never fired once, and at +4m12s `flutter run` itself printed `Service protocol connection closed.`/`Lost connection to device.` and exited — the engine connection died outright, stronger than round 2's "isolate stopped answering."
  - Found the historical smoking gun via WebSearch: [googleads/googleads-mobile-flutter#429](https://github.com/googleads/googleads-mobile-flutter/issues/429) — an unrelated developer reported the *identical* log signature in 2022, on real devices too, confirmed by a Google team member as a real ads-init defect (at the time, server-side). This is a known, recurring native-SDK failure class, not something a Flutter wrapper introduces or can route around. 3-for-3 across 2 distinct fresh AVDs spanning a host restart, on this one machine — most plausibly host-specific (this Mac's virtualization path to the Play Services Dynamite CDN) or a currently-live instance of the same class of defect as issue #429.
  - Expanded `_initTimeout`'s doc comment in `lib/src/facade/ad_flow.dart` to state in-code, explicitly, which hang shape the 30s timeout does and doesn't cover, citing ADR-027. No other code change. Recommended to the user, in order: test on the already-confirmed-working iOS device; try a physical Android device; if emulator testing is required, try a different host machine.
- Example-app hang triage, round 4 — **the freeze was OURS after all; found and FIXED** ✅ (ADR-028, supersedes ADR-027's "unfixable" conclusion)
  - Rounds 1–3 concluded "native/environmental, unfixable in Dart." **Wrong.** Round 4 did the step the first three skipped (SKILL.md §5): read the `google_mobile_ads` plugin's own Android source. Found: `MobileAds#initialize` runs on a **background `new Thread(...)`** (`FlutterMobileAdsWrapper`), but `MobileAds#updateRequestConfiguration` is serviced **synchronously on the platform thread** inside `onMethodCall`, calling `MobileAds.get/setRequestConfiguration()` — which force the Ads-Dynamite settings-manager singleton (`ChimeraMobileAdsSettingManagerCreatorImpl`, the exact freeze line) to bootstrap on the platform thread, **racing init's background bootstrap of the same singleton → deadlock → dead isolate.** Every rounds-1–3 symptom, finally with a cause.
  - Regression from review-fix #5: it moved `updateRequestConfiguration` into the concurrent `Future.wait`. Before #5 it was consent-gated so it ran *after* init. Fix: `AdFlow._start()` now `await`s `initialize()` first, THEN `updateRequestConfiguration()` (still unconditional/not consent-gated, preserving #5). Repro-first: `fakeAsync` test holds `initializeHold` open, asserts `updateRequestConfiguration` isn't called until init completes — fails on old concurrent code, passes on ordered code.
  - **Verified by running on the same Pixel 10 Pro emulator that froze 4×**: full HomeScreen rendered, every format `ready`, native ad rendered, banner showed the live "Test Ad — 468x60". No freeze. 230 tests green, analyze clean. Corrected the now-wrong "environmental/unfixable" text in ADR-027 (kept as an honest misdiagnosis record), RESEARCH.md §3, `_initTimeout` doc, and SKILL.md §6.
  - Also generalizes beyond the emulator: any cold first-launch (real user's first run, cleared-data reinstall) where the Dynamite module isn't cached was at risk of the same platform-thread race — this closes a genuine production hang, not just an emulator annoyance.
- Full interactive on-emulator test of all six formats after the ADR-028 fix — found + fixed a native/banner-blank bug ✅ (ADR-029)
  - Drove every format via `adb` (interstitial, rewarded, rewarded-interstitial, native, banner, app-open) on the Pixel 10 Pro. All worked, but the **native ad + bottom banner blanked the instant a reward was earned** and stayed blank. Control case (interstitial: activity transition, no `setState`) kept them rendered; rewarded (transition + `setState` from the coin bump) blanked them → the trigger was `setState`, not the activity transition (ruled out Impeller).
  - Root cause: the example built `ads.native()`/`ads.banner()` **inside `build()`**, so every `setState` minted fresh unloaded controllers; `AdFlowNativeAd` only loaded in `initState` → swapped-in controller never loaded (permanent blank + leaked old controller). Fixed the example (hoist controllers to `late final` fields, create once) AND hardened both widgets with `didUpdateWidget` (dispose old if owned, load new) as a safety net. Two new regression tests (fail un-hardened, pass hardened).
  - Verified on-device: two reward cycles (coins 0→10→20) — native + banner stayed rendered both times. All six formats confirmed working end-to-end (interstitial pacing gate, rewards flowing, rewarded-interstitial intro+skip screen, app-open on warm return). 232 tests green.
  - Observation (left as-is, policy-safe): app-open shows on the *second* background→return, not the first — the first foreground event is consumed as the cold-start suppression because `AppStateEventNotifier` doesn't replay the cold-launch foreground (lazy `startListening`). Erring toward not-showing is correct (invariant 3).

- **Explainer v2 — restore `initializeWithExplainer` as presenter-based consent + ATT priming (opt-in, additive; ADR-030, spec `EXPLAINER_V2_SPEC.md`).** Shipped in 6 green slices, each analyze-clean + test-green + committed:
  1. `consent/explainer_content.dart` (`ConsentExplainerContent`/`AttExplainerContent` const+copyWith, `ConsentExplainerPresenter`/`AttExplainerPresenter` typedefs) + `widgets/consent_explainer_screen.dart` / `att_explainer_screen.dart` (copy the `RewardedIntroScreen` shape) + barrel exports + widget tests (`71315dd`).
  2. Seam ATT: `AttStatus` enum + `getTrackingAuthorizationStatus()`/`requestTrackingAuthorization()` on `AdSdk`; `GmaAdSdk` via re-added `app_tracking_transparency` (iOS-guarded by `defaultTargetPlatform`, non-iOS → `notSupported`), pure `attStatusFrom` mapper; `FakeAdSdk` gained `attStatus`/`attRequestResult`/`requestTrackingAuthorizationCalls` (`dbdad1f`).
  3. `UmpConsentGateway` flow: ATT first (primer → 200ms `attPromptDelay` → system prompt, only when `notDetermined`) → unchanged info update → GDPR form (primed only when `getConsentStatus()==required && isConsentFormAvailable()`, skipped when ATT denied && `skipGdprConsentIfAttDenied` default true). Throwing presenter → `lastError` set, real prompt proceeds. All §5 tests (`e693180`).
  4. Facade: `AdFlow.initialize` gained `consentExplainer`/`attExplainer`/`consentExplainerContent`/`attExplainerContent`/`skipGdprConsentIfAttDenied` threaded into a self-created gateway (injected gateway used verbatim); end-to-end + no-presenter regression tests (`e28d31e`).
  5. Example: `attExplainer`/`consentExplainer` wired via the existing `navigatorKey` (`908cdbb`).
  6. Docs (README §5 rewrite, MIGRATION mapping, ADR-030, SKILL §6 traps) + this update.
  263 tests green, analyze clean. **Still opt-in: no presenter → today's exact behaviour (regression-guarded at both gateway and facade level).**
  - **On-device iOS verification DONE** (iPhone 17 Pro Max simulator, iOS 26.3, fresh install + forced-EEA debug geography — temp `consentDebug` added then reverted, tree clean). Drove the full sequence via computer-use and confirmed each step visually: **`AttExplainerScreen` (my ATT primer) → Apple's system ATT prompt (with the `NSUserTrackingUsageDescription` copy) → `ConsentExplainerScreen` (my consent primer) → UMP GDPR form → HomeScreen** with all formats `ready`, the AdMob native validator reporting "No implementation issues found", the adaptive banner showing a test ad, and `[ad_flow] paid:` revenue events firing. No exceptions in the run log. The iOS `app_tracking_transparency` pod integrated cleanly (`pod install` 808ms; committed `example/ios/Podfile.lock`).
  - **Android build re-verified green** with the new dependency (`cd example && flutter build apk --debug` → `✓ Built app-debug.apk`); the ATT plugin's Android side is a no-op and the gateway unit test proves ATT is skipped off iOS (`notSupported`).
- **Adversarial self-audit of the explainer feature → 1 compliance bug FIXED + 2 guards added (ADR-031).**
  - **COMPLIANCE BUG (fixed):** `skipGdprConsentIfAttDenied` (default true) skipped the whole GDPR step-3 block on ATT-deny, so an EEA user who denied ATT never saw the *required* consent form (reproduced: `loadAndShowConsentFormCalls == 0`). ATT and GDPR are independent regimes. Fix: `loadAndShowConsentFormIfRequired()` now ALWAYS runs; the flag is renamed `skipConsentPrimerIfAttDenied` and gates only the optional primer. Failing test first, then green. Renamed everywhere (gateway/facade/tests/README/MIGRATION/DECISIONS); spec §3 annotated as superseded.
  - **Guard added — seam boundary:** `seam_boundary_test` now also fails on an `app_tracking_transparency` import outside the seam (was `google_mobile_ads` only); verified it catches a planted violation.
  - **Guard added — pipeline ordering:** the ordering test now snapshots ATT/consent call-counts at each primer, pinning ATT prompt < info update < consent primer < form.
  - Checks 3/4/5/6/8 already held (existing guards). 264 tests green, analyze clean.
- **Non-blocking `AdFlow.initialize()` (audit finding, ADR-032).** `initialize()` awaited `_start()` (consent + network), so on weak internet the caller's first frame was blocked behind a splash (v1's pain). Fixed: build the graph synchronously, set `_instance` synchronously, run `_start()` in the BACKGROUND (errors captured), return immediately (before consent). New `Future<bool> get whenReady` completes when the gate resolves (optional; not required for normal use). Kept the `Future<AdFlow>` return type (low churn; avoids `await_only_futures` at every await site; keeps the fail-fast-as-rejected-future). `_start` returns the gate result and skips the manager/preloads if `dispose()` ran mid-startup. Example drops the `FutureBuilder<AdFlow>` — `main()` awaits (instant) and `runApp`s `HomeScreen` directly. Failing test first (initialize blocked on held consent → timeout), then green; added returns-before-consent / whenReady / no-load-before-gate / gate-closed / a widget-renders-with-consent-pending test; `boot()` + the two ADR-027/028 fakeAsync tests refocused onto `whenReady`. README/MIGRATION/DECISIONS(ADR-032)/SKILL/CHANGELOG updated. **267 tests green, analyze clean; example + root builds green.**
- **Non-blocking on-device verification + adversarial review fixes (ADR-033).**
  - **On-device (iOS sim, forced EEA, fresh install):** HomeScreen rendered behind the *centered* system ATT alert AND the UMP consent card — the app was fully visible under the entire consent/ATT flow (never a spinner); ads loaded only after consenting (all formats `ready`). Non-blocking confirmed end-to-end.
  - **Adversarial multi-agent review** (workflow: 5 finders → per-finding adversarial verify; 7 confirmed, 2 refuted) found and I fixed:
    - **MAJOR (real regression):** on-demand first-frame `banner()`/`native()`/manual loads could fire before `updateRequestConfiguration` (consent gate opens independently of SDK init/config) → untagged/untest-flagged first request (review-fix #5 / COPPA). Fix: `AdGate.canLoad` `await`s a `_configApplied` completer (set after config in `_start`, and on dispose) — config-before-load is now structural for every load path. Fail-first test, then green.
    - **Test gaps:** the `_disposed`-during-startup guard and the `whenReady` error-capture net were correct but untested (a naive dispose test is non-discriminating because controllers self-guard). Added `FakeAdSdk.hasForegroundListener` + `canRequestAdsError` and two tests — each **proven to fail when its guard is removed**, then restored.
    - **Docs:** promoted the non-blocking contract into `initialize`'s + the class `///` dartdoc (was a `//` body comment only); README §3 / MIGRATION §2 now state loads wait for config AND consent; ADR-032 corrected + ADR-033 added; SKILL §6 trap.
  - **272 tests green, analyze clean.**
- **Docs/example polish for the two init modes (no code change).** `example/lib/main.dart` now teaches BOTH modes in one runnable app: `_initSimple()` (UMP-only, no client priming) vs `_initWithExplainer()` (adds `attExplainer`/`consentExplainer` via the existing `navigatorKey`), picked by a top-level `useExplainer` flag (non-`const` so both helpers stay referenced and both flag states `flutter analyze` clean — verified by flipping; example builds on Android). Kept the non-blocking shape (async `main` → `runApp(HomeScreen)`, no `FutureBuilder`), controllers-created-once (ADR-029), and the full all-formats demo. README §3 retargeted into a tight **Quick start** (Step 1 → platform-setup link; Step 2 → non-blocking init + one banner, "never block the first frame", controllers-once) with a short "Add consent + ATT priming" teaser linking to §5, plus the production-config block; the rest already matched the current API (non-blocking, `whenReady`, controllers-once, two modes, `skipConsentPrimerIfAttDenied`).

## In progress
- Nothing. **The explainer-v2 feature is complete: 6 slices shipped + committed, 263 tests green, analyze clean, iOS on-device flow visually verified end-to-end, Android build green.**

## Next (ordered)
- None outstanding for this feature.
- Optional future work (unchanged): extend `test/seam/gma_ad_sdk_test.dart` to rewarded/rewarded-interstitial/app-open/native; a real-device/CI smoke test; before publishing, bump `pubspec.yaml` to a real version and re-run `dart pub publish --dry-run` + `pana` (a new runtime dependency was added, so re-score).

## How to verify the current state
`flutter analyze && flutter test` (root: 263 tests; use `--concurrency=2` if the machine OOM-kills the runner) · `cd example && flutter analyze && flutter build apk --debug` · `dart pub publish --dry-run` · `pana` (was 160/160; re-run after these changes + the new `app_tracking_transparency` dep if publishing). **If `flutter test` throws `Unsupported runtime stages format version. Expected 2, got 1` on a widget test, that's a stale `ink_sparkle.frag` shader cache — `flutter clean && flutter pub get` and re-run (SKILL.md §6), not a real failure.**

## Open questions / assumptions
- `test/seam/gma_ad_sdk_test.dart` covers interstitial + banner only; the same mock-channel pattern applies directly to rewarded/rewarded-interstitial/app-open/native if a future session wants full-format seam coverage — not required, `FakeAdSdk`-level tests already cover their controller logic.
- `FullScreenAdCoordinator`'s `postDismissSuppression` default (1s, in `AppOpenAdManager`) is a judgment call (DECISIONS ADR-026 item #9) — no RESEARCH.md-documented value exists for this; revisit if real-world app-open fill data suggests otherwise.
- `AdFlowBanner`'s adaptive-height estimate (`deviceHeight * 0.15`, clamped 50-90) is grounded in Google's documented bounds (now in RESEARCH.md) but is still an estimate — `placeholderHeight` is the exact override when the real height is known.

## Traps hit this session
- **Explainer-v2 session:** a `capture?.call(show(...))` in a widget test short-circuits argument evaluation when `capture` is null (`?.` guards the whole expression), so the primer never opened — call `show(...)` first, then forward. And a nested `Future<Future<void>>` return type is illegal (`void`-flattening) where `Future<Future<bool>>` compiles — capture the primer future via a `void Function(Future<void>)` callback param. Both appended to SKILL.md §6, plus the "presenter must be context-safe; package never holds a `BuildContext`" trap (ADR-030).
- **Const asserts cannot compare `Duration`s** (`const_eval_type_num`: only `num` operands allowed in const-expression comparisons). A `Duration`-comparing assert compiles until someone `const`-invokes the constructor, then every const call site errors. Validate Durations at use-time instead → SKILL.md §6.
- `AppStateEventNotifier.appStateStream` emits nothing until `startListening()` → appended to SKILL.md §6 (GmaAdSdk handles it lazily).
- `BannerAd.isCollapsible` is `Future<bool>`; inline adaptive height needs post-load `getPlatformAdSize()` → SKILL.md §6.
- `RequestConfiguration` tags are int-encoded (1/0/-1), rating is a String constant → SKILL.md §6.
- `NativeAd.customOptions` is `Map<String, Object>` (non-nullable values) — seam type matches.
- A synchronous check-then-await-then-write is a race (ADR-024); a shared resource needs its own synchronous claim, not a check reached through someone else's async gate; `ValueNotifier`'s setter no-ops (skipping the disposed check) when the new value equals the current one — see SKILL.md §6 for all three, already appended in a prior session.
- **Testing the real `GmaAdSdk` seam requires the plugin's own private test infrastructure pattern**: a fresh `AdInstanceManager` per test (resets ad ids to 0), `setMockMethodCallHandler` on `instanceManager.channel` for outgoing calls, and a hand-reproduced `sendAdEvent` helper (`handlePlatformMessage` + the channel's own `AdMessageCodec`) for simulating incoming `onAdEvent` calls — mirrors the plugin's own `test/ad_containers_test.dart`/`test/banner_ad_test.dart` (reachable in the pub cache, not importable across packages). See `test/seam/gma_ad_sdk_test.dart`.
- **`sdk.loadBanner(spec)` suspends at its own internal awaits before the ad is registered with `instanceManager`** — dispatching a simulated `onAdEvent` immediately after calling `loadBanner` (without an intervening `await pumpEventQueue()`) hits "Ad with id `0` is not available," not because the seam is wrong, but because the TEST raced ahead of Dart's own microtask ordering.
- **Dart's Future error propagation requires the listener attached BEFORE the error, not after**: `await triggerTheError(); await expectLater(future, throwsA(...));` reports an unhandled async error even though the assertion is "correct," because nothing was listening on `future` at the moment it completed. Always do `final expectation = expectLater(future, throwsA(...));` first, trigger the error second, `await expectation` last.
- **Google's anchored adaptive banner height has no pure-width formula** — verified via web search (developers.google.com): 50-90dp, capped at 15% of device height, depends on device/aspect ratio on the native side. Don't try to compute it exactly client-side; a documented-bounds-based estimate is the best achievable without a platform round trip.
- **Adding a default (non-zero) time-based behavior to a shared collaborator (`FullScreenAdCoordinator`) breaks any existing test that does `exit()` then immediately re-`enter()`/`show()` at the same (real or injected) clock instant** — when fixing review finding #7, one pre-existing app-open test asserted the OLD immediate-re-show behavior as correct; had to update it to advance the injected clock past the new suppression window rather than treat the test failure as a regression.
- **A Dart-side `.timeout(Duration)` cannot save you from a native call that blocks the platform thread synchronously** — `.timeout()` needs the isolate's own timer queue to run, and a synchronously-blocked platform thread starves that queue too. Diagnostic tell: query the Dart VM service directly (`GET {vmServiceUri}getIsolate?isolateId=...`) — if that times out too, the whole isolate is wedged, not just your `Future`. **BUT (corrected — see next trap): "isolate wedged by a native platform-thread block" does NOT mean "unfixable from Dart."** The block is *triggered by* specific native calls; changing *which* calls you make, or *when*, can avoid triggering it entirely. Rounds 1–3 of this session wrongly stopped at "unfixable / it's the AVD's Play-Services state." It wasn't.
- **The fix for "the native SDK bootstrap freezes the platform thread" was in OUR call ordering — read the plugin's source to find which thread each call runs on (SKILL.md §5/§6, ADR-028).** `MobileAds.updateRequestConfiguration()` is serviced synchronously on the platform thread and force-bootstraps the Ads-Dynamite settings-manager singleton; `MobileAds.initialize()` bootstraps the same singleton on a background thread. Calling them concurrently (`Future.wait`, as review-fix #5 did) deadlocks the platform thread on a cold device. Sequencing (`await initialize()` then `updateRequestConfiguration()`) fixes it. The meta-lesson: three rounds of black-box symptom-chasing reached the right *mechanism* but a wrong, defeatist *cause*; reading the collaborator's actual Java source in round 4 found the real, Dart-fixable bug in minutes. When a hang looks like it's "below your layer," confirm by reading that layer's source before declaring it unreachable.
- **`ink_sparkle.frag` shader-version test failure is a stale build cache, not a regression** — after many `flutter run` rebuilds an SDK/artifact refresh can leave the Material ripple shader stale, and the first widget test rendering a button ripple throws `Unsupported runtime stages format version. Expected 2, got 1`. `flutter clean && flutter pub get` → green. → SKILL.md §6.

---
### How to resume (read this if you are a new/smaller model)
1. Read, in order: this file → `PLAN.md` → `ARCHITECTURE.md` → `DECISIONS.md` → `RESEARCH.md`. Also load the `ad-flow-builder` skill.
2. Run `flutter analyze && flutter test` — expect clean + 230 passing. (If a widget test throws `ink_sparkle.frag ... Expected 2, got 1`, run `flutter clean && flutter pub get` first — stale shader cache, not a real failure.)
3. Continue from "In progress" → "Next". One small slice at a time; keep the tree green; update this file at the end of every session.
