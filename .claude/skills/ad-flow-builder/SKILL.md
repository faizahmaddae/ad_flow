---
name: ad-flow-builder
description: Operating method for building and maintaining the ad_flow v2 Flutter AdMob package. Use this whenever ANY model (Fable 5, Sonnet 5, Opus, or a smaller model) works on ad_flow. It teaches HOW to work here — research-first, verify-by-running, isolate layers, ship small verifiable slices, and hand off cleanly — so that a smaller/cheaper model produces the same quality as a larger one, and so work can be handed between models without losing quality. Read this together with docs/ad_flow_v2/RESEARCH.md, DECISIONS.md, ARCHITECTURE.md, PLAN.md, and PROGRESS.md before writing any code.
---

# ad_flow builder — how to work here

`ad_flow` is a Flutter package that wraps `google_mobile_ads` (AdMob) into a clean, policy-compliant, revenue-optimized, easy-to-drop-in ad layer used across many of the maintainer's apps. This file is the operating manual. It is intentionally about **method, not facts** — the facts live in `docs/ad_flow_v2/RESEARCH.md`. Follow this method and a smaller model will produce the same quality as a larger one.

The prime directive: **the scarce, expensive resource is high-quality thinking. Spend it on the plan, the decisions, the architecture contract, and this skill — and capture all of it in files — so that whoever works next (possibly a smaller/cheaper model, possibly you with no memory of today) can continue at full quality.**

---

## 0. Orient before you touch anything (every session, no exceptions)

Before writing or changing a single line of code, read these files in this order:

