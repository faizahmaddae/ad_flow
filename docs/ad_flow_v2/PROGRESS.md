# PROGRESS — ad_flow

The full history (v2 → v5, phases 1–33) is in
[archive/PROGRESS_v2-v5.md](archive/PROGRESS_v2-v5.md); the original v2 build
plan in [archive/PLAN_v2.md](archive/PLAN_v2.md). The review that drove 5.5.0
and 6.0.0 is [REVIEW_2026-11.md](REVIEW_2026-11.md).

## Current phase

**Phase 34 — 6.0.0, the simplification release (2026-11-18)** — implemented on
branch `claude/ad-flow-v6` (stacked on `claude/ads-package-review-a0fe65`,
5.5.0, PR #19). Not released: no v6 PR yet, no tag. ADR-083.

Done (one commit each, tree green after each):

1. Removed `forwardConsent` / `MediationConsentFailurePolicy` /
   `RequestConfigFailurePolicy` — startup is one pipeline again.
2. Removed runtime SSV (`setServerSideVerification`, the finalize hook).
3. Removed client-side banner refresh (`minRefresh`, `revision`) and
   `setBlockingViewAdVisible`.
4. `show()` completes when the ad closes → `AdShowResult`;
   `showAtLaunch(maxWait:)` waits for the launch ad; `triggerMode` →
   `showOnResume`; app-open preloads at startup.
5. `canShow` hint (`FrequencyCapPolicy.allowsNow`); nullable slot getters.
6. Test ads automatic in debug (`testMode` null = `kDebugMode`); IDs optional
   in test mode; `AdFlowConfig.test()` removed.
7. Policy collaborators moved to `ad_flow_testing.dart`.
8. Docs: README rewritten (845 → ~330 lines), CHANGELOG/MIGRATION 6.0.0,
   MEDIATION_SETUP, this file, CLAUDE.md, SKILL §0/§6, ADR-083; version 6.0.0.

## Next (ordered)

1. Faiz: merge PR #19 (5.5.0) and tag `v5.5.0` — the App Store fix.
2. Rebase `claude/ad-flow-v6` onto main after #19 merges
   (`git rebase --onto origin/main <last 5.5.0 commit>`), open the 6.0.0 PR.
3. Device check of the example on Android + iOS (show-and-wait, launch ad,
   ATT order) — not done yet; unit tests only.
4. Migrate the nine apps (one session per app, in its own repo), deleting their
   wrappers: wait-for-close adapters, `FullScreenPacing`, `PrivacyOptionsMirror`,
   nahjal's `ConsentThenAttGateway` + TCF channel, launch-wait code, debug
   placeholder IDs. The README's "Set up with AI" prompt is written for this.

## How to verify

`dart format --output=none --set-exit-if-changed .` && `flutter analyze` &&
`flutter test` (≈620 tests) && `cd example && flutter analyze && flutter test`
&& `dart pub publish --dry-run`.

## Traps hit this phase

- Since 6.0 `show()` completes on the CLOSE: a test that `await`s a successful
  show before simulating the dismissal hangs. Use `dispatch()` from
  `test/support/show.dart` to assert the dispatch decision, or start the show,
  pump, simulate the close, then await.
- `kDebugMode` is true under `flutter test`, so a config without `testMode`
  resolves Google's sample IDs in tests; tests that assert configured IDs set
  `testMode: false`.
