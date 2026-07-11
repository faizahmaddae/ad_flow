# PROGRESS — ad_flow v2

## Current phase
**Phase 2 — Scaffold + SDK seam** (Phase 1 pre-authored and shipped in this bundle).

## Done
- Phase 1 — Planning artifacts (pre-authored, not yet committed in the repo):
  - `docs/ad_flow_v2/RESEARCH.md`, `DECISIONS.md`, `ARCHITECTURE.md`, `PLAN.md`, `MIGRATION.md`, this `PROGRESS.md`
  - `.claude/skills/ad-flow-builder/SKILL.md`
  - `docs/ad_flow_v2/MASTER_PROMPT.md` (the original task brief, for reference)

## In progress
- Nothing in code yet. **The very next concrete step:** create the v2 `lib/` skeleton per `ARCHITECTURE.md` and define the `AdSdk` seam interface + `FakeAdSdk`, then bump `pubspec.yaml` to `google_mobile_ads: ^9.0.0` (env Flutter ≥ 3.38.1 / Dart ≥ 3.10.0).

## Next (ordered)
1. Commit the planning docs (`docs: add v2 planning artifacts + builder skill`).
2. Phase 2: scaffold `lib/` layout, `analysis_options.yaml`, `AdSdk` + `GmaAdSdk` + `FakeAdSdk`, barrel export. Get a trivial seam test green.
3. Phase 3: `AdFlowConfig` + per-format configs (+ tests).
4. Continue through PLAN.md phase by phase.

## How to verify the current state
Repo has no v2 code yet — the baseline to establish in Phase 2 is: `flutter pub get` succeeds on `google_mobile_ads: ^9.0.0`, then `flutter analyze` clean and `flutter test` green on the scaffold. Old v1 `lib/` may still be present for reference; do not delete it until its logic has been ported (retry timing, consent-sample flow, test-mode).

## Open questions / assumptions
- ADR-P1 (freezed?), ADR-P2 (KeyValueStore persistence), ADR-P3 (minimal re-export list) are marked *proposed* in DECISIONS.md — resolve them as you reach the relevant phase and record the final call there.
- The maintainer chose: ground-up rewrite · clean v2 API + MIGRATION · Next-Gen as opt-in/default-off. Do not relitigate these (DECISIONS ADR-001, 002, 010).

## Traps hit this session
- None yet (fresh start). Append new traps here **and** to `SKILL.md` Section 6 as you hit them.

---
### How to resume (read this if you are a new/smaller model)
1. Read, in order: this file → `PLAN.md` → `ARCHITECTURE.md` → `DECISIONS.md` → `RESEARCH.md`. Also load the `ad-flow-builder` skill.
2. Confirm/establish the green baseline (see "How to verify" above).
3. Continue from "In progress" → "Next". Work one small slice at a time; keep the tree green; update this file at the end of every session.
