# ad_flow v2 — Audit: structure, defaults, timeouts & blocking init

Focused on the two concerns Faiz raised (timeouts + init blocking the app on weak internet), plus a structure/best-practice/defaults pass. Read against the actual code (facade `initialize`/`_start`, `ConsentGateway`, `RetryPolicy`, `AdFlowConfig` defaults).

## Verdict at a glance
- **Timeouts: already done right.** Only ONE app-level timeout exists, it degrades gracefully, and ad loading has none. Your weak-internet worry is well handled. ✅
- **Default values: sensible and policy-safe.** A couple are worth tuning for revenue (noted). ✅
- **Structure: strong** (DI, seam, sealed state, tested). ✅
- **Blocking init: THIS is the real issue** — `await AdFlow.initialize()` waits for the whole consent/network flow before returning, so on weak internet the app is blocked behind a splash/white screen. It reproduces exactly the v1 problem that made you write `initializeWithExplainer`. Fixable, and it's the one change worth making before publish. ⚠️

---

## 1. Timeouts — GOOD (your concern is handled)

Every timeout/delay in the package, and my verdict:

| Where | Value | Blocks the user? | Verdict |
|---|---|---|---|
| Consent **info-update** (`ConsentGateway`) | 30s, **configurable** | No — on timeout it **degrades to `canRequestAds()`** (uses previously-stored consent) | ✅ safe net, not a hard cut-off |
| Consent **form** display | **no timeout** (by design) | No | ✅ correct — a slow user/network never kills the form |
| `MobileAds.initialize()` | SDK-internal ~30s | No | ✅ native, not ours |
| Ad **loads** (banner/interstitial/rewarded/native/app-open) | **no timeout** | No | ✅ exactly right for weak internet — a slow load is never aborted; failures use retry |
| ATT prompt pre-delay | 200 ms | No | ✅ Apple guidance |
| Retry backoff | 5s → 60s cap, 5min cooldown | No | ✅ |
| App-open post-dismiss suppression | 1s | No | ✅ |

**Bottom line:** v2 learned the v1 lesson. There is exactly **one** network timeout (30s on the consent info-update), and it **degrades gracefully** rather than blocking or failing — on very weak internet it just falls back to the last-known consent answer and moves on. Ad loading is never timed out. If you want, the 30s is a constructor param you can raise, but it's a good default. **No change needed here.**

## 2. Blocking init — the real problem (and the fix)

**What the code does today** (`facade/ad_flow.dart`):
```dart
static Future<AdFlow> initialize(config, {...}) async {
  final flow = AdFlow._(...);      // builds the graph — fast, synchronous
  await flow._start(consentDebug); // ← awaits consent gathering (network-bound!)
  return flow;
}
```
`_start` runs `consent.ensureCanRequestAds()` (UMP info-update + form, and now ATT). So **`await AdFlow.initialize()` doesn't return until the whole consent/network flow finishes.** Because it's the first thing in `main`/the first screen (the example gates a `FutureBuilder<AdFlow>` on it), on weak internet the user stares at a splash/white screen for seconds — **the exact v1 problem.**

**Why it doesn't need to block:** every controller already gates its own loads on `canRequestAds` and no-ops until the gate opens. So the app can render immediately and ads simply appear once consent resolves in the background. Nothing about showing your UI depends on init being finished.

**Recommended fix — make init non-blocking by default:**
- `AdFlow.initialize(config)` should **build the graph and return the instance immediately** (graph construction is synchronous), and run `_start()` (consent + SDK init + preloads) **in the background** (unawaited, with error capture).
- Expose an optional `Future<bool> get whenReady` (or `ads.consentResolved`) for the rare caller who genuinely wants to await — but the **default/documented** usage never blocks.
- Update the **example + README** to render the home screen immediately (drop the `FutureBuilder<AdFlow>` gate). The consent form + ATT + your explainer screens then appear **as routes over the already-visible app** (which the presenter pattern already enables) — better UX than a frozen splash.

Net effect: the app is **never** blocked on AdMob again, on any connection speed. This is also AdMob's own guidance (initialize off the UI path; never block the first frame). It makes `initializeWithExplainer`'s original motivation obsolete in the best way — the explainer becomes a nicety, not a workaround for a frozen screen.

> Note: this changes `initialize`'s return type (Future→sync or add `whenReady`). It's a breaking change, but v2 is unpublished, so now is the moment. It does not affect any invariant (consent still gates every load).

## 3. Default values — sensible; a few revenue notes
Confirmed defaults: retry **5s base → 60s cap → 5min cooldown** then auto re-arm; interstitial cap **30s minGap**; app-open **4min minGap + 4h expiry**; global cap **15s minGap, 100/session**; banner refresh **60s (30s floor)**.

- All are **policy-safe and reasonable**. Good out-of-the-box.
- For **revenue tuning** (optional, per app): the interstitial default has only a 30s minGap and no `maxPerHour` — fine, but consider adding a modest `maxPerHour` if you want a hard ceiling, or shortening minGap where your UX has frequent natural breaks. The global 15s minGap is conservative; you can lower it if you never stack formats.
- App-open 4min minGap is sensible for "opened more than once per session" apps; leave as-is.

## 4. Structure / best-practice — strong
DI over globals, the `AdSdk` seam as the single plugin door, sealed `AdLoadState`, `ValueListenable` state, exponential backoff + jitter + auto re-arm, per-format + global frequency caps, consent-first gating, single-use full-screen ads with reload-on-dismiss, impression-level `onPaidEvent`, and a real test suite behind `FakeAdSdk`. This is at or above best-practice for a Flutter AdMob wrapper. The only best-practice deviation is the blocking init (§2).

## 5. Other angles worth knowing (not raised, but relevant to weak internet)
- **Offline launch:** today, offline → the 30s info-update timeout must elapse before the blocking `FutureBuilder` releases → up to 30s of splash. **Non-blocking init (§2) fixes this too** — the app renders instantly and consent resolves/degrades in the background.
- **Preload bandwidth contention:** on weak links, preloading every full-screen format at once competes for bandwidth and delays the first useful ad. Minor; if you notice it, stagger preloads (load interstitial first, others shortly after). Not needed for launch.
- **App-open on cold start + weak internet:** correctly does nothing (no ad ready yet) — no blocking. ✅

---

## Recommended actions before publish (priority order)
1. **Make `initialize` non-blocking** (+ fix example/README to render immediately). — the one that matters for your users.
2. (Optional) Add `whenReady`/`consentResolved` for callers who want to await.
3. (Optional) Note revenue-tuning knobs in the README defaults table.

Timeouts and defaults need **no** change.
