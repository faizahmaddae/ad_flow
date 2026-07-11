# DECISIONS — ad_flow v2 (ADR log)

Architecture Decision Records. Each entry: **context → decision → rationale → consequences.** Settled decisions are not to be relitigated; if you must change one, add a new superseding ADR that references it. Append a new ADR whenever you make a non-obvious choice.

Status legend: `accepted` (agreed with the maintainer / by design), `proposed` (needs confirmation as you build).

---

## ADR-001 — Ground-up rewrite to v2  ·  accepted
**Context.** v1.3.18 is feature-rich and heavily tested but architecturally constrained: all-singleton, static global config, hand-rolled observer, a lifecycle bug, and pinned to `google_mobile_ads ^7.0.0` (two majors behind).
**Decision.** Rewrite from scratch as **v2**, reusing the *battle-tested logic* of v1 (retry timing, the consent-sample flow, test-mode) but not its structure.
**Rationale.** The problems are structural, not cosmetic; a clean architecture is cheaper than incrementally untangling global state.
**Consequences.** A new `lib/` tree; v1 code stays available in git history for reference; published as a new major.

## ADR-002 — Clean v2 public API + MIGRATION.md  ·  accepted
**Context.** The package is used across the maintainer's own apps.
**Decision.** Design the best API without preserving source-compat with v1; document every breaking change in `MIGRATION.md`.
**Rationale.** A clean break with a good guide beats contorting the design for backward-compat.
**Consequences.** Consumer apps update call sites once, guided by `MIGRATION.md`.

## ADR-003 — Target `google_mobile_ads: ^9.0.0`  ·  accepted
**Context.** v9.0.0 is current (2026-06-09); core ad flow is stable 7→9; only the adaptive-banner methods were renamed.
**Decision.** Depend on `^9.0.0`; use `getLargeAnchoredAdaptiveBannerAdSize` / `…WithOrientation`. Raise package env to Flutter ≥ 3.38.1 / Dart ≥ 3.10.0.
**Consequences.** Consumer projects must meet v9's min versions (iOS 13, Android minSdk 24 / compileSdk 36, AGP 8.13.1) and adopt the iOS `UISceneDelegate` lifecycle. Documented in `MIGRATION.md`.

## ADR-004 — Dependency injection over global singletons  ·  accepted
**Decision.** No static/singleton config; `AdFlowConfig` and collaborators are constructed and injected. A convenience accessor may exist but must be backed by an injectable instance.
**Rationale.** v1's static global forced elaborate `reset()` test plumbing and made DI impossible. Injection makes every unit independently testable.
**Consequences.** Tests construct their own graph with fakes; no shared static state to reset between tests.

## ADR-005 — One reactive primitive: ChangeNotifier / ValueListenable  ·  accepted
**Decision.** Ad state is exposed as `ValueListenable<AdLoadState>`; drop v1's hand-rolled `List<VoidCallback>` observer and its duplicate broadcast stream.
**Rationale.** Idiomatic, less code, fewer bugs, integrates with `ValueListenableBuilder`.
**Consequences.** Widgets subscribe via `ValueListenableBuilder`; one notification channel per controller.

## ADR-006 — The SDK seam is the only door to google_mobile_ads  ·  accepted
**Decision.** All plugin calls go through an `AdSdk` interface (`GmaAdSdk` real, `FakeAdSdk` for tests). Nothing else imports `google_mobile_ads` except the seam and the widgets that must host an `AdWidget`.
**Rationale.** Makes everything testable without a device, and keeps the legacy↔Next-Gen native swap invisible to our code.
**Consequences.** A little boilerplate in the seam; huge testability and future-proofing payoff.

## ADR-007 — Foreground detection via AppStateEventNotifier  ·  accepted
**Context.** v1 treated iOS `inactive` AND `paused` as backgrounding, so app-open ads fired after Control Center / permission dialogs / the app-switcher.
**Decision.** Use `AppStateEventNotifier.appStateStream` (the official signal) for foreground-return; never hand-roll off `didChangeAppLifecycleState`.
**Consequences.** Correct warm-start behavior; no false app-open triggers.

