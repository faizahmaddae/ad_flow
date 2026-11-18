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

9. CI on PR #19 broke when CI moved to Flutter 3.50 (`2011fad` on the 5.5.0
   branch, pushed): targeted ignores on the deprecated `material.dart`
   imports; the example's Android build now matches the 3.50 template
   (Gradle 9.5.0, AGP 9.3.1, Kotlin 2.4.20). The v6 branch is rebased on top
   of it, and its example now builds locally too (`flutter build apk --debug`,
   2026-11-18). If a build fails at once with "Cannot lock execution history
   cache … already locked by this process", a Gradle daemon from an earlier
   aborted build holds the lock: `cd example/android && ./gradlew --stop`.

10. Independent review (fresh agent) before release: 3 should-fix issues and
    several nits, all fixed (ADR-083 addendum): presentation-only show
    timeout, expired-ad self-heal, `showAtLaunch` no-wait on Remove-Ads /
    dispose-safe, interface `canShow`, per-platform test-ID resolution,
    implementer notes, stale comments.

11. Documentation pass: every snippet in `doc/NATIVE_ADS_SETUP.md` and
    `doc/MEDIATION_SETUP.md` compiles against the 6.0 API, and README §7's
    test runs as written. `dart doc --dry-run`: the only warning left is the
    README checklist's `[ ]` (GitHub task-list syntax, harmless). Fixed:
    2 unresolved references, `AdBlockReason.expired` (all full-screen formats,
    not only app open), `AppOpenAdController` (points at `showAtLaunch`),
    `AdFlowErrorKind.timeout`, `TestAdUnitIds` wording; `banner()`/`native()`
    and both widgets now document that a slot with no ID for the running
    platform throws `invalidConfig` (README, CHANGELOG and MIGRATION say so
    too); the library doc has a quick start. `pana --no-warning .`: 160/160.

12. Public surface cut (review F7, ADR-084): `ad_flow.dart` exports 71 types +
    4 helpers (was 100), everything else a test double needs is in
    `ad_flow_testing.dart`. Checked against the nine apps first — nothing they
    use moved. `test/architecture/public_api_test.dart` pins the list.

13. Docs reset (review Phase 4): `DECISIONS.md` is now an index of
    ADR-001…083 (full text in `archive/DECISIONS_v2-v6.md`) plus new records
    from ADR-084; the stale v2 files (MASTER_PROMPT, START_HERE, specs, old
    audits) moved to `archive/`. The review's plan now carries a status line
    per phase.

14. Placements without a slot render nothing (ADR-085, Faiz left the call to
    Claude): `AdFlowBanner(adFlow:)` / `AdFlowNativeAd(adFlow:)` collapse to
    `SizedBox.shrink()` where their slot has no config or no ID for the
    platform (debug prints why) instead of throwing in `initState`.

15. The consent primer is gone (ADR-086, Faiz left the call to Claude): with
    ATT after GDPR it made four privacy screens in a row for EU iOS users, and
    an App Store reviewer read it as asking twice. The ATT primer stays. The
    public API is 68 types + 4 helpers now.

## Next (ordered)

1. Faiz: merge PR #19 (5.5.0) and tag `v5.5.0` — the App Store fix.
2. Rebase `claude/ad-flow-v6` onto main after #19 merges
   (`git rebase --onto origin/main <last 5.5.0 commit>`), open the 6.0.0 PR.
3. Device check of the example on Android + iOS (show-and-wait, launch ad,
   ATT order) — not done yet; unit tests only.
4. Migrate the nine apps (one session per app, in its own repo), deleting their
   wrappers: wait-for-close adapters, `FullScreenPacing`, `PrivacyOptionsMirror`,
   nahjal's `ConsentThenAttGateway` + TCF channel, launch-wait code, debug
   placeholder IDs, and the `consentExplainer` argument (novels, jadval,
   nahjal_balagha, dehkhoda). The README's "Set up with AI" prompt is written for this.

## How to verify

`dart format --output=none --set-exit-if-changed .` && `flutter analyze` &&
`flutter test` (≈630 tests) && `cd example && flutter analyze && flutter test`
&& `dart pub publish --dry-run`.

## Traps hit this phase

- Since 6.0 `show()` completes on the CLOSE: a test that `await`s a successful
  show before simulating the dismissal hangs. Use `dispatch()` from
  `test/support/show.dart` to assert the dispatch decision, or start the show,
  pump, simulate the close, then await.
- `kDebugMode` is true under `flutter test`, so a config without `testMode`
  resolves Google's sample IDs in tests; tests that assert configured IDs set
  `testMode: false`.
