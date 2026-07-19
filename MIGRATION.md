# Upgrading 4.0.x → 4.1.0

Non-breaking. Update the dependency and you are done — nothing to change.

Optional adoption:

- **Mediation consent forwarding:** if you use mediation partners that need
  their privacy signal before the first request (Unity, AppLovin US-state,
  Meta LDU), pass `forwardConsent: () async { ... }` to `AdFlow.initialize`
  — the first ad load waits for it. See `doc/MEDIATION_SETUP.md` §4.
- Behavior fixes (cap late-hydration, SSV in-flight/fail-drop, rewarded-
  interstitial post-intro re-check, async-callback isolation) require no code
  changes; they only make existing paths correct.

---

# Upgrading 3.x → 4.0.0

4.0 is a hardening major; most apps compile unchanged. Check these:

1. **Enum switches.** `AdBlockReason` gained `requestConfigNotApplied` and
   `internalError`; `AdFlowErrorKind` gained `ssv`. Add the cases to any
   exhaustive `switch` (or add a wildcard).
2. **Rewarded interstitial pacing.** The RI sequence is now paced by
   `globalFrequencyCap` (the intro is an app-chosen interruption), and every
   check runs BEFORE the intro. If you relied on RI ignoring the global gap,
   raise/clear `globalFrequencyCap` or the RI slot's own `cap`. Classic
   rewarded is still exempt.
3. **SSV semantics.** If you configure `ssv` and the attach fails at load,
   the load now FAILS (`AdFlowError(ssv)`) and retries — you may observe
   `AdFailed` where 3.x reported a (silently unverified) `AdLoaded`.
4. **Child-directed / rated / test-device apps.** If
   `updateRequestConfiguration` fails, loads now BLOCK with
   `AdBlocked(requestConfigNotApplied)` until the retried apply succeeds
   (default `RequestConfigFailurePolicy.auto`). Opt out with
   `requestConfigPolicy: RequestConfigFailurePolicy.failOpen` — not
   recommended for child-directed apps.
5. **Load watchdog.** Loads that get no SDK callback within
   `RetryConfig.loadTimeout` (default 60s) fail as `AdFlowError(timeout)`
   and retry. Pass `loadTimeout: null` for 3.x behavior (not recommended).
6. **`AdGate` constructor** (only if you build one directly, e.g. in tests):
   `configReady:` future → `settleRequestConfig:` bounded callback.
7. **Custom `AdSdk` implementations** must add
   `disableMediationInitialization()`.

New (additive): per-slot `AdRequestOptions request` on every format config,
`MediationNetworkExtras`, `AdFlow.onConsentChanged`,
`AdFlowConfig.deferMediationInit`, `RetryConfig.loadTimeout`. If you use
mediation, re-read `doc/MEDIATION_SETUP.md` — the consent-forwarding
section changed from "automatic" to the honest per-network contract.

---

# Upgrading 2.x → 3.0.0

3.0 bundles the (unpublished) 2.2.0 hardening work with a deliberate,
compact API cleanup. Breaking changes first — each takes minutes:

1. **`AdLoadState` gained `AdBlocked(reason)`.** Add one case to every
   exhaustive `switch` over `AdLoadState`. It replaces the old
   "blocked loads look like `AdIdle`" ambiguity: match on it to render
   "consent pending" / "ads off" placeholders directly.

2. **Prefer the widget-first ad widgets.** `AdFlowBanner(adFlow: ads)` /
   `AdFlowNativeAd(adFlow: ads)` create and own their controllers — delete
   your `late final _banner = ads.banner()` fields and the
   `controller:`/`ownsController:` arguments (that mode still exists for
   advanced use; `controller` is now optional).

3. **`show()` reward callback**: only `RewardedAdController` and
   `RewardedInterstitialAdController` accept `show(onReward: …)` now. If you
   passed `onReward` to `interstitial.show()` or an app-open show, it was
   silently ignored — delete it.

4. **Removed**: `AppOpenConfig.showOnColdStart` (ignored since 2.1.0 — it
   never could do anything; delete the argument) and `AdGate.canShow` (an
   unfixably racy composed query with a warning label; if you used it for a
   UI hint, combine `controller.state` + your own cap knowledge instead).
   `AdGate`'s constructor lost its unused `caps`/`coordinator` params.
   `BannerAdController.slot`/`NativeAdController.slot` →
   `slotName`.

5. **New reactive consent surface**: `ads.canRequestAds`
   (`ValueListenable<bool>`) is the LIVE answer — use it instead of caching
   `whenReady`'s one-shot result.

Behaviour changes carried over from the unpublished 2.2.0 hardening (check
these too):

