# PROGRESS — ad_flow

The full history (v2 → v5, phases 1–33) is in
[archive/PROGRESS_v2-v5.md](archive/PROGRESS_v2-v5.md); the original v2 build
plan in [archive/PLAN_v2.md](archive/PLAN_v2.md). The review that drove 5.5.0
and 6.0.0 is [REVIEW_2026-11.md](REVIEW_2026-11.md).

## Current phase

**Phase 34 — 6.0.0, the simplification release (2026-11-18)** — **shipped and
published** (ADR-083…087). 5.5.0: PR #19 squash-merged as `8416e87`, tag
`v5.5.0`, on pub.dev. 6.0.0: PR #20 squash-merged as `51015be`, tag `v6.0.0`,
on pub.dev (latest). Both via the tag-triggered `publish.yml`, after main's own
CI on each merge commit was green (ci, pana, example-build, example-build-ios).

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
    test runs (with both imports — the snippet showed only the testing one
    until the final review, item 18). `dart doc --dry-run`: the only warning left is the
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

16. Device check, iOS simulator (iPhone 18 Pro, iOS 27, debug, Google's
    sample units), all as designed:
    - first install: home at once, no launch ad (no earlier consent);
      outside the EU, UMP's IDFA message then Apple's prompt;
    - every format loads; the native validator reports no issues; paid
      events arrive; AdMob refreshes the banner server-side;
    - `show()` completes on the close (the SnackBar came ~12 s after the
      dispatch, longer than a SnackBar lives) and the next ad is preloaded
      at once; first interstitial tap → `userActionPacing` (2 actions);
      rewarded and RI grant the reward; RI intro first, skip →
      `introSkipped`; an RI 8 s after the rewarded closed →
      `frequencyCapped` (15 s global gap from the close, ADR-040);
    - app open on a warm return; a second return within 4 min →
      `frequencyCapped`; cold relaunch with consent stored → the launch ad
      over the loading screen, home after the close;
    - EU (debug geography): the GDPR form is the first screen, Apple's
      prompt only after the answer, no second tracking question; the
      privacy-settings button shows; Remove-Ads blocks every slot and
      removes the banner and the native card.
    Not covered: the client-driven `attExplainer` primer on a device —
    Google's sample app ID has a console IDFA message, so UMP asks itself
    and ad_flow (correctly) skips its own step; needs a real app ID without
    that message. Android not run on a device/emulator (the APK builds).
    Flutter 3.50 migrated the example's iOS target to 15.0 (Flutter ≥ 3.47
    needs iOS 15) — committed with the example.

17. Device check, Android emulator (Pixel 10 Pro, Android 17, profile build,
    Google's sample units): every format, `show()` completing on the close,
    action pacing, rewarded and RI rewards, RI intro first, app open on a warm
    return and the 4-min cap, the EU GDPR form first, privacy settings
    reopening the form, and a consent change dropping and reloading the ads —
    all as designed. The startup gate showed in the log (loads waited for the
    request configuration, then went out). One finding, fixed (ADR-087): a
    failed launch load no longer holds the loading screen for the rest of
    `maxWait`. The cold-start launch ad missed the 3 s wait on this emulator
    (ad ready at ~4 s); the default stays 3 s.

18. Final independent review of items 11–17 (8 commits): no correctness bug
    in the changed code. Fixed what it found:
    - a per-placement `config:` skipped validation and an ID-less slot got a
      sample ad in debug but an empty slot in release (ADR-085 addendum);
    - `public_api_test`'s parser could miss declaration forms (public
      extensions, generic or record-returning functions, nested exports) —
      now strict: every top-level line must be read or the test fails, with
      its own parser tests;
    - docs: README §7 / testing-library snippet needed both imports;
      `presentationTimeout` was named on a class apps cannot import;
      `expired` left out native; the launch-wait rationale was overstated;
    - older: disposing during the launch wait now ends it (ADR-087 addendum).

## Next (ordered)

1. Device check left: the client-driven `attExplainer` primer with a real
   app ID that has no console IDFA message (iOS item 16, Android item 17).
2. Apps still on `^5.x` get the ATT-order fix with a plain `pub upgrade`
   (5.5.0); 6.0 needs the migration below.
3. Migrate the nine apps (one session per app, in its own repo), deleting their
   wrappers: wait-for-close adapters, `FullScreenPacing`, `PrivacyOptionsMirror`,
   nahjal's `ConsentThenAttGateway` + TCF channel, launch-wait code, debug
   placeholder IDs, and the `consentExplainer` argument (novels, jadval,
   nahjal_balagha, dehkhoda). The README's "Set up with AI" prompt is written for this.

## How to verify

`dart format --output=none --set-exit-if-changed .` && `flutter analyze` &&
`flutter test` (≈630 tests) && `cd example && flutter analyze && flutter test`
&& `dart pub publish --dry-run`.

## Traps hit this phase

- The maintainer's Android emulator has ~700 MB free: the 155 MB debug APK
  fails with `INSTALL_FAILED_INSUFFICIENT_STORAGE`. Use
  `flutter build apk --profile --target-platform android-arm64` (~31 MB; the
  example's IDs are Google's sample units, so profile mode still serves test
  ads), and uninstall the example afterwards.

- Google's sample app ID has a console IDFA message, so on a device UMP asks
  ATT itself and the client-driven `attExplainer` step is (correctly)
  skipped — that path cannot be exercised with sample IDs.
- In test mode Google's native ad validator pops up again after every
  full-screen ad: Google's overlay, not ours.

- Since 6.0 `show()` completes on the CLOSE: a test that `await`s a successful
  show before simulating the dismissal hangs. Use `dispatch()` from
  `test/support/show.dart` to assert the dispatch decision, or start the show,
  pump, simulate the close, then await.
- `kDebugMode` is true under `flutter test`, so a config without `testMode`
  resolves Google's sample IDs in tests; tests that assert configured IDs set
  `testMode: false`.
