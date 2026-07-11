# PROGRESS — ad_flow v2

## Current phase
**Phase 4 — Consent (ConsentGateway)** (Phases 2–3 complete).

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
  - ADR-017 (hand-written immutables, no freezed/copyWith), ADR-018 (no runtime appId field)

## In progress
- Nothing mid-slice. **The very next concrete step:** Phase 4 — `lib/src/consent/consent_gateway.dart`: `ConsentGateway` interface + `UmpConsentGateway(AdSdk)` implementing `ensureCanRequestAds({debug})` (info update → form if required → gate check, double-load guard, internal timeout), `isPrivacyOptionsRequired`, `showPrivacyOptions()`, `reset()`. Tests via `FakeAdSdk` consent knobs: non-EEA (gate true, no form), EEA (form then gate), update/form error fallback, privacy-options-required.

## Next (ordered)
1. Phase 4 — ConsentGateway (see ADR-016: pure orchestration over the seam's UMP primitives). Decide the ATT question (see Open questions).
2. Phase 5 — Policies (RetryPolicy, KeyValueStore, FrequencyCapPolicy, AdGate, FullScreenAdCoordinator).
3. Continue PLAN.md phase by phase (6 banner → 7 interstitial → …).

## How to verify the current state
`flutter analyze && flutter test`
Expected: analyze clean, **58 tests passing** (core 6, fake seam 28, gma mappers 8, config 16).

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