## ADR-008 — Exponential backoff + jitter for retries  ·  accepted
**Decision.** `RetryPolicy` = exponential backoff with jitter, a max attempt count, a cooldown, then **auto re-arm**. Keep v1's cancellable-`Timer` approach (not `Future.delayed`).
**Rationale.** v1's linear no-jitter backoff made managers retry in lockstep and never re-armed banner/native after cooldown.
**Consequences.** Fewer thundering-herd retries; loads recover automatically after a cooldown.

## ADR-009 — FrequencyCapPolicy: per-format + global caps  ·  accepted
**Decision.** Per-format time + count caps AND a global cross-format cap, persisted through an injected key-value store.
**Rationale.** v1 had only a per-interstitial time cooldown; nothing stopped an interstitial then an app-open back-to-back.
**Consequences.** Configurable caps in `AdFlowConfig`; a user is never hit by stacked full-screen ads.

## ADR-010 — Next-Gen SDK: opt-in, Android-only, default OFF  ·  accepted
**Context.** Next-Gen is GA on native Android but experimental in Flutter (a build-time `USE_NEXT_GEN_SDK` flag); the Dart API is unchanged. iOS has no Next-Gen.
**Decision.** Build the *capability* and document it as an experimental opt-in (`--dart-define=USE_NEXT_GEN_SDK=true`); keep legacy `play-services-ads` the default; add an example build variant that turns it on. Never enable by default; don't depend on legacy-only native internals.
**Rationale.** The revenue upside (Android) is real, the effort is low (no Dart changes), and keeping it opt-in contains the risk while it's pre-GA.
**Consequences.** README documents the flag + its Android-only, experimental status; nothing in our Dart code assumes which native SDK is active.

## ADR-011 — Manual preloading (no Flutter preload API)  ·  accepted
**Context.** The Flutter plugin has no preload API even in 9.0.0.
**Decision.** "Preload" = load ahead, cache the instance, show later; every full-screen controller reloads the next in `onAdDismissedFullScreenContent` / `onAdFailedToLoad` and keeps one warm.
**Consequences.** Higher show-rate/fill without a native preload API; respect the 4h app-open expiry.

## ADR-012 — Test ads only in code; production IDs via config  ·  accepted
**Decision.** The library never hardcodes a production ad-unit ID; consumers supply per-platform IDs via `AdFlowConfig`. A `testMode` uses Google's official sample IDs. Test-mode is derived from an explicit flag/config, NOT from resolved IDs.
**Rationale.** Prevents accidental invalid-traffic strikes and fixes v1's `isUsingTestAds` false positives.

## ADR-013 — Add rewarded interstitial with mandatory intro/skip  ·  accepted
**Decision.** Implement the missing rewarded-interstitial format, including a built-in intro/announcement screen helper with a skip option.
**Rationale.** v1 had a dead test-ID constant but no implementation; the format is policy-gated on the intro screen.

## ADR-014 — Publish as 2.0.0  ·  accepted
**Decision.** Version the rewrite `2.0.0`; maintain a clear `CHANGELOG.md`; keep the same package name, repo, and pub.dev identity.
**Consequences.** Same publishing pipeline; consumers opt in via a major bump.

## ADR-015 — v1 parked under `legacy/v1/`, excluded from analysis and publish  ·  accepted
**Context.** Phase 2 scaffolds a new `lib/` in the same paths v1 occupied, but PROGRESS requires keeping v1 greppable until its battle-tested logic (retry timing, consent-sample flow, test-mode) is ported. Leaving v1 in `lib/` would collide with the new tree and break `flutter analyze` under gma 9 lints.
**Decision.** `git mv` v1 `lib/`, `test/`, `example/` → `legacy/v1/`; exclude `legacy/**` in `analysis_options.yaml`; add `legacy/` (plus `docs/`, `.claude/`) to `.pubignore`.
**Rationale.** Satisfies both constraints: v1 stays greppable in the working tree for porting, while the package analyzes clean and publishes without it. Git history additionally preserves v1 at tag/commit `c9d95d5` (v1.3.17) / `4ecef71` (v1.3.18).
**Consequences.** Delete `legacy/` once porting is complete (Phase 13/14). `flutter test` no longer runs v1's ~1000 tests — v2 rebuilds coverage phase by phase.

