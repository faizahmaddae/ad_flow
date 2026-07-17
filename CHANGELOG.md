## 3.0.0

Two releases in one (2.2.0 was never published): the production-hardening
work from a deep 2026-07 multi-agent audit (25 confirmed findings, all
fixed), plus the API cleanup that backward compatibility had forbidden.
See MIGRATION.md for the short 2.x → 3.0 checklist.

### BREAKING

- **`AdBlocked(reason)` is a new `AdLoadState` case.** A load refused by
  policy (consent pending, Remove-Ads, withdrawal, disposed graph) now
  reports itself as a state instead of an `AdIdle` indistinguishable from
  "nothing requested yet" — the model ADR-045 documented as correct but
  could not ship in 2.x. Exhaustive switches gain one case; the controller
  still re-checks its gate and proceeds to `AdLoading` on its own.
- **Widget-first ad widgets.** `AdFlowBanner(adFlow: ads)` /
  `AdFlowNativeAd(adFlow: ads)` create AND own their controller, making the
  ADR-029 footgun (minting a controller inside `build()` → permanently
  blank ad) unrepresentable. `controller:` is now optional (advanced use).
- **`FullScreenAdController.show()` takes no reward callback** — it was
  silently ignored by interstitial and app-open. The rewarded formats keep
  `show({onReward})`.
