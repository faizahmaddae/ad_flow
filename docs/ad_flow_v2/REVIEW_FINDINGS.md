# ad_flow v2 — Independent Code Review (Opus)

Reviewed commit `3ede24d` on branch `v2`, by static reading (Flutter not available in the review env, so tests were not re-run — 205 were green per the build). Four independent review passes (concurrency, consent/policy, architecture/resources, test quality); every finding below was then **re-verified by hand** against the actual source. Line numbers are from the reviewed commit.

## Verdict
The architecture is sound and the logic layer is genuinely well-built — consent gating, cap math, the rewarded-interstitial intro gate, disposal discipline, the seam boundary, and "no global state" are all correct and (mostly) well-tested. **But there is one blocker-class bug and a few real majors, and they cluster in exactly the layer the unit tests can't see: the live plugin seam and controller timing.** Fix the must-fix list before publishing; everything is a contained fix.

---

## Must fix before publish

### 1. BLOCKER — `show()` awaits `handle.show()` with no try/catch → one rejected show wedges every full-screen ad for the whole session
`lib/src/controllers/full_screen_ad_controller_base.dart:194`
```dart
if (!_coordinator.tryEnter()) return false;   // claims the shared coordinator
_enteredCoordinator = true;
_state.value = const AdShowing();
...
await handle.show(onUserEarnedReward: onRewardOnce);   // ← no try/catch
```
The coordinator is claimed and `_state` set to `AdShowing` *before* the await. `_exitCoordinator()` only runs from a content event (`AdDismissedEvent`/`AdFailedToShowEvent`), from `rejectAndRollBack` (gate/caps only), or `dispose()`. The seam forwards the plugin future raw (`gma_ad_sdk.dart` `show() => _ad.show()`), and `_ad.show()` **can reject** (ad expired/released between load and show, "not ready", channel error, mediation failure) — none of which produce a content event.

**Failure:** interstitial warm → `show()` claims coordinator, sets `AdShowing` → `_ad.show()` rejects → exception unwinds; `_exitCoordinator()` never runs. `_coordinator` depth stays `1` → `isFullScreenAdVisible` stuck `true` → **every** full-screen controller (interstitial, rewarded, rewarded-interstitial, **and app-open**) has `tryEnter()` return `false` for the rest of the session. This controller is also stuck in `AdShowing` (its `load()` early-returns), so it never reloads. Session-long full-screen revenue loss from a single, not-rare rejection. Also an unhandled async error.

**Fix:** wrap the show dispatch; on error route through the failure path:
```dart
try {
  await handle.show(onUserEarnedReward: onRewardOnce);
} catch (e) {
  _exitCoordinator();
  _dropHandle();
  if (!_disposed) { _state.value = AdFailed(AdFlowError(AdFlowErrorKind.showFailed, '$e')); unawaited(load()); }
  return false;
}
onShown();
return true;
```
(Optionally also harden the seam so `show()` never rejects — emit `AdFailedToShowEvent` instead — but fix the controller regardless.) Add a `FakeFullScreenAdHandle.show()` mode that *rejects* so this is testable.

### 2. MAJOR — banner load completes its `Completer` on every refresh → `StateError` (unhandled) every ~60s
`lib/src/seam/gma_ad_sdk.dart:133` + `:193`
```dart
onAdLoaded: (_) => unawaited(_finishBannerLoad(handle, spec, completer)),
...
handle._size = size; handle._isCollapsible = collapsible;
completer.complete(handle);   // ← no isCompleted guard
```
`BannerAdListener.onAdLoaded` fires on **every** load, including AdMob's default auto-refresh. On the 2nd firing, `completer.complete()` runs on an already-completed completer → throws `StateError: Future already completed`; because it's `unawaited`, it's an unhandled async error on every refresh cycle (spams Crashlytics, may trip error zones).

**Fix:** guard the top of `_finishBannerLoad`: `if (completer.isCompleted) { handle._size = size; handle._isCollapsible = collapsible; return; }` — i.e. still update the handle's size on later refreshes, but only complete once.

### 3. MAJOR — a stale retry timer stomps a now-valid `AdLoaded`/`AdShowing` state → leaks the shown ad + a live subscription
`lib/src/controllers/full_screen_ad_controller_base.dart:234-245` (retry callback sets `AdIdle` unconditionally) with `128-138` (load-success path never cancels `_timer`). Same shape in `native_ad_controller.dart:123-135`.

