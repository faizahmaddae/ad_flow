/// Why a load or show was refused (ADR-045).
///
/// A refused load leaves the controller at [AdIdle] — which is also what "no
/// ad has been requested yet" looks like. That ambiguity made the single most
/// common integration question ("why aren't my ads showing?") unanswerable
/// from inside the app: consent never gathered, Remove-Ads still on, and a
/// frequency cap quietly doing its job are all indistinguishable, and the
/// package logs nothing (`avoid_print` is on).
///
/// Read it per slot from `lastBlockReason`, or subscribe once via
/// `AdFlow.onAdBlocked`. This is a **diagnostic**, not control flow: it is
/// deliberately NOT a new `AdLoadState` case, because `AdLoadState` is a
/// `sealed` type and adding a case would break every exhaustive `switch` in
/// every app.
enum AdBlockReason {
  /// `AdFlow.disableAds()` is in effect (the user bought Remove-Ads).
  adsDisabled,

  /// `canRequestAds()` is false: consent has not been granted (the user
  /// declined, or the consent flow has not succeeded yet — e.g. offline).
  consentNotGranted,

  /// The slot's own cap, or the global cross-format cap, refused this show.
  frequencyCapped,

  /// Another full-screen ad is on screen, or one just closed (the
  /// `FullScreenAdCoordinator` is claimed).
  otherAdShowing,

  /// `show()` was called with no warm ad. A load is kicked off in response, so
  /// this usually means "too early" — or that loads are failing; check
  /// `state` for an `AdFailed`.
  notReady,

  /// A per-format precondition refused the show: today only the interstitial's
  /// user-action pacing (`InterstitialConfig.minActionsBetween`).
  userActionPacing,

  /// The warm app-open ad outlived its 4-hour expiry and was discarded rather
  /// than shown.
  expired,

  /// The user chose "skip" on the mandatory rewarded-interstitial intro. Not a
  /// fault — policy working as intended.
  introSkipped,

  /// The SDK request configuration (test devices, COPPA/child-directed and
  /// under-age tags, max content rating) has not been applied, and the
  /// effective [RequestConfigFailurePolicy] forbids loading without it.
  ///
  /// This is fail-CLOSED protection for policy-critical configuration: a
  /// child-directed app must never send untagged requests, and a registered
  /// test device must never receive live ads (invalid-traffic risk), just
  /// because a config call failed at startup. The apply is retried in the
  /// background (rate-limited) and every gate re-check re-joins it, so the
  /// slot recovers the moment it succeeds — observable via `onAdBlocked`
  /// and the `AdBlocked` state, never a silent revenue stop (4.0 audit).
  requestConfigNotApplied,

  /// A collaborator failed while answering the permission question — the
  /// consent channel threw, an injected gateway rejected, or an app-supplied
  /// hook broke (the underlying error is reported via
  /// `FlutterError.reportError`). Indeterminate permission blocks NEW loads
  /// (the controller re-checks on a backoff and recovers when the
  /// collaborator heals) but never drops a LIVE ad — a transient channel
  /// hiccup must not destroy revenue already on screen (4.0 audit).
  internalError,

  /// The publisher supplied `forwardConsent` and it has not completed
  /// successfully yet — the forwarder failed or timed out — while the
  /// effective [MediationConsentFailurePolicy] is `failClosed` (the default).
  ///
  /// This is fail-CLOSED protection for mediation privacy: mediation adapters
  /// must never initialize (they read their privacy flag during
  /// `MobileAds.initialize()`) or receive an ad request before that flag is
  /// forwarded. So the GMA SDK is not initialized and loads are blocked until
  /// forwarding succeeds; the forwarder is retried in the background and every
  /// gate re-check re-joins it, so the slot recovers the moment it succeeds —
  /// observable via `onAdBlocked` and the `AdBlocked` state, never a silent
  /// unsignalled request (release gate). Choose
  /// [MediationConsentFailurePolicy.unsafeFailOpen] to serve anyway (unsafe).
  consentNotForwarded,
}