## ADR-016 — Seam refinements: UMP primitives live in AdSdk; view handles build their own widget  ·  accepted
**Context.** ARCHITECTURE's sketch had `ConsentGateway` "wrapping UMP", and banner/native loads "return the plugin object because a real AdWidget must host it". Invariant 8 says only the seam imports `google_mobile_ads`.
**Decision.** (a) `AdSdk` exposes raw UMP one-call wrappers (`requestConsentInfoUpdate`, `canRequestAds`, `loadAndShowConsentFormIfRequired`, `showPrivacyOptionsForm`, statuses, `resetConsent`) as clean `Future`s; `ConsentGateway` (Phase 4) becomes pure orchestration over the seam. (b) `BannerHandle`/`NativeHandle` expose `buildWidget()` — `GmaAdSdk` returns a real `AdWidget`, `FakeAdSdk` a `SizedBox` — instead of leaking the plugin ad object.
**Rationale.** (a) keeps invariant 8 literal (one gma import) and makes ConsentGateway fully testable with `FakeAdSdk`; UMP callbacks are wrapped into Futures exactly once, per the v1 trap. (b) removes the last reason for widgets to import the plugin and lets widget tests pump real trees with fakes.
**Consequences.** `GmaAdSdk` is the single gma import in `lib/` (widgets no longer need one). Fake handles are drivable test doubles shipped in `lib/src/seam/fake_ad_sdk.dart` (whether to export them for consumers' tests is part of ADR-P3).

## ADR-017 — Hand-written immutables; no freezed/build_runner (resolves ADR-P1)  ·  accepted
**Context.** ADR-P1 proposed `freezed` to cut v1's copyWith-sentinel boilerplate.
**Decision.** Hand-write the config/state immutables; add **no** build_runner dependency. Also: **no `copyWith` until a real caller needs one** — v1's boilerplate existed to serve copyWith sentinels; the v2 configs are small consts built once at startup.
**Rationale.** A library forcing build_runner on consumers is a real cost; the config surface is ~10 small classes with no unions. Prefer deleting to adding.
**Consequences.** If copyWith becomes necessary (e.g. runtime config swaps), add it narrowly to the classes that need it, or supersede this ADR.

## ADR-018 — No `appId` field in AdFlowConfig  ·  accepted
**Context.** ARCHITECTURE's sketch had `required this.appId` "(or null → set in manifest/plist)".
**Decision.** Drop the field. The AdMob application ID cannot be set at runtime by the Flutter plugin — it is read from `AndroidManifest.xml` (`com.google.android.gms.ads.APPLICATION_ID`) and `Info.plist` (`GADApplicationIdentifier`) only.
**Rationale.** A config field the SDK never reads is a lie that would burn integration time.
**Consequences.** README/MIGRATION document the manifest/plist requirement prominently. `AdFlowConfig` carries ad *unit* IDs only.

## ADR-019 — ATT handled by UMP; no `app_tracking_transparency` dependency  ·  accepted
**Context.** v1 depended on `app_tracking_transparency` and sequenced the ATT prompt itself. RESEARCH §5: UMP can present the ATT explainer and the system prompt (IDFA message configured in the AdMob console), and double-prompting must be avoided.
**Decision.** v2 has no direct ATT dependency. `UmpConsentGateway` lets UMP drive ATT; the README documents: configure the IDFA message in AdMob's Privacy & messaging, add `NSUserTrackingUsageDescription` to `Info.plist`, and do NOT also call `app_tracking_transparency` yourself.
**Rationale.** One consent surface, one prompt sequence, one less dependency; matches Google's current guidance.
**Consequences.** Apps wanting a custom pre-ATT explainer outside UMP must implement it themselves before `AdFlow.initialize`. Timeout design: only the info-update step has a timeout (30s default) — the form step never times out because the user may legitimately keep it open.

## ADR-020 — Consent flow degrades to `canRequestAds()` on failure, surfacing `lastError`  ·  accepted
**Context.** v1 swallowed consent errors with `catchError((_){})` (weakness #12); Google's sample continues after "consent gathering failed" because a previously-consented (or not-required) user should still get ads offline.
**Decision.** `ensureCanRequestAds()` never throws: update/form failures and timeouts are captured as a typed `AdFlowError` on `ConsentGateway.lastError`, and the method returns the SDK's own `canRequestAds()` answer. Concurrent calls join the in-flight run (double-load guard).
**Consequences.** Callers branch on the bool; diagnostics read `lastError`. `showPrivacyOptions()` DOES rethrow — a user-initiated surface should show its failure.

## ADR-021 — Interstitial user-action pacing activates on first `recordUserAction()`  ·  accepted
**Context.** AdMob guidance: ≤ 1 interstitial per 2 user actions. But enforcing `minActionsBetween` (default 2) unconditionally would silently block every interstitial in apps that never call `recordUserAction()` — a trap for integrators.
**Decision.** Action pacing is dormant until the app's first `recordUserAction()` call. Untracked apps are paced by frequency caps alone; once the app reports actions, `show()` requires `minActionsBetween` actions since the last show (counter resets on show).
**Rationale.** Opt-in enforcement can't brick monetization by omission, yet gives policy-conscious apps the exact guardrail.
**Consequences.** README must tell integrators to call `recordUserAction()` at natural breaks to get action pacing.

## ADR-022 — Public surface: zero google_mobile_ads re-exports; FakeAdSdk ships via `ad_flow_testing.dart` (resolves ADR-P3)  ·  accepted
**Context.** ADR-P3 proposed a minimal curated re-export of plugin types. As built, the seam's own value types (`FixedBannerSize`, `AdPaidEvent`, `RewardEarned`, `MaxContentRating`, …) cover the entire public API — no plugin type leaks through any signature.
**Decision.** The main barrel re-exports **nothing** from `google_mobile_ads`. Consumers needing plugin internals (mediation extras, custom `AdRequest`s) import the plugin directly. Test doubles (`FakeAdSdk`, fake handles) ship in a separate `package:ad_flow/ad_flow_testing.dart` barrel so consumers can unit-test their integration; `InMemoryKeyValueStore` is already public via the policy exports.
**Rationale.** Re-exporting plugin types couples consumers to plugin majors for no gain; a clean seam plus an explicit escape hatch is strictly simpler. Shipping the fakes makes downstream apps testable the same way ad_flow itself is.
**Consequences.** MIGRATION documents "import google_mobile_ads directly if you need more" (table row already present). Fake knobs become semi-public API — additive changes only.

## ADR-023 — Rewarded interstitial intro presenter is injected at `AdFlow.initialize`  ·  accepted
**Context.** The intro screen needs a `BuildContext` at show time; the facade has none.
**Decision.** `AdFlow.initialize` takes a `rewardedIntroPresenter` (e.g. `(content) => RewardedIntroScreen.show(navigatorKey.currentContext!, content)`) and **fails fast with `invalidConfig`** when the rewarded interstitial slot is configured without one.
**Rationale.** Failing at init is discoverable; failing at first show in production is not. Injection keeps the controller free of navigation concerns and testable.
**Consequences.** README shows the navigatorKey pattern. Apps with custom intro UIs pass their own presenter (must keep a skip path — policy).

---

## Proposed / to confirm while building
- ~~**ADR-P1 — Immutability codegen (`freezed`).**~~ Resolved by ADR-017 (hand-written, no codegen).
- ~~**ADR-P2 — Persistence dependency for frequency caps.**~~ **Confirmed at Phase 5:** `shared_preferences` (`SharedPreferencesAsync`, keys namespaced `ad_flow.`) behind the `KeyValueStore` interface; `InMemoryKeyValueStore` for tests. Design note: the last-impression timestamp is persisted separately from the pruned hourly history so `minGap` values longer than the 1h history window still work; session counts are deliberately in-memory only.
- ~~**ADR-P3 — Minimum public surface.**~~ Resolved by ADR-022 (zero plugin re-exports; testing barrel for fakes).