**Failure:** load fails → retry timer T armed. Then `show()` finds it not ready → `unawaited(load())` (line 153) which succeeds → `_handle=A`, `_contentSub=SA`, `AdLoaded`; app shows A → `AdShowing`. **T is still pending.** T fires → `_state.value = AdIdle` (stomps `AdShowing`) → `load()` → `_handle=B` (overwrites A with no dispose → **A leaks**), `_contentSub=SB` (SA reassigned, never cancelled → **SA leaks**). When A dismisses, dangling SA fires `_onContentEvent` → `_dropHandle()` disposes **B** (never shown). Leaked ad + leaked subscription + churn, from the common "failed load, later show" sequence.

**Fix:** guard the retry callbacks so they only act while still failed: `if (_disposed || _state.value is! AdFailed) return;` before touching state (and/or cancel `_timer` in the load-success path). `_scheduleGateRecheck` is already safe (it doesn't stomp state).

### 4. MAJOR — `NativeAdController.reload()` resets to `AdIdle`, re-opening the ADR-024 double-load window
`lib/src/controllers/native_ad_controller.dart:111-117`
```dart
Future<void> reload() async {
  if (_disposed) return;
  _timer?.cancel();
  _dropHandle();
  _state.value = const AdIdle();   // defeats the synchronous AdLoading guard
  await load();
}
```
**Failure:** `load()` (call #1) is in flight (suspended at `await _gate.canLoad`, state `AdLoading`). `reload()` sets `AdIdle` → `load()` (call #2) sees `AdIdle`, proceeds → two concurrent `loadNative` requests; the second `_handle=` assignment overwrites the first with no dispose → leaked native ad + double request for one slot.

**Fix:** don't stomp an in-flight load — set `AdLoading` synchronously (not `AdIdle`) before awaiting, or bail if `_state.value is AdLoading`. (The base's `discardCurrentAd()` has the same shape; it's safe *today* only because its one caller guarantees `AdLoaded` — but finding #3 can break that guarantee, so fix it too.)

---

## Should fix (minor, but real)

### 5. MINOR (MAJOR for child-directed / test-device apps) — request configuration is skipped when consent isn't resolved at init
`lib/src/facade/ad_flow.dart:224` — `updateRequestConfiguration` runs only `if (canRequest)`. But it sends no ad request (pure config), so gating it on consent is unnecessary and harmful: if consent resolves *later* (privacy-options grant, or a first-launch form that failed), controllers then load ads with **`testDeviceIds`, `tagForChildDirectedTreatment`, `maxAdContentRating`, `tagForUnderAgeOfConsent` never applied**. Result: a registered test device gets *live* ads (self-click / invalid-traffic risk); a child-directed app serves untagged/wrongly-rated ads (COPPA/policy).
**Fix:** call `updateRequestConfiguration` unconditionally in `_start` (before the loads), independent of the consent gate. (This also corrects ARCHITECTURE.md's sequence note.)

### 6. MINOR — `AdGate.canShow` is dead code that re-embodies the exact ADR-024 race
`lib/src/policy/ad_gate.dart:38-42` — no caller (the base controller deliberately bypasses it and does its own `tryEnter()`; the comment at `full_screen_ad_controller_base.dart:157-164` explains why). Its `await`-separated coordinator check is precisely the double-show race that was fixed. Leaving it live invites a future controller to wire to it and reintroduce the bug.
**Fix:** delete `AdGate.canShow` (or strip it to the caps-only part and document it as not for the show path).

### 7. MINOR (design) — app-open can fire *immediately after* a full-screen dismiss unless the app sets a non-zero global `minGap`
On dismiss, `_onContentEvent` calls `_exitCoordinator()` *before* the resumed-foreground event reaches `AppOpenAdManager`, so `tryEnter()` succeeds and only `globalFrequencyCap.minGap` stands between an interstitial closing and an app-open opening. The default `FrequencyCap()` has no `minGap`, so invariant 4's "never immediately after another ad closes" isn't enforced by default.
**Fix:** add a short post-dismiss suppression window in the coordinator/manager (Google's own app-open sample uses an "is/just-showed" flag), independent of cap config — or set a sane default `minGap` and document it.

### 8. MINOR — adaptive banners reserve a flat 50px → residual layout shift (accidental-click policy)
`lib/src/controllers/banner_ad_controller.dart:80` reserves `50` for anchored/inline adaptive, but real anchored-adaptive height is often 50–90px (inline can be much taller), so the `SizedBox` jumps when the ad lands. Mitigated by a caller-supplied `placeholderHeight`, and documented — hence minor — but the default shifts on common devices, which is exactly what the "Layout Encourages Accidental Clicks" policy targets.
**Fix:** reserve the resolved anchored height once known, or make `placeholderHeight` strongly recommended in docs for adaptive placements.

---

## Test & robustness (do soon — this is the residual risk)

### 9. The real `GmaAdSdk` seam (~660 LOC) is essentially untested — and findings 1–3 all live there
`grep 'GmaAdSdk(' test/` → none; only the pure mapper functions are tested (`gma_mappers_test.dart`). All the stateful plugin wiring — load-callback→Future, `fullScreenContentCallback`→event stream, single-use dispose+reload, `AppStateEventNotifier.startListening()`, async `isCollapsible`/`getPlatformAdSize` — is unverified. Every "205 tests prove correctness" claim rests on "`FakeAdSdk` faithfully models the plugin," which nothing checks. This is the same gap the build honestly flagged, and it's why bugs 1/2/3 shipped green.
**Fix:** add a `GmaAdSdk` test using `TestWidgetsFlutterBinding` + `setMockMethodCallHandler('plugins.flutter.io/google_mobile_ads', …)` asserting: load-success completes the Future; a simulated dismiss emits exactly one `AdDismissedEvent`; first `appForegroundEvents` subscription triggers `startListening`; `onAdFailedToLoad` throws the mapped `AdFlowError`; and (for #1) a rejected `show()` is handled.

### 10. `FakeAdSdk` is more forgiving than the real SDK → false confidence
`fake_ad_sdk.dart:365-374` — `FakeFullScreenAdHandle.show()` never fails on a 2nd show and never rejects; the fake also permits impossible event orderings (dismiss-without-show, reward-after-dismiss). The real plugin is single-use and ordered. A double-show or stray event that slips a controller guard wouldn't be caught.
**Fix:** make the fake authoritative — 2nd `show()` (or show-after-terminal) emits `AdFailedToShowEvent`; add a `showRejects` mode (for #1); reject impossible transitions. Then add controller tests for double-dispatch and post-dismiss reward.

### 11. `no_global_state_test` regex exempts every `static final <UpperType>` — the idiomatic way to hold global mutable state
`test/architecture/no_global_state_test.dart:18-24` — the `(?!final\s+[A-Z])` carve-out means `static final List<String> _log = [];` or `static final ValueNotifier<int> _shared = …` pass. Clean today, but the guard misses the most realistic invariant-9 violation.
**Fix:** drop the `[A-Z]` exemption; allow-list known-immutable singletons by name, or flag `static final` initialized to a mutable literal (`[`, `{`, `ValueNotifier(`, `StreamController(`).

### 12. Add an executable guard against hardcoded production ad-unit IDs (invariant 6)
Today only a value-swap test exists. Mirror `seam_boundary_test`: scan `lib/` for `ca-app-pub-<publisher>/…` and assert every publisher segment is Google's sample `3940256099942544`.

**Nits:** banner/native seam handles construct two broadcast `StreamController`s before `ad.load()` and don't `close()` them on load-failure (GC-reclaimed, `close_sinks`-flaggable); `AdFlowConfig` has no `copyWith` (the ARCHITECTURE sketch listed one — optional); verify the `DebugGeography` enum member spellings against the installed UMP 4.0 plugin (`debugGeographyRegulatedUsState`/`debugGeographyOther` look right but couldn't be confirmed without the pub cache).

---

## Confirmed solid (verified, no action)
- **Seam boundary:** only `gma_ad_sdk.dart` imports `package:google_mobile_ads`; even the widgets host `AdWidget` via the seam. Tight.
- **No global mutable state:** the only mutable `static` is the sanctioned `AdFlow._instance`, correctly nulled in `dispose()`.
- **Consent gating:** every `load()` path routes through `AdGate.canLoad → canRequestAds`; the synchronous `AdLoading` guard prevents double-load; no `sdk.load*` exists outside the seam.
- **Interstitial cap math:** `minActionsBetween=2` with reset-on-show = exactly ≤1/2 actions; window boundaries correct; timestamps UTC; persists across restart.
- **Rewarded-interstitial:** the intro+skip screen is structurally unbypassable (virtual dispatch through the override); skip grants no reward; reward is deduped once per ad.
- **Privacy-options button:** reactive via `ValueListenableBuilder` on `consent.privacyOptionsRequired` (ADR-025 fix is correct; a test kills the old stale-getter bug).
- **Disposal:** every notifier/subscription/timer/handle is disposed; facade dispose order is correct; `_disposed` guards after every await.
- **Concurrency regression tests** genuinely interleave (same-turn `tryEnter`), not sequential happy-path.
- **pubspec:** `google_mobile_ads: ^9.0.0`, Flutter ≥3.38.1, Dart ≥3.10.0 — correct.

---

### Suggested order
Fix **1** first (blocker), then **2, 3, 4** (majors), add the **#9/#10** seam tests that would have caught them, then **5–8** and the remaining test hardening. Re-run `flutter analyze` + `flutter test` + the real-device QA checklist. None of these change the public API, so `MIGRATION.md`/`CHANGELOG.md` are unaffected.