- **`AdGate` is a pure permission gate**: the racy composed `canShow()`
  query (review finding #6) and its caps/coordinator collaborators are
  removed. Show pacing lives in the controllers, where the atomic
  `tryEnter()` is.
- **`AppOpenConfig.showOnColdStart` removed** (deprecated + ignored since
  2.1.0; it never could do anything). Banner/native slot constants renamed
  `slot` → `slotName` to match the full-screen formats.

### Added (3.0)

- `AdFlow.canRequestAds` — a `ValueListenable<bool>` with the LIVE consent
  answer: follows a late consent grant (ADR-035 retry) and a
  privacy-options withdrawal, unlike the one-shot `whenReady` snapshot.

### Fixed (correctness / revenue)

- **Banner refresh/resize races**: a rotation during an in-flight opt-in
  refresh could leak a live `BannerAd` (a native view), destroy a fresher
  right-width ad, corrupt the recorded width, or cancel the slot's only
  recovery timer (wedging it blank). `resize()` now defers to an in-flight
  refresh; the refresh completion re-validates state and reconciles a
  mid-flight width change; the failure path backs off only while a current ad
  exists.
- **Refresh swaps now actually reach the screen**: the plugin's `AdWidget`
  cannot re-point its platform view at a new ad, so an unkeyed rebuild after
  a swap kept hosting the DISPOSED ad — a permanently dead slot that still
  requested (and paid for) fresh ads. `AdFlowBanner`/`AdFlowNativeAd` now key
  the hosted subtree by handle identity, forcing a correct remount.
- **Inline-adaptive auto-refresh**: a failed post-refresh size query tore
  down the LIVE mounted banner and silently ended its revenue reporting; it
  now only fails the initial load. A refresh that resolves a *different*
  height updates the widget via the new `BannerHandle.dimensions`
  listenable (inline adaptive creatives vary per refresh).
- **Preloaded full-screen ads expire** (Google documents ~1 hour): new
  `maxAdAge` on interstitial/rewarded/rewarded-interstitial configs (default
  55 min; null disables) — stale warm ads are proactively replaced and never
  shown. App-open's 4h expiry now runs through the same shared mechanism and
  also replaces proactively.
- **Ads come DOWN when no longer permitted**: `disableAds()` (Remove-Ads),
  `dispose()`, a re-`initialize`, and a consent withdrawal through
  `ads.consent` now DROP live banner/native ads and warm full-screen
  inventory (previously only future loads were blocked — a mounted banner
  kept serving and auto-refreshing). `enableAds()` re-warms at once. New
  `AdController.recheckGate()`.
- **show() no longer holds the shared coordinator across a consent settle**:
  a network-bound consent retry could freeze every full-screen format behind
  one `show()` call for up to 30s. The show path now uses cheap live checks
  only (`AdGate.showBlockReason`).
- **View-ad click latch can no longer be stranded**: an iOS in-app overlay
  click (open→close with no foreground event) used to eat the NEXT genuine
  warm return's app-open ad. `onAdClosed` now starts a 3s grace clock;
  Android's external-browser return ordering stays suppressed.
- Raw platform-channel throws from the load *dispatch* are normalized to
  `AdFlowError` and no longer leak the constructed ad + stream controllers.
- `SharedPrefsKeyValueStore` reads type-corrupt data as absent instead of
  throwing (a throwing cap read blocked every full-screen show, with no
  self-heal).
- Consent/ATT primers wait (bounded) for the first frame, so a fast launch
  no longer silently drops the primer before the navigator mounts.
- `PrivacyOptionsButton` failures default to `FlutterError.reportError`
  instead of a silent swallow.

### Added

- **Runtime SSV**: `setServerSideVerification(ssv)` on both rewarded
  controllers — set `userId` after login and per-show `customData`; applies
  to the warm ad and future loads; throws if attaching fails.
- **Mediation observability**: `AdResponseSummary` (`handle.response` /
  `controller.response`) — winning ad source, adapter class, response ID.
  `AdPaidEvent` gains `slot` and `adSourceName` for analytics-ready
  impression logging.
- `AdFlowConfig.validate()` (run automatically): empty ad-unit strings and
  nonsensical durations fail fast at init.
- Null-safe slot getters: `interstitialOrNull`, `rewardedOrNull`,
  `rewardedInterstitialOrNull`, `appOpenOrNull`, `appOpenControllerOrNull`.
- Testing surface: `FakeBannerHandle.simulateResize`/`responseSummary`,
  `FakeFullScreenAdHandle.simulateShowFailed`/`ssvUpdates`/`ssvUpdateError`,
  `FakeAdSdk.onPrivacyOptionsFormShown`.

### Changed

- `AdFlow.consent` now returns a thin graph-aware wrapper: consent-mutating
  calls trigger a permission re-check across every controller (this is what
  makes withdrawal drop live ads). Read-only members delegate unchanged.
- Docs: `doc/MEDIATION_SETUP.md` and `doc/NATIVE_ADS_SETUP.md` rewritten for
  v2 (they still described the removed v1 API); README documents the
  emergency kill-switch pattern, the Families app-open prohibition, and
  both-platform ad unit configuration.

### For implementers of the seam interfaces (rare)

`BannerHandle` gained `dimensions`; all handles gained `response`; the
rewarded handles gained `updateServerSideVerification`; `AdController`
gained `recheckGate()`. The in-package fakes implement all of these — custom
implementations must add them.

## 2.1.1

Docs: README updated to 2.1.x; documented the diagnostic surface
(`AdBlockReason` / `onAdBlocked` / `lastBlockReason`) and the rewarded
global-cap exemption; fixed a stale skill trap. No code changes.

## 2.1.0

Behaviour and default changes from the eight judgment calls raised by the 2.0.2
audit, all approved by the maintainer. **No breaking API changes** — every
existing call site still compiles. But several DEFAULTS and BEHAVIOURS changed
deliberately; read this section before upgrading. See MIGRATION.md for the
upgrade checklist and ADR-039 … ADR-045 for the reasoning.

### Revenue

* **The global frequency cap no longer blocks user-initiated rewarded ads**
  (ADR-039). A user who tapped "watch an ad for 100 coins" 10s after an
  interstitial fired got no ad, no reward and no explanation — the shipped
  default global gap (15s) silently refused the highest-eCPM format in the
  package. The global cap now paces **involuntary** ads only (interstitial,
  app-open). Rewarded impressions are still *recorded* globally, so an
  interstitial cannot fire straight after one.
  **New:** `RewardedConfig.cap` / `RewardedInterstitialConfig.cap` (unlimited by
  default) if you do want a per-format limit.
* **App-open ads now show on the FIRST genuine warm return of a session**
  (ADR-043). The manager was consuming that return as a "cold start" the
  platform never actually emits — costing one impression in every single
  session, on both platforms. A true cold start still cannot show an ad: nothing
  is loaded yet.
* **A banner refresh no longer blanks the slot** (ADR-041). It used to destroy
  the live ad and reload from empty, so the slot went blank for the whole load —
  multi-second on a weak network, every cycle — and a refresh that merely failed
  (no-fill, routine) left it empty, having destroyed a perfectly good ad to get
  there. The replacement now loads in the background and swaps in only on
  success.

### Defaults changed

* **`BannerConfig.minRefresh` now defaults to `null` = no client-side refresh at
  all** (ADR-041). AdMob already auto-refreshes banner ad units server-side, from
  the console, **on by default**; the client timer was a second, unsynchronised
  refresh loop on the same placement — up to 2x the ad requests for no extra
  revenue. Set the refresh rate in the AdMob console. Pass `minRefresh:`
  explicitly to opt back in.
* **The frequency gap is now measured from the previous ad's DISMISS, not its
  SHOW** (ADR-040). Stamped at show time, the gap ran down while the user was
  still watching: a 30s rewarded ad under a 15s global gap used the gap up on
  screen, so an interstitial could fire the instant the user closed it — two
  full-screen ads back to back.
* **`AppOpenConfig.showOnColdStart` is deprecated and ignored** (ADR-043). It
  could never do what its name promised, and its only real effect is now the
  default. Remove it.

### Policy

* **An app-open ad no longer stacks on a banner/native ad** (ADR-042). Returning
  from a banner or native ad the user *clicked* no longer shows one — they were
  being handed a second ad the moment they closed the first. And the new
  `AdFlow.setBlockingViewAdVisible(bool)` lets the app declare that a blocking
  banner occupies the screen, so no app-open ad covers it. ad_flow cannot judge
  that itself — whether a banner is "blocking" is a question about your layout —
  so placement remains partly the integrator's job.

### Robustness

* **`AdFlow.initialize()` is now idempotent** (ADR-044). A second call used to
  build a whole new graph and leave the previous one fully alive — still
  listening to the foreground stream, still preloading, still able to show ads,
  and coordinating through its own separate coordinator, so it could not even see
  the new graph's ads. Two app-open reactors, each blind to the other. It now
  disposes the previous graph.

### New

* **`AdBlockReason` + `AdFlow.onAdBlocked` + `controller.lastBlockReason`**
  (ADR-045) — the answer to "why aren't my ads showing?". A refused load reported
  plain `AdIdle`, which is also what "nothing requested yet" looks like, so
  consent-not-gathered, Remove-Ads and a frequency cap all looked identical, and
  the package logged nothing. Deliberately **not** a new `AdLoadState` case:
  `AdLoadState` is sealed, and adding one would break every exhaustive `switch`
  in every app.
* `AdFlow.setBlockingViewAdVisible(bool)`; `BannerAdController.revision`,
  `.resize()`, `.loadedWidth`; `StoredFrequencyCapPolicy.globalCapExemptSlots`;
  `AdGate.loadBlockReason()`; `FullScreenAdCoordinator.noteViewAdOpened()` /
  `.consumeViewAdOpened()` / `.blockingViewAdVisible`.

## 2.0.2

Bug-fix release from a full adversarial audit. Every fix below is guarded by a
test that was verified failing first. No breaking API changes.

**Revenue — weak/slow networks (ADR-035)**

* **FIXED: an offline or very slow launch served ZERO ads for the entire
  session**, even after the network returned seconds later. The consent flow ran
  exactly once per launch; if its info update failed, `canRequestAds()` stayed
  false and nothing ever re-asked. A failed consent flow is now retried
  (rate-limited). A user who simply *declined* is still never re-prompted.
* **FIXED: banner and native slots mounted on the first frame stayed blank for
  5 minutes on every new install.** The consent gate resolves after the config
  gate, so the first-frame load failed fast and re-armed only after the
  5-minute failure cooldown. Loads now wait for consent to settle, and a
  gate-blocked slot re-checks with a short exponential backoff instead.
* **FIXED: a failed banner auto-refresh destroyed the live banner.** The same
  `BannerAd`'s `onAdFailedToLoad` also fires on a failed AdMob-driven refresh —
  routine on a weak network. The seam disposed the mounted ad, closed its
  paid-event stream (silently ending revenue reporting for that placement) and
  raised "Bad state: Future already completed".
* **FIXED: adaptive banners never reloaded on rotation/fold (ADR-036)** — the ad
  kept the old orientation's width for the rest of the session, including every
  refresh.

**Policy**

* **FIXED: the mandatory rewarded-interstitial SKIP button was rendered
  off-screen at large accessibility text scales (ADR-038)** — an AdMob-required
  opt-out became unreachable. The consent/ATT primers became un-escapable dead
  ends the same way. All three screens now scroll.
* **FIXED: a raw platform error from ATT aborted the whole consent flow
  (ADR-034)** — no info update, no GDPR form, no privacy-options entry point.
  ATT and GDPR are independent regimes: ADR-031 established that an ATT
  *denial* must not suppress a required form; an ATT *crash* must not either.
* **FIXED: a failed/timed-out consent flow hid the privacy-options entry
  point** while ads kept serving from cached consent (invariant 2 / GDPR).
* **FIXED: an inline adaptive banner whose height could not be resolved was
  rendered in a zero-height box** — a loaded, billable, unviewable impression.

**Robustness (ADR-034, ADR-037)**

* **FIXED: a throwing frequency-cap store or gate inside `show()` left the
  full-screen coordinator claimed forever**, permanently blocking *every*
  full-screen format for the session.
* **FIXED: a `PlatformException`/`MissingPluginException` from any `load()`
  pinned that slot at `AdLoading` forever** with no retry armed.
* **FIXED: a device clock that was ahead when an ad showed blocked every
  full-screen ad forever, across restarts.** Future-dated timestamps are now
  ignored and pruned.

**Docs**

* Documented the required iOS `SKAdNetworkItems` (missing entries cost iOS
  revenue silently) and clarified that client-driven ATT and the AdMob console
  IDFA message are mutually exclusive.
* Fixed the §7 testing snippet, which crashed verbatim under non-blocking init.

**Testing**

* `FakeAdSdk` gains `onConsentInfoUpdate` for modelling an offline launch that
  later recovers.

## 2.0.1

- Docs: added a "Set up with AI" README section with copy-paste new-setup and v1→v2 migration prompts. No code changes.

## 2.0.0

Ground-up rewrite targeting `google_mobile_ads ^9.0.0`. **Breaking** — see
[MIGRATION](MIGRATION.md) for the field-by-field and
symbol-by-symbol mapping.

* **NEW**: Rewarded interstitial format with the policy-mandated intro/skip
  screen enforced by construction (`RewardedIntroScreen` + injected presenter).
* **NEW**: Frequency capping — per-format time/count caps AND a global
  cross-format cap, persisted across restarts.
* **NEW**: Interstitial user-action pacing (`recordUserAction` +
  `minActionsBetween`), opt-in by first use.
* **NEW**: Server-side verification options for rewarded formats.
* **NEW**: `onPaidEvent` impression-level revenue callback for every format.
* **NEW**: `package:ad_flow/ad_flow_testing.dart` ships `FakeAdSdk` so apps
  can unit-test their ad integration.
* **NEW**: Experimental Next-Gen GMA SDK opt-in on Android via
  `--dart-define=USE_NEXT_GEN_SDK=true` (no Dart changes).
* **NEW**: Non-blocking `AdFlow.initialize()` — builds the graph synchronously
  and returns immediately; consent/ATT/SDK-init run in the background. Render
  your first frame at once (no `FutureBuilder<AdFlow>` spinner). Optional
  `Future<bool> ads.whenReady` awaits the consent gate. Nothing loads before
  the gate opens (ADR-032).
* **NEW**: Opt-in consent & ATT priming screens — the v2 equivalent of v1's
  `initializeWithExplainer`, now decoupled from `BuildContext` via presenters
  (`attExplainer`/`consentExplainer` on `initialize`, ready-made
  `AttExplainerScreen`/`ConsentExplainerScreen`). Supplying `attExplainer`
  enables client-driven ATT (iOS). Additive — pass nothing for today's
  UMP-driven behaviour (ADR-030).
* **IMPROVED**: Architecture — dependency injection everywhere, no static
  global config; one `AdSdk` seam is the only door to the plugin; state is
  `ValueListenable<AdLoadState>`.
* **IMPROVED**: Consent — UMP wrapped once into `ConsentGateway` Futures;
  ATT handled by UMP (dependency on `app_tracking_transparency` removed);
  consent failures degrade gracefully with a typed `lastError`.
* **IMPROVED**: Retries — exponential backoff with jitter, cooldown, then
  automatic re-arm (v1 never re-armed banner/native loads).
* **FIXED**: App-open ads no longer fire after Control Center / permission
  dialogs / app switcher (v1 treated iOS `inactive` as backgrounding);
  foreground detection now uses `AppStateEventNotifier`; 4-hour expiry
  enforced with discard-and-reload.
* **FIXED**: `isUsingTestAds` false positives — test mode is an explicit
  config flag, never derived from resolved IDs.
* **BREAKING**: Requires Flutter ≥ 3.38.1, Dart ≥ 3.10, iOS 13+,
  Android minSdk 24 / compileSdk 36 (from google_mobile_ads 9.x).
* **BREAKING**: All v1 managers, mixins, Easy* widgets and the broad
  `google_mobile_ads` re-export are gone — see MIGRATION §7.

## 1.3.18

* **NEW**: `EasyBannerAd` now supports optional `SafeArea` wrapping ([#6](https://github.com/faizahmaddae/ad_flow/pull/6))
  - Added `useSafeArea` parameter (default: `true`) to prevent extra black space
  - Set to `false` when the banner is already inside a `SafeArea` or `Scaffold` that handles insets
  - Works for fixed-size, adaptive, and collapsible banners
* **IMPROVED**: Extracted `_wrapWithSafeArea()` helper in `EasyBannerAd` for cleaner SafeArea logic
* **IMPROVED**: Test suite expanded to 1035 tests
* **IMPROVED**: Branch protection enabled on `main` (requires PR review before merge)

## 1.3.17

* Re-release of v1.3.16 (no code changes)

## 1.3.16

* **FIX**: App Open ad no longer shows immediately after closing an interstitial or rewarded ad
  - OS lifecycle (`paused → resumed`) from fullscreen ad overlays was mistaken for a real foreground event
  - Added fullscreen-ad suppression with 5-second grace period in `AppLifecycleReactor`
  - `InterstitialAdManager` and `RewardedAdManager` now signal showing/dismiss to the reactor
* **IMPROVED**: Example launcher now distinguishes "initialized" from "can request ads"
  - Shows 3 states: Initializing, Initialized (No Consent), AdFlow Ready
  - No longer shows "Initializing…" forever when consent is denied
* **IMPROVED**: Test suite expanded to 1031 tests

## 1.3.15

* **IMPROVED**: Comprehensive README rewrite with step-by-step integration guide
  - Added callbacks reference tables for all 5 ad types
  - Added status listeners documentation
  - Added `ignoreCooldown` interstitial example
* **IMPROVED**: Restructured example app with focused per-ad-type demos
  - Launcher menu with navigation to Banner, Interstitial, Rewarded, Native, App Open examples
  - All-in-one demo page retained for quick overview
* **IMPROVED**: Added CI/CD with GitHub Actions
  - Automated format, analyze, and test on push/PR
  - Auto-publish to pub.dev on version tag push
* **IMPROVED**: Expanded test suite to 1015 tests
* **INTERNAL**: Added `AdSdk` abstraction and `AdManagerMixin` for testability
* **INTERNAL**: Added `PrivacyRequirementMixin` for consent checks

## 1.3.14

* **NEW**: Non-blocking initialization for instant app startup
  - App can start immediately without waiting for AdFlow to initialize
  - Ads load in background while users interact with the app
  - Dramatically improves user experience on slow networks
* **NEW**: `waitForInit()` method - waits for initialization to complete
  - Returns `Future<bool>` indicating if ads can be requested
  - Returns immediately if already initialized
  - Use for fullscreen ads (interstitial, rewarded) before showing
* **NEW**: `initStream` - broadcast stream that emits when initialization completes
  - Widgets can subscribe and react when AdFlow becomes ready
  - Useful for complex scenarios requiring custom ad loading
* **IMPROVED**: `EasyBannerAd` and `EasyNativeAd` are now fully reactive
  - Automatically subscribe to `initStream` on mount
  - Auto-load ads when AdFlow initialization completes
  - No code changes required - existing widgets work seamlessly
* **IMPROVED**: Test coverage expanded from 309 to 328 tests
  - Added tests for `waitForInit()` behavior
  - Added tests for reactive widget initialization
  - Added tests for stream subscription cleanup

## 1.3.13

* **FIX**: Ad managers now properly guard against dispose-during-retry crashes
  - Added `_isDisposed` flag to `InterstitialAdManager`, `RewardedAdManager`, `AppOpenAdManager`, `NativeAdManager`
  - Retry loops now exit early if manager is disposed mid-operation
  - Prevents `setState() called after dispose()` errors in edge cases
* **FIX**: Status listener iteration is now safe from concurrent modification
  - All ad managers now use `List.of()` when notifying listeners
  - Prevents `ConcurrentModificationError` if listener removes itself during callback
* **FIX**: Removed unnecessary `meta` import in `ad_service.dart`
* **IMPROVED**: Test coverage expanded from 227 to 309 tests
  - Added comprehensive tests for `EasyPrivacySettingsButton` and `PrivacySettingsListTile`
  - Added dispose guard tests for all ad managers
  - Added listener safety tests for concurrent modification scenarios

## 1.3.12

* **FIX**: Splash screen remains too long when AdMob initialization is slow ([#4](https://github.com/faizahmaddae/ad_flow/issues/4))
  - Added smart timeouts with sensible defaults to prevent indefinite blocking
  - `consentNetworkTimeout` (default: 10s) - Timeout for consent info network request, falls back to cached status
  - `sdkInitTimeout` (default: 8s) - Timeout for Mobile Ads SDK initialization, retries in background
  - `coldStartAdTimeout` (default: 3s) - Timeout for cold-start app open ad loading
  - Consent dialogs are NOT affected - they always wait for user interaction (compliance)
  - Zero code changes required - existing apps get faster initialization automatically
* **IMPROVED**: Background retry for SDK initialization if timeout occurs
* **IMPROVED**: Cold-start app open ads now use bounded timeout instead of blocking indefinitely

## 1.3.11

* **FIX**: `AppOpenAdManager.addStatusListener` callback now fires correctly ([#3](https://github.com/faizahmaddae/ad_flow/issues/3))
  - Status listeners were not notified when using `showAdIfAvailable()`
  - Now properly calls `_notifyStatusListeners()` on show/dismiss/fail events
* **FIX**: iOS App Store rejection for GDPR shown after ATT denial ([#2](https://github.com/faizahmaddae/ad_flow/issues/2))
  - Added `skipGdprConsentIfAttDenied` config option (default: `true`)
  - When user selects "Ask App Not to Track", GDPR consent UI is skipped
  - Prevents Apple Guideline 5.1.1 rejections
  - Set to `false` if you legally require showing GDPR consent regardless of ATT
* **NEW**: `ConsentManager.lastAttStatus` and `isAttDenied` getters
  - Access the iOS ATT authorization status after consent gathering

## 1.3.10

* **NEW**: `EasyBannerAd` now supports custom ad sizes
  - Use `EasyBannerAd(adSize: AdSize.mediumRectangle)` for fixed-size banners
  - Supports all standard sizes: `banner`, `largeBanner`, `mediumRectangle`, `leaderboard`, etc.
  - Fixed-size banners skip orientation handling for better performance
  - Priority: `adSize` > `collapsible` > adaptive (default)

## 1.3.9

* **FIX**: Export `BannerAdListener` from `google_mobile_ads` (fixes [#1](https://github.com/faizahmaddae/ad_flow/issues/1))
  - Allows users to create custom-sized `BannerAd` instances directly
* **NEW**: Added `BannerAdManager.loadBanner()` method for custom ad sizes
  - Load banners with specific sizes like `AdSize.mediumRectangle` (300x250) for dialogs
  - Same consent/disabled checks and callbacks as `loadAdaptiveBanner()`

## 1.3.8

* **NEW**: Mediation support for third-party ad networks
  - Added `MediationHelper` class for forwarding consent to mediation networks
  - Built-in support for Unity Ads and AppLovin with convenience methods
  - Register custom adapters for any mediation network
  - Consent auto-forwarded during `initialize()` / `initializeWithExplainer()`
  - See `doc/MEDIATION_SETUP.md` for complete integration guide
* **DOCS**: Added comprehensive mediation documentation
* **IMPROVED**: Updated copilot-instructions.md with mediation patterns

## 1.3.7

* **FIX**: `NativeAdWidget` now respects `AdsEnabledManager.isDisabled` on initial build
* **IMPROVED**: Added comprehensive tests for `EasyNativeAd` and `NativeAdWidget` ads-disabled behavior

## 1.3.6

* **NEW**: `EasyNativeAd` now collapses when ads fail to load (no more empty white space)
  - Added `hideOnLoading` parameter (default: `true`) - collapses while loading
  - Added `hideOnError` parameter (default: `true`) - collapses on load failure (e.g., no fill)
  - Set to `false` to show loading/error widgets with reserved height
* **FIX**: Removed double semicolon in `BannerAdManager` causing static analysis warning
* **IMPROVED**: Better UX for fixed-height layouts like `bottomNavigationBar`

## 1.3.5

* **FIX**: All ad managers now respect `AdsEnabledManager.isDisabled` state
  - `loadAd()` and `showAd()` check disabled state before proceeding
  - Fixes race condition where `disableAds()` in `onComplete` was too late
  - Affected managers: `BannerAdManager`, `InterstitialAdManager`, `RewardedAdManager`, `AppOpenAdManager`, `NativeAdManager`
* **DOCS**: Updated copilot-instructions.md with timing warning for disabling ads

## 1.3.4

* **FIX**: Applied `dart format` to all files for pub.dev static analysis compliance

## 1.3.3

* **IMPROVED**: Code quality improvements across all ad managers
  - Extracted magic numbers to named constants for better maintainability
  - Added explicit types for improved type safety in `AdFlowConfig`
  - Fixed potential memory leaks in dispose methods (banner, interstitial, app open)
* **IMPROVED**: Selective ad type preloading
  - `preloadAds()` now only preloads ad types that have real IDs configured
  - Added `hasBannerConfigured`, `hasInterstitialConfigured`, etc. getters
  - Use only the ad types you need without loading unnecessary ads
* **FIX**: `reset()` now properly calls `AdFlowConfig.resetCurrent()`
  - Previously config state persisted after reset, now fully resets
* **FIX**: Status listeners properly cleaned up in dispose methods
* **IMPROVED**: Simplified example files
  - Replaced complex demo pages with two clean, reactive examples
  - `example_with_explainer.dart` - GDPR-friendly with explainer dialog
  - `example_without_explainer.dart` - Direct initialization
  - Both examples demonstrate reactive UI with status listeners

## 1.3.2

* **NEW**: Centralized error handling with `AdFlowError` and `errorStream`
  - Subscribe to `AdFlow.instance.errorStream` for all ad-related errors
  - Use `AdFlow.instance.setErrorCallback()` for simpler callback-based handling
  - Errors include type, code, message, ad unit ID, and timestamp
  - Supports logging to analytics, crash reporting, or custom UI
* **NEW**: Comprehensive native ad factory documentation
  - Added `doc/NATIVE_ADS_SETUP.md` with platform code examples
  - Android (Kotlin) and iOS (Swift) factory implementations
  - Layout XML and XIB templates
* **BREAKING**: Removed deprecated `AdConfig` class
  - Use `AdFlowConfig.current` for static access to config values
  - Use `AdFlow.instance.config` for instance-based access
  - Cleaner API with no deprecation warnings
* **IMPROVED**: Simplified consent flow to match Google's official samples
  - Sequential popup handling prevents stacking
  - Explainer dialogs only shown when consent is actually needed

## 1.3.1

* **NEW**: Added `AdFlow.instance.reset()` for testing
  - Enables proper unit testing of singleton state
  - Clears all managers and resets initialization
* **FIX**: Fixed barrel export to use correct file (`ad_service.dart`)
* **FIX**: Fixed `use_build_context_synchronously` warnings in `BannerAdManager`
* **IMPROVED**: Added lazy initialization for ad managers
  - Managers only created when first accessed
  - Better memory efficiency for apps using subset of ad types
* **IMPROVED**: Expanded test coverage from 140 to 185 tests
  - Added `AdFlow` singleton tests
  - Added `EasyBannerAd` widget tests
  - Added `ConsentManager` tests
* Removed duplicate `ad_flow_service.dart` file

## 1.3.0

* **NEW**: Added `EasyPrivacySettingsButton` widget for GDPR compliance
  - Auto shows/hides based on privacy options requirement
  - Opens official Google privacy options form
  - Customizable text, icon, and style
* **NEW**: Added `PrivacySettingsListTile` for settings screens
* **FIX**: `initializeWithExplainer()` now properly checks AdsEnabledManager
  - Previously skipped "Remove Ads" check, now matches `initialize()` behavior
* **FIX**: `isPrivacyOptionsRequired()` now returns correct cached value
  - Was incorrectly returning `canRequestAds` instead of privacy options status
* Added production example with complete implementation guide
* Updated documentation with privacy button usage examples

## 1.2.0

* **NEW**: Added `RewardedAdManager` for rewarded video ads
  - Watch ads to earn in-app rewards (coins, lives, etc.)
  - Automatic preloading and retry logic
  - Reward callbacks with type and amount
  - Status listeners for UI updates
* Added `androidRewardedAdUnitId` and `iosRewardedAdUnitId` to `AdFlowConfig`
* Added `TestAdUnitIds.rewarded` for testing
* Re-exported `RewardedAd` and `RewardItem` from google_mobile_ads
* Updated example app with rewarded ads demo page

## 1.1.0

* **BREAKING**: Added `AdFlowConfig` for runtime configuration of ad unit IDs
* Users can now configure ad unit IDs without modifying package source code
* Added `AdFlowConfig.testMode()` factory for easy development/testing setup
* Added `TestAdUnitIds` class with Google's official test ad unit IDs
* `AdConfig` is now a proxy that reads from `AdFlowConfig`
* Updated example app to demonstrate new configuration pattern

## 1.0.2

* Added explicit platform support declaration for Android and iOS

## 1.0.1+1

* Code formatting fixes for pub.dev static analysis compliance

## 1.0.1

* Initial release
* Banner ads (adaptive and collapsible)
* Interstitial ads with cooldown management
* App open ads with lifecycle handling
* Native ads with factory support
* GDPR/ATT consent management via UMP SDK
* iOS App Tracking Transparency support
* Remove Ads feature with persistence
* Multi-language consent dialogs (English, Spanish, Persian)
