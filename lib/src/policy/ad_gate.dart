import 'package:flutter/foundation.dart';

import '../core/ad_block_reason.dart';

/// The PERMISSION gate every controller consults: may this slot request
/// (or keep serving) an ad right now?
///
/// - [canLoad]/[loadBlockReason]: request configuration applied AND consent
///   settled AND ads enabled (Remove-Ads off). Guards invariant 1 — no
///   `load()` before consent — and the config-before-load ordering
///   (review-fix #5 / ADR-028).
/// - [showBlockReason]: the cheap live subset used on the show path.
///
/// Frequency caps and the full-screen coordinator are deliberately NOT here
/// (3.0): they are SHOW-pacing concerns owned by the controllers, and the
/// one composed query that mixed them in (`canShow`) was an unfixably racy
/// footgun — see the note at the end of this file.
class AdGate {
  /// Creates a gate.
  ///
  /// [canRequestAds] is the *cheap, current* consent answer (wire it to
  /// `AdSdk.canRequestAds`) — it must NOT re-run the consent flow.
  /// [isEnabled] reflects the app's Remove-Ads state.
  /// [settleRequestConfig] joins (and if needed re-attempts) the bounded
  /// `updateRequestConfiguration` apply and answers whether loads may
  /// proceed with respect to it — `false` blocks the load with
  /// [AdBlockReason.requestConfigNotApplied] (the fail-closed policy path,
  /// 4.0). It must be BOUNDED (the facade's attempts are) so the gate never
  /// parks a load indefinitely. Omit it when config timing is not in play.
  AdGate({
    required Future<bool> Function() canRequestAds,
    required bool Function() isEnabled,
    Future<bool> Function()? settleRequestConfig,
    Future<void> Function()? settleConsent,
    Future<bool> Function()? settleConsentForwarding,
    int Function()? consentGeneration,
  }) : _canRequestAds = canRequestAds,
       _isEnabled = isEnabled,
       _settleRequestConfig = settleRequestConfig,
       _settleConsent = settleConsent,
       _settleConsentForwarding = settleConsentForwarding,
       _consentGeneration = consentGeneration;

  final Future<bool> Function() _canRequestAds;
  final bool Function() _isEnabled;
  final Future<bool> Function()? _settleRequestConfig;
  final Future<void> Function()? _settleConsent;
  final int Function()? _consentGeneration;

  /// The cheap, synchronous "are ads currently enabled?" answer (the injected
  /// [isEnabled] predicate: Remove-Ads off AND the owning graph still alive).
  ///
  /// A controller reads this in the SAME synchronous turn it publishes
  /// `AdLoaded`, to close the `disableAds()` in-flight-load race: a disable (or
  /// graph dispose) landing while a request is in flight cannot be caught by
  /// `recheckGate`, which no-ops on an `AdLoading` controller (no handle yet),
  /// so the controller instead re-checks this immediately before installing the
  /// freshly-loaded handle and drops it if ads are no longer enabled. A pure
  /// bool — it never throws, so (unlike the fallible consent read) it can never
  /// yield a transient `internalError` that would wrongly drop good inventory.
  /// Mirrors [consentGeneration]: a getter over an injected callback, not a new
  /// subsystem (5.1.2).
  bool get isEnabled => _isEnabled();

  /// A monotonically-increasing counter bumped on every consent MUTATION.
  ///
  /// A controller captures this right after its load passes the gate and
  /// compares it once the ad actually installs: if it advanced in between, a
  /// consent change landed WHILE the request was in flight, so the ad carries
  /// a stale consent/forwarding state and must be dropped and re-requested
  /// (release gate #2 — the mid-load window). 0 when consent tracking is not
  /// wired (isolated controller tests).
  int get consentGeneration => _consentGeneration?.call() ?? 0;

  /// Joins (and if needed re-attempts) the bounded consent-forwarding barrier
  /// — the app's `forwardConsent`. Answers whether a MEDIATION-CAPABLE load may
  /// proceed: `false` blocks the load with [AdBlockReason.consentNotForwarded]
  /// (the fail-closed default), so no partner request goes out before its
  /// privacy signal is forwarded. Checked only AFTER consent is granted (a
  /// declined user makes no request). Must be BOUNDED so the gate never parks a
  /// load indefinitely. Null when the publisher did not supply `forwardConsent`.
  final Future<bool> Function()? _settleConsentForwarding;

  /// Whether [slot] may load an ad now.
  Future<bool> canLoad(String slot) async =>
      await loadBlockReason(slot) == null;

