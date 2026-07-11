# PROGRESS — ad_flow v2

## Current phase
**Phase 14 — Final verification** (Phases 2–13 complete).

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

## In progress
- Nothing mid-slice. **The very next concrete step:** Phase 14 — final verification: root analyze+test, example analyze+builds, `dart pub publish --dry-run` (note: pubspec still says `2.0.0-dev.1`; bump to `2.0.0` only when actually publishing), pana if available, self-review every ARCHITECTURE invariant + RESEARCH §6 policy item against the code/tests, and decide whether `legacy/` porting is complete (retry timing ✓ ported into RetryConfig defaults, consent-sample flow ✓ ConsentGateway, test-mode ✓ ADR-012 — recommend deleting `legacy/` or keeping one release cycle).

## Next (ordered)
1. Phase 14 — Final verification + publish-readiness.

## How to verify the current state
`flutter analyze && flutter test` (root: 186 tests) · `cd example && flutter analyze && flutter build apk --debug`

## Open questions / assumptions
- ADR-P2 (shared_preferences behind KeyValueStore) — dependency already kept in pubspec; confirm at Phase 5. ADR-P3 (public re-export list; whether `FakeAdSdk` ships for consumers' tests) — Phase 11.
- `RewardIntroContent` / `ServerSideVerification` are config-level placeholders; Phase 8 wires SSV through the seam (the seam does not carry SSV yet — extend `AdSdk.loadRewarded`/`loadRewardedInterstitial` or the handles when implementing).
- `BannerConfig.minRefresh` has NO constructor assert (Duration comparisons are illegal in const asserts — see traps); the Phase 6 controller must clamp values below 30s.
- `app_tracking_transparency` was **dropped** from pubspec: RESEARCH §5 says UMP can present the ATT explainer + system prompt itself. Phase 4 must confirm ConsentGateway needs no direct ATT dependency; if it does, re-add and route through the seam.
- Seam contract refinements vs the ARCHITECTURE sketch are recorded in ADR-016 (UMP primitives in `AdSdk`; `buildWidget()` on view handles). ARCHITECTURE.md's sketch was NOT rewritten — treat ADR-016 as the authoritative delta.
- `FakeAdSdk.enforceConsentGate` (default off) is a tripwire for invariant 1 — controller tests from Phase 6 on should turn it on.
- `GmaAdSdk`'s adaptive-size resolution and load paths hit platform channels — not unit-testable without channel mocks; pure mappers ARE tested. Consider channel-mock tests in Phase 6 if worth it.

## Traps hit this session
- **Const asserts cannot compare `Duration`s** (`const_eval_type_num`: only `num` operands allowed in const-expression comparisons). A `Duration`-comparing assert compiles until someone `const`-invokes the constructor, then every const call site errors. Validate Durations at use-time instead → SKILL.md §6.
- `AppStateEventNotifier.appStateStream` emits nothing until `startListening()` → appended to SKILL.md §6 (GmaAdSdk handles it lazily).
- `BannerAd.isCollapsible` is `Future<bool>`; inline adaptive height needs post-load `getPlatformAdSize()` → SKILL.md §6.
- `RequestConfiguration` tags are int-encoded (1/0/-1), rating is a String constant → SKILL.md §6.
- `NativeAd.customOptions` is `Map<String, Object>` (non-nullable values) — seam type matches.

---
### How to resume (read this if you are a new/smaller model)
1. Read, in order: this file → `PLAN.md` → `ARCHITECTURE.md` → `DECISIONS.md` → `RESEARCH.md`. Also load the `ad-flow-builder` skill.
2. Run `flutter analyze && flutter test` — expect clean + 42 passing.
3. Continue from "In progress" → "Next". One small slice at a time; keep the tree green; update this file at the end of every session.