1. `docs/ad_flow_v2/PROGRESS.md` — where we are, what's in progress, the exact next step.
2. `docs/ad_flow_v2/PLAN.md` — the phased plan and acceptance criteria.
3. `docs/ad_flow_v2/ARCHITECTURE.md` — the target architecture and the public-API contract you must implement to.
4. `docs/ad_flow_v2/DECISIONS.md` — why things are the way they are (don't relitigate settled decisions).
5. `docs/ad_flow_v2/RESEARCH.md` — ground-truth facts about `google_mobile_ads` 9.x, UMP, and AdMob policy.

If these files do not exist yet, you are at Phase 1: create them first (the master task prompt describes their contents). **Never skip orientation to "save time" — it is what makes a handoff safe.**

Precedence when they seem to conflict: **PROGRESS/PLAN** decide *what to do next*; **DECISIONS/ARCHITECTURE** decide *how*; **RESEARCH** decides *the facts*. If a real conflict exists, fix the docs first, then code.

---

## 1. The method

**Research-first — but don't re-research.** `RESEARCH.md` already contains the verified SDK/policy knowledge. Trust it. Go to the web only for something genuinely not covered there; when you do, **append what you learned back to `RESEARCH.md`** so the next worker inherits it instead of rediscovering it. Re-researching what's already written is the #1 way to waste scarce capacity.

**Isolate layers.** Build and change ONE layer at a time. The layers, bottom-up, are: **SDK seam → config → consent → policies → per-format controllers → lifecycle → facade → widgets.** A layer may depend only on the layers below it, and only through their interfaces. This is exactly what lets a smaller model work safely on one layer without holding the whole system in its head. If you find yourself needing to understand five layers to make one change, stop — the change is in the wrong place.

**Verify by running — always.** After every slice: `flutter analyze` must be clean and `flutter test` must be green **before you move on**. Do not reason about whether code is correct; run it. If you cannot run the tools in your environment, write down in `PROGRESS.md` exactly what must be run and stop at a safe point — do not guess and pile up unverified changes.

**Ship small vertical slices.** One controller, one policy, one widget per slice. Each slice: implement → write/adjust tests → `flutter analyze` → `flutter test` → update `PROGRESS.md` → commit. A slice should be small enough that its diff is easy to review and its tests obviously cover it. Never make a large, sweeping, untested change — it cannot be safely handed off.

**Never fabricate an API.** Use only `google_mobile_ads` 9.0.0 symbols documented in `RESEARCH.md`. If you are not certain a class/method/parameter exists, **grep the installed package source in the pub cache** (`find ~/.pub-cache -path '*google_mobile_ads*/lib/*.dart'`) and confirm before using it. A hallucinated API compiles in your head and fails on device — worse than pausing to check.

**Prefer deleting to adding.** This is a rewrite; reuse the *battle-tested logic* from v1 (retry timing, the consent-sample flow, test-mode) but not its global-singleton structure. When in doubt, the simpler design that satisfies the invariants wins.

---

## 2. Non-negotiable invariants (AdMob-specific — breaking these loses money or gets accounts banned)

These are not style preferences. Each one maps to real revenue or a real policy-enforcement risk. Never violate them, and add a test that guards each one.

1. **Consent gates every load.** Never call any ad `load()` before `ConsentGateway` reports `canRequestAds()` is true. `MobileAds.initialize()` may run in parallel with consent gathering, but no `load()` until the gate is open. Guard against double-loading with a boolean.
2. **Privacy options entry point.** When `getPrivacyOptionsRequirementStatus()` is `required`, a persistent "Manage consent / Privacy settings" control must be available that calls `ConsentForm.showPrivacyOptionsForm(...)`.
3. **App-open ads: warm-start only.** Never show on the first cold launch while still loading. Show only on foreground-return via `AppStateEventNotifier.appStateStream`. Enforce the **4-hour expiry** (discard + reload stale ads). Never show an app-open ad while another full-screen ad is showing (use the `FullScreenAdCoordinator`). Never over content that also shows a banner.
4. **Interstitials at natural breaks only.** Enforce a frequency cap (per-format time + count, and a global cross-format cap). Never on app launch or app exit; never immediately after another ad closes; never interrupt an active task.
5. **Rewarded interstitial: intro + skip first.** Always present the intro/announcement screen with clear reward messaging and a skip option before the ad plays. Non-negotiable AdMob policy.
6. **Test ads only in library/example code.** The library must never hardcode a production ad-unit ID. Production IDs come exclusively from `AdFlowConfig`. Keep a `testMode` that uses Google's official sample IDs.
7. **Single-use full-screen ads.** Interstitial / rewarded / rewarded-interstitial / app-open instances show once. Dispose them in the dismiss/fail callback and **reload the next one immediately** so one is always warm.
8. **The SDK seam is the only door to the plugin.** All `google_mobile_ads` calls go through `AdSdk`. Nothing else imports `google_mobile_ads` except the seam and the widgets that must host an `AdWidget`. This is what makes everything testable with `FakeAdSdk` and keeps the legacy/Next-Gen native swap invisible to our code.
9. **No global mutable state.** No static/singleton config. Config and collaborators are injected. A convenience accessor may exist, but it must be backed by an injectable instance so tests construct their own.

---

## 3. Definition of done for a slice

A slice is done only when ALL of these are true:

- It compiles and `flutter analyze` is clean (zero warnings/infos you introduced).
- Unit tests are written and green, using `FakeAdSdk` (and fakes for consent / key-value store / clock as needed). Every invariant the slice touches has a guarding test.
- Public API is documented with dartdoc comments.
- `DECISIONS.md` updated if you made any non-obvious choice (ADR entry: context → decision → rationale → consequences).
- `MIGRATION.md` updated if the public API changed relative to v1.
- `PROGRESS.md` updated (Section 4 template).
- Committed with a clear, scoped message (e.g. `feat(interstitial): add frequency-capped controller with reload-on-dismiss`).

If any of these is not true, the slice is not done — do not start the next one.

---

## 4. Handoff protocol (you may be replaced by a smaller model at any moment)

Assume that the next turn is a different model with **no memory of this conversation**. The only things it inherits are the repository and the docs. Make that enough.

End **every** session by updating `docs/ad_flow_v2/PROGRESS.md` using this template:

```markdown
# PROGRESS — ad_flow v2

## Current phase
<n> — <name>

## Done
- <completed slice> (<commit hash>)
- ...

## In progress
- <exact file(s)> — the very next concrete step is: <one sentence>

## Next (ordered)
1. <slice>
2. <slice>

## How to verify the current state
`flutter analyze` && `flutter test`   (or the exact narrower command, e.g. `flutter test test/policies/`)
Expected: analyze clean, N tests passing.

## Open questions / assumptions
- <anything a fresh model must know to not go wrong>

## Traps hit this session
- <new pitfall> → also append it to SKILL.md Section 6
```

Rules for a safe handoff:

- **Always leave the tree green.** Never stop mid-slice with a broken build or red tests. If you must stop, retreat to the last green state (or finish the tiny bit needed to make it green) first.
- **Never leave a half-fabricated API.** If you were unsure and guessing, revert the guess before you stop.
- **Front-load when capacity is low.** If you sense you are running out of room, do NOT start new work. Instead: (a) get the current slice to green, (b) update `PROGRESS.md`, (c) append any new trap to Section 6 of this skill. Those three things are what preserve quality across the handoff.
- A resuming model's first three actions are always: read the six docs (Section 0) → run `flutter analyze && flutter test` to confirm the green baseline → continue from `PROGRESS.md`'s "In progress".

---

## 5. When stuck

Do not thrash and do not silently guess. In order:

1. Re-read the relevant `RESEARCH.md` / `ARCHITECTURE.md` section — the answer is often already written down.
2. Confirm the API against the pub-cache source (grep it) rather than assuming.
3. If it's a genuine decision, make the **smallest safe assumption**, record it in `DECISIONS.md` (and note it under "Open questions" in `PROGRESS.md`), and continue.
4. If it's a decision only the maintainer (Faiz) can make, stop **at a green state** and ask him — never leave a broken build to "fix later."

A clean stop with a clear question beats a large, broken, speculative change every time.

---

## 6. Common pitfalls here (learned from v1 — append to this list whenever you hit a new one)

- **iOS `inactive` is NOT backgrounding.** v1 treated both `paused` and `inactive` as "went to background," so an app-open ad could fire after Control Center, a permission dialog, the notification shade, or the app-switcher preview. Use `AppStateEventNotifier.appStateStream` for the real foreground signal; do not hand-roll lifecycle detection off `didChangeAppLifecycleState`.
- **Don't fight the UMP callback API.** v1 wrapped UMP in `Completer`s + void callbacks + several 60s safety timeouts and still hit an "async-callback-as-void" bug. Wrap UMP into clean `Future`s **once**, in `ConsentGateway`, and let the rest of the code `await` it.
- **Test-mode detection must come from config, not resolved IDs.** v1 computed `isUsingTestAds` by checking whether the *resolved* ad-unit IDs contained Google's test publisher ID. Because unconfigured formats fall back to test IDs, a production app that simply didn't use one format falsely reported "using test ads." Derive test-mode from an explicit flag/config field.
- **One owner of app-open/foreground behavior.** v1 allowed two lifecycle reactors to exist (a widget-based one and an `enableAppOpenOnForeground` one) and coordinated them through static globals, which fight. Make two reactors impossible by construction; share suppression state through an injected `FullScreenAdCoordinator`, not statics.
- **Linear backoff hammers the SDK.** v1 retried on a fixed `delay * attempt` schedule with no jitter, so multiple managers retried in lockstep. Use exponential backoff **with jitter**, a max attempt count, a cooldown, and then **auto re-arm** (v1 also failed to re-arm banner/native loads after the cooldown unless the widget remounted).
- **No global frequency cap.** v1 only had a per-interstitial time cooldown. Real revenue/UX safety needs per-format time + count caps **and** a global cross-format cap so a user isn't hit by an interstitial then an app-open back to back.
- **The Flutter plugin has no preload API — even in 9.0.0.** "Preloading" is manual: `load()` ahead, cache the instance, `show()` later, and reload the next in `onAdDismissedFullScreenContent` / `onAdFailedToLoad`. Do not look for a `PreloadController`; it doesn't exist in Flutter.
- **Rewarded interstitial is not just a rewarded ad.** It needs the mandatory intro/skip screen; shipping it without one is a policy violation, not a UX nicety.
- **`dispose()` discipline.** Every `BannerAd`/`NativeAd`/full-screen ad and every stream subscription must be disposed. Lint with `close_sinks` / `cancel_subscriptions`; a leaked ad is a real memory and correctness bug.
- **app-ads.txt is required (since Jan 2025)** for full ad serving. It's a publisher-side setup step, but the README must call it out prominently or the maintainer's apps silently under-serve.
- **`AppStateEventNotifier.appStateStream` is dead until `startListening()`.** The plugin only starts emitting foreground/background events after `AppStateEventNotifier.startListening()` runs. `GmaAdSdk.appForegroundEvents` calls it lazily on first access — if you ever bypass the seam, remember it, or app-open-on-foreground silently never fires.
- **`BannerAd.isCollapsible` and inline-adaptive real height are async post-load calls.** `isCollapsible` is `Future<bool>`, and an inline adaptive banner's real height comes from `getPlatformAdSize()` after load. `GmaAdSdk` resolves both inside the load flow so `BannerHandle.size`/`isCollapsible` are plain sync getters above the seam.
- **`RequestConfiguration` tags are ints, not bools** (`TagFor*.yes/no/unspecified` = 1/0/-1; `maxAdContentRating` is a String constant). The seam maps `bool?`/enum → plugin encoding in `toGmaRequestConfiguration`; never pass raw bools through.

---

*Keep this file current. When you discover a new trap or make a method-level decision that future workers must follow, add it here in the same session. This skill is only as good as its last update.*