  /// Why [slot] may not load right now, or null if it may (ADR-045).
  ///
  /// [canLoad] is this, collapsed to a bool. Controllers keep the reason so an
  /// app can tell a gate-blocked slot apart from an idle one.
  ///
  /// **Never throws.** The collaborators behind it do throw in the wild — the
  /// plugin's `canRequestAds()` force-unwraps its channel result, and an
  /// injected consent gateway can reject through the settle callback. An
  /// escaping throw used to pin the calling controller at `AdLoading` forever
  /// (its own re-entry guard then rejects every later load) with an unhandled
  /// async error on top. Indeterminate permission is now an answer:
  /// [AdBlockReason.internalError] — blocked for the moment, re-checked on the
  /// controller's backoff (4.0 audit).
  Future<AdBlockReason?> loadBlockReason(String slot) async {
    try {
      if (!_isEnabled()) return AdBlockReason.adsDisabled;
      // Never request an ad before request configuration is applied — an
      // on-demand banner/native mounted on the first frame (ADR-032) can reach
      // here while the background init/config is still in flight; loading now
      // would send an untagged/untest-flagged first request (review-fix #5).
      // The settle callback JOINS the bounded apply attempt; when it answers
      // false (the apply failed and the policy is fail-closed), the load is
      // refused — visibly, with retries continuing in the background (4.0).
      if (!(await _settleRequestConfig?.call() ?? true)) {
        return AdBlockReason.requestConfigNotApplied;
      }
      // Then wait for the consent flow to actually SETTLE, rather than reading
      // a still-false canRequestAds() and failing fast.
      //
      // This closes the gap ADR-032 opened. Startup is non-blocking, so the
      // app renders and mounts its banner/native on the first frame — but the
      // config gate above (SDK init, no user interaction, ~1s) always opens
      // well BEFORE consent (a network-bound info update, and possibly an ATT
      // prompt and a GDPR form the user must read). So a first-frame view ad
      // used to arrive here, get a hard `false`, go idle and re-arm only after
      // RetryConfig's 5-minute cooldown — leaving every new install with blank
      // banner and native slots for the first five minutes of its first
      // session.
      //
      // The callback also RE-ATTEMPTS a consent flow that previously FAILED
      // (see AdFlow._settleConsent), which is what lets an offline launch
      // start serving ads once the network returns instead of staying dead all
      // session.
      await _settleConsent?.call();
      if (!_isEnabled()) return AdBlockReason.adsDisabled;
      if (!await _canRequestAds()) return AdBlockReason.consentNotGranted;
      // Ads ARE permitted. Before the (mediation-capable) request goes out,
      // make sure the app's per-network privacy signal has been forwarded —
      // fail-CLOSED by default: a partner must not receive a request without
      // its GDPR/US-state/age flag. Runs the forwarder once per consent
      // generation, joined by concurrent loads, and re-attempts a failure on
      // the controller's backoff (4.1 audit / release gate).
      if (!(await _settleConsentForwarding?.call() ?? true)) {
        return AdBlockReason.consentNotForwarded;
      }
      return null;
    } catch (error, stack) {
      _reportGateError(error, stack);
      return AdBlockReason.internalError;
    }
  }

  /// Why [slot] may not SHOW an already-loaded ad right now, or null if it
  /// may — the cheap, current checks only (2026-07 audit).
  ///
  /// Unlike [loadBlockReason] this never awaits [AdGate]'s config gate or the
  /// consent settle: a warm handle exists, so both were already satisfied at
  /// load time, and `FullScreenAdControllerBase.show()` calls this while
  /// HOLDING the shared coordinator claim — joining a network-bound consent
  /// re-attempt there (up to the 30s info-update timeout) would freeze every
  /// full-screen format behind one controller's show call. The
  /// `canRequestAds()` read is still live, so a consent withdrawal between
  /// load and show is still respected.
  Future<AdBlockReason?> showBlockReason(String slot) async {
    try {
      if (!_isEnabled()) return AdBlockReason.adsDisabled;
      if (!await _canRequestAds()) return AdBlockReason.consentNotGranted;
      return null;
    } catch (error, stack) {
      _reportGateError(error, stack);
      return AdBlockReason.internalError;
    }
  }

  /// Surfaces a contained collaborator throw without letting it escape —
  /// visible in logs/crash reporting via `FlutterError.onError`, never a
  /// wedged controller or an unhandled async error.
  static void _reportGateError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'ad_flow',
        context: ErrorDescription(
          'while evaluating the ad permission gate (contained; the slot is '
          'blocked with AdBlockReason.internalError and will re-check)',
        ),
      ),
    );
  }
}

// 3.0: `AdGate.canShow` is REMOVED. It re-embodied the exact
// check-then-await-then-act race ADR-024 closed (two callers could both read
// "nothing is showing" and both proceed), had no in-package caller since
// ADR-024, and survived 2.x only as public API with a warning label (review
// finding #6). For a UI hint ("gray out the Watch Ad button"), combine
// `coordinator.visible`, `controller.state` and `caps.canShow(slot)` —
// and treat the answer as a hint, never as permission to show.
