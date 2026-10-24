# START HERE — ad_flow v2 starter bundle

This bundle pre-authors all the "expensive thinking" artifacts so the coding model (Fable 5) can skip straight to implementation (Phase 2) instead of spending its weekly capacity on planning.

## What's in this bundle
```
.claude/skills/ad-flow-builder/SKILL.md      ← how every model should work here (Claude Code auto-discovers it)
docs/ad_flow_v2/RESEARCH.md                  ← verified SDK/policy facts (ground truth)
docs/ad_flow_v2/DECISIONS.md                 ← architecture decisions (ADR log)
docs/ad_flow_v2/ARCHITECTURE.md              ← target architecture + concrete Dart API sketch
docs/ad_flow_v2/PLAN.md                      ← phased plan with acceptance criteria
docs/ad_flow_v2/MIGRATION.md                 ← v1 → v2 migration guide
docs/ad_flow_v2/PROGRESS.md                  ← handoff log (Phase 1 done → start at Phase 2)
docs/ad_flow_v2/MASTER_PROMPT.md             ← the full original task brief (for reference)
```

## Install (3 steps)

**1) Clone the repo and create a branch** (don't work on `main`):
```bash
git clone https://github.com/faizahmaddae/ad_flow.git
cd ad_flow
git checkout -b v2
```

**2) Copy this bundle's contents into the repo root.** The `.claude/` and `docs/` folders drop straight into place. If you extract the zip at the repo root it merges automatically. Note: `.claude` is a hidden folder.

**3) Open the repo in Claude Code with Fable 5.** Because the planning is already done, do NOT paste the long master prompt again — send this short kickoff message instead:

```
Load the ad-flow-builder skill. Then read docs/ad_flow_v2/PROGRESS.md, PLAN.md,
ARCHITECTURE.md, DECISIONS.md, and RESEARCH.md. Phase 1 (planning artifacts) is
already written in this bundle — do NOT redo it. First commit the planning docs,
then start Phase 2 (scaffold lib/ + the AdSdk seam) and proceed one small slice at
a time, keeping `flutter analyze` clean and `flutter test` green. Update PROGRESS.md
at the end of every session. Keep all code and docs in English.
```

To let Fable 5 run without pausing, add: `Run autonomously through the phases; don't pause for confirmation.`

## When Fable 5 hits its weekly limit
Hand off to the next model (Sonnet 5 or Opus) with just this:
```
Load the ad-flow-builder skill and read docs/ad_flow_v2/PROGRESS.md, then continue
the plan from where it left off. One small slice at a time; keep the tree green.
```
The skill + PROGRESS.md steer the rest and keep the quality consistent.

## Reminders
- **Don't delete the v1 code at the start** — its battle-tested logic (retry, consent flow, test-mode) is reference material; git keeps it regardless.
- **Prerequisite:** Flutter ≥ 3.38.1 (required by `google_mobile_ads` 9). Check with `flutter --version`.
- **app-ads.txt:** remember to verify it in your publisher settings (required since 2025 for full ad serving).
- You can delete this `START_HERE` file after reading — it's not part of the package output.
