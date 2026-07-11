# PROGRESS — ad_flow v2

## Current phase
**Phase 3 — Config** (Phase 2 complete).

## Done
- Phase 1 — Planning artifacts (committed `4e4132e`).
- Phase 2 — Scaffold + SDK seam ✅
  - v1 parked under `legacy/v1/` (ADR-015); pubspec → `google_mobile_ads: ^9.0.0` (resolves 9.0.0), env Flutter ≥ 3.38.1 / Dart ^3.10.0, version 2.0.0-dev.1; lint set per PLAN (`0a152ff`)
  - `core/`: `AdFlowError` (typed, throwable) + sealed `AdLoadState` (`18e907d`)
  - `seam/`: `AdSdk` interface + seam value types + drivable `FakeAdSdk` (`e7cf7d0`)
  - `seam/gma_ad_sdk.dart`: real impl — every symbol grep-verified against the pub-cache 9.0.0 source; pure mappers unit-tested; barrel exports core + seam (this commit)

## In progress
- Nothing mid-slice. **The very next concrete step:** Phase 3 — create `lib/src/config/ad_flow_config.dart` (+ `ad_platform.dart`): `AdFlowConfig`, per-format configs, `PlatformAdUnitId`, `FrequencyCap`, `RetryConfig`, `AdFlowConfig.test()` with Google sample IDs, explicit `testMode` flag. Tests: id resolution per platform, test-mode from flag not ids.

## Next (ordered)
1. Phase 3 — Config (+ tests). ADR-P1 (freezed?) must be decided here: recommendation is **hand-written immutables** (no build_runner dep for a library); record final call in DECISIONS.
2. Phase 4 — ConsentGateway as pure orchestration over the seam's UMP primitives (see ADR-016); fake-UMP tests via `FakeAdSdk` consent knobs.
3. Phase 5 — Policies (RetryPolicy, KeyValueStore, FrequencyCapPolicy, AdGate, FullScreenAdCoordinator).
4. Continue PLAN.md phase by phase (6 banner → 7 interstitial → …).

## How to verify the current state
`flutter analyze && flutter test`
Expected: analyze clean, **42 tests passing** (core 6, fake seam 28 incl. 1 widget test, gma mappers 8 groups).

## Open questions / assumptions
- ADR-P1 (freezed?) — decide at Phase 3 start. ADR-P2 (shared_preferences behind KeyValueStore) — dependency already kept in pubspec. ADR-P3 (public re-export list; whether `FakeAdSdk` ships for consumers' tests) — Phase 11.
- `app_tracking_transparency` was **dropped** from pubspec: RESEARCH §5 says UMP can present the ATT explainer + system prompt itself. Phase 4 must confirm ConsentGateway needs no direct ATT dependency; if it does, re-add and route through the seam.
- Seam contract refinements vs the ARCHITECTURE sketch are recorded in ADR-016 (UMP primitives in `AdSdk`; `buildWidget()` on view handles). ARCHITECTURE.md's sketch was NOT rewritten — treat ADR-016 as the authoritative delta.
- `FakeAdSdk.enforceConsentGate` (default off) is a tripwire for invariant 1 — controller tests from Phase 6 on should turn it on.
- `GmaAdSdk`'s adaptive-size resolution and load paths hit platform channels — not unit-testable without channel mocks; pure mappers ARE tested. Consider channel-mock tests in Phase 6 if worth it.

## Traps hit this session
- `AppStateEventNotifier.appStateStream` emits nothing until `startListening()` → appended to SKILL.md §6 (GmaAdSdk handles it lazily).
- `BannerAd.isCollapsible` is `Future<bool>`; inline adaptive height needs post-load `getPlatformAdSize()` → SKILL.md §6.
- `RequestConfiguration` tags are int-encoded (1/0/-1), rating is a String constant → SKILL.md §6.
- `NativeAd.customOptions` is `Map<String, Object>` (non-nullable values) — seam type matches.

---
### How to resume (read this if you are a new/smaller model)
1. Read, in order: this file → `PLAN.md` → `ARCHITECTURE.md` → `DECISIONS.md` → `RESEARCH.md`. Also load the `ad-flow-builder` skill.
2. Run `flutter analyze && flutter test` — expect clean + 42 passing.
3. Continue from "In progress" → "Next". One small slice at a time; keep the tree green; update this file at the end of every session.