1. **Preloaded interstitial/rewarded/rewarded-interstitial ads now expire**
   (`maxAdAge`, default 55 minutes, per Google's documented ~1-hour window).
   A stale warm ad is proactively replaced and never shown. Pass
   `maxAdAge: null` on the format config to restore the old keep-forever
   behaviour (not recommended — an expired ad may display but not count).

2. **`disableAds()` now DROPS live ads** — mounted banner/native widgets fall
   back to their placeholder and warm full-screen inventory is released,
   instead of only blocking future loads. If you relied on the old "the
   mounted ad stays until I hide it" behaviour, hide the widget first. The
   same drop now happens on `dispose()`, on a re-`initialize`, and when the
   user withdraws consent through the privacy-options form.

3. **A consent withdrawal is now acted on**: use `ads.consent` (not a
   directly-constructed `UmpConsentGateway`) for `PrivacyOptionsButton` /
   `showPrivacyOptions()` so the graph can react. `AdFlow.consent` returns a
   thin wrapper with identical behaviour otherwise.

4. **`initialize` validates the config** and throws
   `AdFlowError(invalidConfig)` on nonsense (empty ad-unit strings, negative
   durations). If this fires for you, the config was already broken — it was
   silently no-filling.

5. **Custom implementers of the seam/testing interfaces** (rare; the shipped
   fakes are updated): `BannerHandle.dimensions`, `*Handle.response`,
   rewarded handles' `updateServerSideVerification`, and
   `AdController.recheckGate()` are new interface members you must add.

New opt-in APIs you may want: runtime SSV
(`ads.rewarded.setServerSideVerification`), mediation observability
(`controller.response`, `AdPaidEvent.slot`/`adSourceName`), null-safe slot
getters (`ads.interstitialOrNull` …), and the kill-switch recipe in README §6.

# Upgrading 2.0.x → 2.1.0

**No breaking API changes** — everything still compiles. But several defaults and
behaviours changed on purpose. Check these five things:

1. **Banner refresh is now OFF by default.** `BannerConfig.minRefresh` defaults to
   `null` (no client-side refresh timer). AdMob already auto-refreshes banner ad
   units server-side, from the console, on by default — the client timer was a
   second, unsynchronised loop on the same placement. **Action:** confirm the
   refresh rate is set on the ad unit in the AdMob console. Pass `minRefresh:`
   explicitly only if you deliberately turned the console refresh off.

2. **`AppOpenConfig.showOnColdStart` is deprecated and ignored.** Delete it. App-open
   ads now show on the first genuine warm return of a session (they never could
   show on a cold launch — the platform emits no event for one).

3. **The global frequency cap no longer blocks rewarded ads.** If you were relying
   on `globalFrequencyCap` to limit how often users can watch rewarded ads, set
   `RewardedConfig(cap: ...)` / `RewardedInterstitialConfig(cap: ...)` instead —
   they are unlimited by default.

4. **Frequency gaps are measured from an ad's DISMISS, not its show.** A `minGap`
   of 30s now means 30s of *app* after the ad closes, not 30s that the ad itself
   may partly consume. Effective pacing is slightly more conservative; retune the
   value if you had compensated for the old behaviour.

5. **`AdFlow.initialize()` now disposes the previous graph.** If you call it more
   than once (login/logout, config change), that is now safe — and the old graph
   really stops. Two simultaneous `AdFlow` instances are not supported.

**Worth adopting:**

- `ads.onAdBlocked = (slot, reason) => log('ad_flow: $slot blocked: ${reason.name}')`
  — tells you *why* an ad did not appear (consent not granted, Remove-Ads,
  frequency cap, …) instead of the silent `AdIdle` you got before.
- `ads.setBlockingViewAdVisible(true/false)` on screens where a large banner or
  native ad fills the view, so no app-open ad is shown over it.

---

# MIGRATION — ad_flow v1 → v2

For apps currently on `ad_flow` 1.3.x. A consumer should be able to migrate from this file alone.

## 1. Project / platform prerequisites (from `google_mobile_ads` 9.x)
- **pubspec:** `ad_flow: ^2.0.0` (pulls `google_mobile_ads: ^9.0.0`).
- **Flutter ≥ 3.38.1, Dart ≥ 3.10.0.**
- **iOS:** deployment target **13.0**; adopt the **`UISceneDelegate`** lifecycle if you have a custom `AppDelegate` (needed for app-open). Add to `Info.plist`: `GADApplicationIdentifier`, and `NSUserTrackingUsageDescription` (ATT).
- **Android:** `minSdk 24`, `compileSdk 36`, AGP compatible with **8.13.1**; keep the `com.google.android.gms.ads.APPLICATION_ID` meta-data in `AndroidManifest.xml`.
- **app-ads.txt:** ensure your published `app-ads.txt` is verified (required since Jan 2025 for full serving).

## 2. Initialization
**v1**
```dart
await AdFlow.instance.initialize(config: myConfig, /* preload…, enableAppOpenOnForeground: */);
```
**v2** — `initialize` builds and returns the instance (dependency-injected; no static global config):
```dart
final ads = await AdFlow.initialize(myConfig);      // consent-gated internally
// keep `ads` (or use the convenience accessor if you opt into it)
```
Consent is gathered and `canRequestAds`-gated automatically; you no longer sequence UMP yourself.

**Non-blocking (behavior change — ADR-032).** `AdFlow.initialize()` still returns `Future<AdFlow>` (type unchanged), but the Future now **completes immediately, before consent** — the graph is built synchronously and consent/ATT/SDK-init run in the **background**. Do NOT gate your first frame on it: render your UI at once and let ads/consent/ATT appear over it. If you previously wrapped the app in a `FutureBuilder<AdFlow>` that showed a spinner until `initialize` resolved, drop it — the resolve no longer means "consent finished," and blocking on it reintroduces v1's splash hang. New `Future<bool> ads.whenReady` completes when the consent gate resolves, for the rare caller that must await it (not required for normal use). No ad request goes out before request configuration is applied and the consent gate opens — even a banner/native mounted on the first frame waits (ADR-033) — so rendering immediately is safe.

**Priming screens (v1 `initializeWithExplainer`)** are restored as opt-in presenters — decoupled from `BuildContext`:
```dart
final ads = await AdFlow.initialize(
  myConfig,
  attExplainer:     (c) => AttExplainerScreen.show(navigatorKey.currentContext!, c),
  consentExplainer: (c) => ConsentExplainerScreen.show(navigatorKey.currentContext!, c),
  // optional: attExplainerContent:/consentExplainerContent: to localize the copy
);
```

| v1 | v2 |
|---|---|
| `initializeWithExplainer(context:, consentTexts:, attTexts:)` | `initialize(attExplainer:, consentExplainer:, attExplainerContent:, consentExplainerContent:, skipConsentPrimerIfAttDenied:)` |

The `context:` parameter is gone: the app supplies the UI through a presenter callback (exactly like `rewardedIntroPresenter`), so the package never holds a `BuildContext`. Supplying `attExplainer` opts into **client-driven ATT** (re-adds `app_tracking_transparency` behind the seam, iOS only) — in that mode do **not** also set the UMP IDFA message in the AdMob console (double prompt). Pass nothing and behaviour is exactly today's (UMP-driven).

## 3. Configuration object
- v1's single flat `AdFlowConfig(androidBannerAdUnitId:, iosBannerAdUnitId:, …)` becomes **per-format config objects** with `PlatformAdUnitId(android:, ios:)`, plus per-format frequency caps and a global cap.
- **Test mode:** `AdFlowConfig.test()` (uses Google sample ids). Test-mode is now an explicit flag, not inferred from ids.

| v1 field | v2 |
|---|---|
| `androidBannerAdUnitId` / `iosBannerAdUnitId` | `banner: BannerConfig(adUnitId: PlatformAdUnitId(android:, ios:))` |
| `androidInterstitialAdUnitId` / `ios…` | `interstitial: InterstitialConfig(adUnitId: …)` |
| `androidRewardedAdUnitId` / `ios…` | `rewarded: RewardedConfig(adUnitId: …)` |
| `androidNativeAdUnitId` / `ios…` | `nativeAd: NativeConfig(adUnitId: …, templateKind: / factoryId:)` |
| `androidAppOpenAdUnitId` / `ios…` | `appOpen: AppOpenConfig(adUnitId: …)` |
| `minInterstitialInterval` (30s) | `InterstitialConfig.cap: FrequencyCap(minGap: …)` — plus optional `maxPerHour`, `maxPerSession`, and the new `globalFrequencyCap` across formats |
| `maxLoadRetries` / `retryDelay` / `retryCooldownAfterMaxAttempts` | `retry: RetryConfig(maxAttempts:, baseDelay:, maxDelay:, cooldown:, jitterFactor:)` — now exponential with jitter |
| `appOpenAdMaxCacheDuration` (4h) | `AppOpenConfig.expiry` (still 4h default) |
| `testDeviceIds`, `maxAdContentRating`, `tagFor…` | same names on `AdFlowConfig` (rating is the `MaxContentRating` enum; tags are `bool?`) |
| `isUsingTestAds` (derived, buggy) | `testMode` (explicit flag) |
| _(new)_ | `InterstitialConfig.minActionsBetween` (action pacing), `RewardedConfig.ssv`, `RewardedInterstitialConfig(intro:, ssv:)`, `BannerConfig(kind:, fixedSize:, collapsible:, minRefresh:)` |

## 4. Ad access & showing
| v1 | v2 |
|---|---|
| `AdFlow.instance.banner…` / `EasyBannerAd(...)` | `ads.banner(...)` controller + `AdFlowBanner(...)` widget |
| `AdFlow.instance.interstitial…` | `ads.interstitial` (`InterstitialAdController`) — `load()` / `show()` |
| `AdFlow.instance.rewarded…` | `ads.rewarded` — `show(onReward:)` |
| _(missing in v1)_ | `ads.rewardedInterstitial` — shows the intro/skip screen automatically |
| `AdFlow.instance.appOpen…` / `enableAppOpenOnForeground` | `ads.appOpen` (`AppOpenAdManager`, single owner) |
| native widget | `AdFlowNativeAd(...)` (template or factory) |
| `EasyPrivacySettingsButton` | `PrivacyOptionsButton` |
| `disableAds()/enableAds()` | same names on the facade |
| broad `google_mobile_ads` re-export | **no re-exports** (ADR-022) — import `google_mobile_ads` directly if you need plugin types |

State is now exposed as `ValueListenable<AdLoadState>` (use `ValueListenableBuilder`) instead of v1's manual listeners/streams.

## 5. Behavior changes to know
- **App-open** now shows on true foreground-return only (via `AppStateEventNotifier`), never on the first cold launch mid-load, and never while another full-screen ad is visible. If you relied on v1's `inactive`-triggered behavior, expect (correctly) fewer, better-timed app-open shows.
- **Frequency caps** are enforced per-format and globally; tune them in config.
- **Retries** use exponential backoff + jitter and auto re-arm after cooldown.
- **Rewarded interstitial** always shows an intro/skip screen first.

## 6. Next-Gen SDK (optional, experimental, Android-only)
No code change. To try it: build with `--dart-define=USE_NEXT_GEN_SDK=true` (Android only; iOS ignores it; legacy stays the default). See README.

## 7. Removed / renamed

| v1 symbol | v2 replacement |
|---|---|
| `AdFlow.instance.initialize(config: …)` | `await AdFlow.initialize(config)` (returns the instance) |
| `AdFlow.instance.preloadAds()` | automatic at init and after every dismissal |
| `EasyBannerAd` | `AdFlowBanner(controller: ads.banner(), ownsController: true)` |
| `EasyNativeAd` / `NativeAdWidget` / `NativeAdLayoutHelper` | `AdFlowNativeAd(controller: ads.native(), ownsController: true)` |
| `EasyPrivacySettingsButton` / `PrivacySettingsListTile` | `PrivacyOptionsButton(consent: ads.consent)` |
| `BannerAdManager` / `InterstitialAdManager` / `RewardedAdManager` / `NativeAdManager` / `AppOpenAdManager` (v1) | `ads.banner()` / `ads.interstitial` / `ads.rewarded` / `ads.native()` / `ads.appOpen` controllers |
| `AppLifecycleReactor` / `AppOpenAdWrapper` / `enableAppOpenOnForeground` | the single `AppOpenAdManager` started by `initialize` |
| `AdsEnabledManager` | `ads.enableAds()` / `ads.disableAds()` / `ads.adsEnabled` |
| `ConsentManager` / `ConsentExplainerDialog` / `ConsentExplainerLocalizations` | `ConsentGateway` (`ads.consent`); UMP owns the form UI. Priming screens return as opt-in presenters — `AttExplainerScreen` / `ConsentExplainerScreen` (or your own), passed to `initialize` (see §2). Default (no presenter): UMP-driven, no ATT calls |
| `initializeWithExplainer(context:, consentTexts:, attTexts:)` | `initialize(attExplainer:, consentExplainer:, attExplainerContent:, consentExplainerContent:)` — presenter pattern, no `BuildContext` (see §2) |
| `AdErrorHandler` | typed `AdFlowError` (thrown by the seam, carried in `AdFailed`, surfaced on `consent.lastError`) |
| `AdManagerMixin` / `PrivacyRequirementMixin` | not needed — subscribe to `controller.state` / read `consent.isPrivacyOptionsRequired` |
| `MediationHelper` / `MediationConsentConfig` / `MediationForward…` | removed — UMP forwards consent to partners registered in AdMob's Privacy & messaging; add `gma_mediation_*` adapters directly |
| `TestAdIds.*` getters | `TestAdUnitIds.*` (`PlatformAdUnitId` constants) — or just use `testMode` |
| broad `google_mobile_ads` + `TrackingStatus` re-exports | none (ADR-022) — import the plugin directly if needed |
| _(new)_ | `package:ad_flow/ad_flow_testing.dart` — `FakeAdSdk` + fake handles for your own tests |
