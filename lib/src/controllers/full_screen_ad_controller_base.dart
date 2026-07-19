import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ad_flow_config.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../core/ad_load_state.dart';
import '../core/callback_guard.dart';
import '../core/load_watchdog.dart';
import '../policy/ad_gate.dart';
import '../policy/frequency_cap_policy.dart';
import '../policy/full_screen_ad_coordinator.dart';
import '../policy/retry_policy.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';

/// Shared engine for all full-screen formats (interstitial, rewarded,
/// rewarded interstitial, app open).
///
/// Encodes the invariants once:
/// - consent/enabled gate before every load (invariant 1);
/// - retry with backoff, then cooldown, then auto re-arm (ADR-008);
/// - single-use handles: dispose on dismiss/fail and reload immediately so
///   one ad is always warm (invariant 7, ADR-011);
/// - `FullScreenAdCoordinator` entered on show and exited on dismiss/fail,
///   so no two full-screen ads ever overlap;
/// - impressions recorded in the frequency caps when the ad shows.
abstract class FullScreenAdControllerBase implements FullScreenAdController {
  /// Wires the shared engine. [slot] names this format for the gate/caps
  /// (e.g. `'interstitial'`). [adUnitId] is already platform-resolved.
  FullScreenAdControllerBase({
    required AdSdk sdk,
    required AdGate gate,
    required FrequencyCapPolicy caps,
    required FullScreenAdCoordinator coordinator,
    required this.slot,
    required this.adUnitId,
    Duration? maxAdAge,
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
    void Function(String slot, AdBlockReason reason)? onBlocked,
    DateTime Function()? now,
  }) : _sdk = sdk,
       _gate = gate,
       _caps = caps,
       _coordinator = coordinator,
       _maxAdAge = maxAdAge,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid,
       _onBlocked = onBlocked,
       _now = now ?? DateTime.now;

  /// The gate/cap slot name of this format.
  final String slot;

  /// The platform-resolved ad unit ID this controller loads.
  final String adUnitId;

  final AdSdk _sdk;

  /// The seam, for subclasses' [loadHandle] implementations.
  @protected
  AdSdk get sdk => _sdk;

  final AdGate _gate;
  final FrequencyCapPolicy _caps;
  final FullScreenAdCoordinator _coordinator;
  final Duration? _maxAdAge;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;
  final void Function(String slot, AdBlockReason reason)? _onBlocked;
  final DateTime Function() _now;
  DateTime? _loadedAt;

  AdBlockReason? _lastBlockReason;

  /// Why this slot last refused to load or show, or null if nothing is
  /// blocking it (ADR-045). A gate-blocked load reports [AdIdle], which is also
  /// what "not requested yet" looks like — this is what tells them apart, and
  /// it is the only way an app can learn that (say) a rewarded show was refused
  /// by a frequency cap rather than by a missing ad.
  AdBlockReason? get lastBlockReason => _lastBlockReason;

  /// Records a refusal and notifies `AdFlow.onAdBlocked`.
  ///
  /// The app callback is ISOLATED: it fires from inside load/show
  /// transitions, so a throw from it used to corrupt the very transition
  /// that reported the refusal (4.0 audit).
  @protected
  void noteBlocked(AdBlockReason reason) {
    _lastBlockReason = reason;
    final onBlocked = _onBlocked;
    if (onBlocked != null) {
      guardedCallback(() => onBlocked(slot, reason), debugName: 'onAdBlocked');
    }
  }

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  FullScreenAdHandle? _handle;
  StreamSubscription<FullScreenAdEvent>? _contentSub;
  StreamSubscription<AdPaidEvent>? _paidSub;
  Timer? _timer;
  int _attempts = 0;
  int _gateAttempts = 0;
  bool _enteredCoordinator = false;

  /// The consent generation the warm ad was REQUESTED under (release gate #2).
  /// A consent mutation bumps `AdGate.consentGeneration`; when it no longer
  /// matches, the warm ad carries a stale consent/forwarding state and is
  /// dropped-and-reloaded — on load completion (the mid-load window) and on
  /// `recheckGate` (the already-warm case). One internal mechanism, no public
  /// surface.
  int _loadedGeneration = 0;

  /// The ad reached the screen (AdShowedEvent) but has not been dismissed yet,
  /// so its impression is not recorded yet (ADR-040).
  bool _impressionPending = false;
  bool _disposed = false;

  /// The seam load call for this format.
  @protected
  Future<FullScreenAdHandle> loadHandle();

  /// Extra per-format show precondition (e.g. interstitial user-action
  /// pacing). Runs after the gate allows.
  @protected
  bool canShowExtra() => true;

  /// Hook invoked right after a show is dispatched.
  @protected
  void onShown() {}

  /// Hook invoked right after a load succeeds (e.g. to timestamp the ad).
  @protected
  void onLoaded() {}

  /// Drops the current handle (without showing it) and preloads a fresh
  /// one — used by app-open to discard expired ads.
  ///
  /// A no-op while a load is already in flight (same reasoning as review
  /// finding #4 on `NativeAdController.reload()`): today's one caller
  /// (`AppOpenAdController.show()`) only invokes this after confirming
  /// `isReady` (implies `AdLoaded`), so this guard is currently
  /// unreachable in practice — kept as defense-in-depth since this is a
  /// `@protected` method a future subclass could call from elsewhere.
  @protected
  void discardCurrentAd() {
    if (_disposed || _state.value is AdLoading) return;
    _dropHandle();
    _state.value = const AdIdle();
    unawaited(load());
  }

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// Whether a loaded ad is warm and ready to show.
  bool get isReady => _state.value is AdLoaded && _handle != null;

  /// The warm handle, for subclasses that must talk to the loaded ad
  /// directly (e.g. the rewarded formats applying runtime SSV). Null unless
  /// [isReady].
  @protected
  FullScreenAdHandle? get currentHandle => _handle;

  /// Which network filled the warm ad (mediation observability), or null
  /// when nothing is loaded / the SDK reported nothing.
  AdResponseSummary? get response => _handle?.response;

  /// Whether the warm ad has outlived its maximum age and must not be shown.
  ///
  /// Google documents full-screen ads as expiring after ~1 hour (4 hours for
  /// app-open): a stale ad may fail to display, or display but not count.
  /// [show] discards-and-reloads an expired ad instead of showing it, and an
  /// expiry timer proactively replaces one that goes stale while warm
  /// (2026-07 audit; generalizes what app-open always did).
  bool get isExpired {
    final loadedAt = _loadedAt;
    final maxAdAge = _maxAdAge;
    if (loadedAt == null || maxAdAge == null) return false;
    return _now().difference(loadedAt) >= maxAdAge;
  }

  /// Arms the proactive expiry replacement for the ad just loaded.
  ///
  /// Uses the shared single-slot [_timer]: while `AdLoaded` no retry or
  /// gate-recheck timer can be pending, and any transition out of `AdLoaded`
  /// re-arms [_timer] through its own path. Best-effort — timers do not fire
  /// while the app is suspended, so [show]'s own [isExpired] check remains
  /// the guarantee.
  void _scheduleExpiry() {
    final maxAdAge = _maxAdAge;
    if (maxAdAge == null) return;
    _timer?.cancel();
    _timer = Timer(maxAdAge, () {
      if (_disposed || _state.value is! AdLoaded || !isExpired) return;
      noteBlocked(AdBlockReason.expired);
      discardCurrentAd();
    });
  }

  @override
  Future<void> load() async {
    if (_disposed) return;
    if (_state.value is AdLoading ||
        _state.value is AdLoaded ||
        _state.value is AdShowing) {
      return;
    }
    // Set Loading synchronously, before any await, so a concurrent load()
    // call sees it immediately and bails instead of racing to a second
    // in-flight loadHandle() call (each would overwrite _handle, leaking
    // the loser's ad).
    _state.value = const AdLoading();

    // ONE try around the whole async body — the gate await included. The gate
    // itself no longer throws, but the rule stands regardless of collaborator
    // promises: from the moment AdLoading is written, ANY escape path that is
    // not a state write + timer arm leaves the slot wedged forever (4.0
    // audit; the gate await used to sit outside this try).
    try {
      final blocked = await _gate.loadBlockReason(slot);
      if (_disposed) return;
      if (blocked != null) {
        noteBlocked(blocked);
        // A refused load is a STATE, not a side channel (3.0): consent still
        // pending, Remove-Ads on and "nothing requested yet" used to be
        // indistinguishable AdIdle.
        _state.value = AdBlocked(blocked);
        _scheduleGateRecheck();
        return;
      }

      // Capture the consent generation this request is dispatched under, to
      // detect a consent mutation that lands WHILE the request is in flight
      // (release gate #2 — the mid-load window): the gate already passed, so
      // it is dropped-and-reloaded on completion below rather than by
      // recheckGate (which handles only the already-warm case).
      final requestGeneration = _gate.consentGeneration;

      // Watchdog: the plugin has no load timeout of its own — a callback that
      // never arrives must fail this attempt (and dispose its late handle if
      // one ever shows up) instead of pinning the slot at AdLoading (I-C).
      final handle = await watchAdLoad(
        pending: loadHandle(),
        timeout: _retry.loadTimeout,
        disposeLate: (late) => late.dispose(),
        slot: slot,
      );
      if (_disposed) {
        safeUnawaited(handle.dispose(), debugName: 'handle');
        return;
      }
      if (_gate.consentGeneration != requestGeneration) {
        // Consent mutated while this ad was in flight — it was requested (and
        // its mediation privacy signal forwarded) under the OLD consent. Drop
        // it unshown and reload through the re-forwarded gate, so it never
        // records a stale-consent impression.
        safeUnawaited(handle.dispose(), debugName: 'handle');
        _state.value = const AdIdle();
        unawaited(load());
        return;
      }
      _handle = handle;
      _contentSub = handle.contentEvents.listen(_onContentEvent);
      _paidSub = handle.paidEvents.listen(_dispatchPaid);
      _attempts = 0;
      _gateAttempts = 0;
      _lastBlockReason = null;
      _loadedAt = _now();
      _loadedGeneration = requestGeneration;
      _state.value = const AdLoaded();
      _scheduleExpiry();
      onLoaded();
    } catch (e) {
      // Catch EVERYTHING, not just AdFlowError. The seam's contract says it
      // throws AdFlowError, but a real platform channel violates that freely:
      // MissingPluginException, PlatformException, or the plugin's own
      // canRequestAds() force-unwrapping a null channel result. Before this,
      // such a throw escaped `on AdFlowError`, left the controller pinned at
      // AdLoading (which load()'s own re-entry guard then rejects forever) and
      // armed no retry — one platform hiccup killed the slot for the session.
      if (_disposed) return;
      _state.value = AdFailed(asAdFlowError(e, AdFlowErrorKind.loadFailed));
      _scheduleRetry();
    }
  }

  @override
  Future<void> recheckGate() async {
    if (_disposed) return;
    final state = _state.value;
    if (state is AdLoaded) {
      // A warm ad requested under a now-stale consent generation
      // (consent/privacy changed but ads are still permitted, so the
      // permission check below would pass) must be dropped and reloaded under
      // the fresh gate, or it would show a stale-consent impression (release
      // gate #2). This is the already-warm counterpart of the mid-load check
      // in load(); one internal mechanism.
      if (_loadedGeneration != _gate.consentGeneration) {
        discardCurrentAd();
        return;
      }
      // Cheap current checks only (enabled + live canRequestAds) — the warm
      // ad already passed the full load gate; this asks "is it STILL
      // permitted?" (Remove-Ads bought, consent withdrawn, graph disposed).
      final blocked = await _gate.showBlockReason(slot);
      if (_disposed || blocked == null) return;
      // Indeterminate is not "revoked": a transient channel hiccup while
      // re-checking permission must never destroy the perfectly good warm ad
      // (4.0 audit). Definite answers (adsDisabled, consentNotGranted) drop.
      if (blocked == AdBlockReason.internalError) return;
      if (_state.value is! AdLoaded) return; // changed while awaiting
      _timer?.cancel();
      _dropHandle();
      noteBlocked(blocked);
      _state.value = AdBlocked(blocked);
      _scheduleGateRecheck();
    } else if (state is AdIdle || state is AdFailed || state is AdBlocked) {
      // The gate may have just (re)opened — load() re-checks it itself, so
      // this simply short-circuits the pending backoff.
      if (state is AdFailed) _state.value = const AdIdle();
      await load();
    }
    // AdLoading resolves on its own; AdShowing is on screen — the dismiss
    // path reloads through the gate anyway.
  }

  @override
  Future<bool> show() => showEngine();

  /// The full show engine, shared by every format. [onReward] is forwarded
  /// to the handle for the rewarded formats (their public `show(onReward:)`
  /// overrides call this); the base [show] never passes one.
  ///
  /// [confirm], when supplied, runs AFTER every policy check has passed and
  /// WHILE the coordinator claim is held, immediately before the ad is
  /// dispatched — the rewarded interstitial presents its mandatory intro
  /// there (4.0 audit). Ordering is the point, twice over: (a) every
  /// consent/cap/pacing refusal happens BEFORE the user is promised an ad,
  /// so accepting the intro can no longer end in "no ad, no reward"; (b) the
  /// claim spans the intro, so a warm-return app-open cannot stack over it.
  /// Returning false (the user skipped; report the reason yourself before
  /// returning) or throwing rolls everything back to a warm [AdLoaded].
  @protected
  Future<bool> showEngine({
    OnUserEarnedReward? onReward,
    Future<bool> Function()? confirm,
  }) async {
    if (_disposed) return false;
    if (_state.value is AdShowing) return false; // never double-show
    final handle = _handle;
    if (handle == null || _state.value is! AdLoaded) {
      noteBlocked(AdBlockReason.notReady);
      unawaited(load()); // warm one up for the next natural break
      return false;
    }
    if (isExpired) {
      // Stale inventory (the proactive timer did not fire — e.g. the app was
      // suspended past the ad's maximum age): discard, keep a fresh one warm,
      // show nothing. Showing it risks a failed display, or one that does
      // not count.
      noteBlocked(AdBlockReason.expired);
      discardCurrentAd();
      return false;
    }

    // Atomically check-and-claim the coordinator BEFORE any await — see
    // FullScreenAdCoordinator.tryEnter doc. An await-separated check (via
    // AdGate.canShow, which reads the coordinator too) lets two
    // independently-gated controllers — e.g. interstitial + app open —
    // both observe "nothing is showing" in the same turn and both
    // proceed, so this bypasses gate.canShow's coordinator check and does
    // its own atomic one instead. gate.canLoad + caps.canShow cover the
    // remaining (consent/enabled/frequency-cap) checks.
    if (!_coordinator.tryEnter()) {
      noteBlocked(AdBlockReason.otherAdShowing);
      return false;
    }
    _enteredCoordinator = true;
    // Set Showing synchronously, in the same turn as the coordinator
    // claim above, so a concurrent show() call on THIS controller also
    // sees it immediately and bails.
    _state.value = const AdShowing();

    Future<bool> rejectAndRollBack() async {
      _exitCoordinator();
      if (!_disposed) _state.value = const AdLoaded();
      return false;
    }

    // These preconditions run AFTER the coordinator has been claimed and
    // AdShowing written (both must be synchronous — ADR-024), so any throw in
    // here MUST roll both back. A corrupt shared_preferences backend makes
    // `_caps.canShow` throw a PlatformException, and the plugin's
    // `canRequestAds()` can throw too; before this guard such a throw escaped
    // show() with the coordinator still claimed, permanently blocking EVERY
    // full-screen format (interstitial, rewarded, rewarded-interstitial and
    // app-open) for the rest of the session. Review finding #1 fixed only the
    // symmetric hole around `handle.show()`; this is the other half.
    try {
      // The CHEAP show checks, not loadBlockReason: a warm handle proves the
      // config gate and consent settle already passed at load time, and this
      // runs while holding the coordinator claim — awaiting a network-bound
      // consent re-attempt here would freeze every full-screen format behind
      // it (2026-07 audit). canRequestAds() is still read live, so a consent
      // withdrawal between load and show is still respected.
      final blocked = await _gate.showBlockReason(slot);
      if (blocked != null) {
        noteBlocked(blocked);
        return rejectAndRollBack();
      }
      if (_disposed) return false; // dispose() already rolled everything back
      if (!await _caps.canShow(slot)) {
        noteBlocked(AdBlockReason.frequencyCapped);
        return rejectAndRollBack();
      }
      if (_disposed) return false;
      if (!canShowExtra()) {
        noteBlocked(AdBlockReason.userActionPacing);
        return rejectAndRollBack();
      }
      // The confirm hook (the rewarded-interstitial intro) runs LAST, with
      // every policy check already passed and the claim held. It is
      // user-facing and unbounded — the state is AdShowing throughout, so
      // the expiry timer cannot discard the handle mid-intro and re-entrant
      // show() calls bail on the AdShowing guard.
      if (confirm != null && !await confirm()) {
        return rejectAndRollBack();
      }
      // The confirm hook can outlive the graph (the user backgrounds the
      // app on the intro and the screen is popped): dispose() already
      // released the claim and dropped the handle — do not show.
      if (_disposed) return false;
      // RE-VALIDATE after the unbounded confirm hook (4.1 audit). The checks
      // above ran BEFORE the intro, which the user may sit on for minutes:
      // Remove-Ads can be bought and the warm ad can age past maxAdAge in
      // that window. Re-run the cheap live checks (no network/config join —
      // showBlockReason is the same subset the show path already trusts) and
      // re-check expiry; a stale or no-longer-permitted ad is rolled back
      // rather than shown. internalError is a transient hiccup — proceed
      // (mirrors recheckGate), never waste an accepted intro on a blip.
      if (confirm != null) {
        final after = await _gate.showBlockReason(slot);
        if (_disposed) return false;
        if (after != null && after != AdBlockReason.internalError) {
          noteBlocked(after);
          return rejectAndRollBack();
        }
        if (isExpired) {
          noteBlocked(AdBlockReason.expired);
          // Roll back the claim/state, THEN discard the stale ad + reload.
          await rejectAndRollBack();
          discardCurrentAd();
          return false;
        }
      }
    } catch (_) {
      // Degrade to "don't show", never to "wedged forever".
      return rejectAndRollBack();
    }

    OnUserEarnedReward? onRewardOnce;
    if (onReward != null) {
      // A reward is granted at most once per ad, even if the SDK misfires —
      // and the app's grant callback is isolated, so an app bug inside it
      // cannot corrupt the show flow or become an unhandled platform-callback
      // error (4.0 audit).
      var granted = false;
      onRewardOnce = (reward) {
        if (granted) return;
        granted = true;
        guardedCallback(() => onReward(reward), debugName: 'onReward');
      };
    }
    try {
      await handle.show(onUserEarnedReward: onRewardOnce);
    } catch (e) {
      // The documented AdSdk.show contract says failures arrive via
      // AdFailedToShowEvent, never a rejected Future — but a real
      // implementation can still violate that (ad released between load
      // and show, channel error, mediation failure). Without this guard
      // the coordinator claim and AdShowing state above are never rolled
      // back, wedging every full-screen format for the rest of the
      // session (review finding #1).
      _exitCoordinator();
      _dropHandle();
      if (!_disposed) {
        _state.value = AdFailed(AdFlowError(AdFlowErrorKind.showFailed, '$e'));
        unawaited(load());
      }
      return false;
    }
    _lastBlockReason = null;
    onShown();
    return true;
  }

  void _onContentEvent(FullScreenAdEvent event) {
    if (_disposed) return;
    switch (event) {
      case AdShowedEvent():
        // The SDK confirms the ad is really on screen. The impression is NOT
        // recorded here — it is recorded on dismiss (see below, ADR-040).
        // Coordinator entry already happened synchronously in show().
        _impressionPending = true;
      case AdDismissedEvent():
        // Record the impression HERE, not on AdShowedEvent (ADR-040).
        //
        // Every cap timestamp — including the global cross-format minGap — is
        // stamped from this moment, so the gap between two full-screen ads is
        // measured from when the previous one CLOSED. Stamping it at show time
        // meant the gap ran down while the user was still watching: a 30s
        // rewarded ad under a 15s global gap "used up" the whole gap on
        // screen, so an interstitial could fire the instant the user closed it
        // — two full-screen ads back to back, which is the exact thing the
        // global cap exists to prevent.
        _recordImpressionIfPending();
        // Single-use spent: dispose and immediately preload the next
        // (invariant 7, ADR-011).
        _exitCoordinator();
        _dropHandle();
        _state.value = const AdIdle();
        unawaited(load());
      case AdFailedToShowEvent(:final error):
        // If the ad had already reached the screen, it still counts.
        _recordImpressionIfPending();
        _exitCoordinator();
        _dropHandle();
        _state.value = AdFailed(error);
        unawaited(load()); // AdFailed passes the load guard → AdLoading
      case AdImpressionEvent() || AdClickedEvent():
        break;
    }
  }

  /// Forwards a paid event to the app with its slot tag, isolated (an
  /// analytics-hook bug must never surface as an unhandled stream error).
  void _dispatchPaid(AdPaidEvent event) {
    final onPaid = _onPaid;
    if (onPaid == null) return;
    guardedCallback(
      () => onPaid(event.taggedWithSlot(slot)),
      debugName: 'onPaidEvent',
    );
  }

  /// Records the impression for an ad that reached the screen, exactly once.
  ///
  /// A throwing store must not become an unhandled async error — losing one
  /// recorded impression (slightly loose capping) beats crashing the zone.
  void _recordImpressionIfPending() {
    if (!_impressionPending) return;
    _impressionPending = false;
    unawaited(_caps.recordImpression(slot).catchError((Object _) {}));
  }

  void _exitCoordinator() {
    if (_enteredCoordinator) {
      _coordinator.exit();
      _enteredCoordinator = false;
    }
  }

  void _scheduleRetry() {
    _attempts++;
    _timer?.cancel();
    if (_retry.shouldRetry(_attempts)) {
      _timer = Timer(_retry.nextDelay(_attempts), () {
        // Only act while still in the failed state this timer was armed
        // for — a manual show()-triggered load() (or another retry timer,
        // impossible by construction since _timer is single-slot, but a
        // gate-recheck could not race here either) may have already
        // recovered the controller to AdLoaded/AdShowing by the time this
        // fires. Stomping that back to AdIdle would leak the current
        // handle/subscription and force an unrelated second load (review
        // finding #3).
        if (_disposed || _state.value is! AdFailed) return;
        _state.value = const AdIdle();
        unawaited(load());
      });
    } else {
      _timer = Timer(_retry.cooldown, () {
        if (_disposed || _state.value is! AdFailed) return;
        _attempts = 0;
        _state.value = const AdIdle();
        unawaited(load());
      });
    }
  }

  /// Re-checks the gate after a backoff when a load was blocked (consent not
  /// settled / ads disabled) rather than failed — otherwise a slot whose one
  /// preload attempt happened to land while the gate was shut stays idle
  /// forever with nothing left to prompt a retry.
  ///
  /// Uses [RetryPolicy.gateRecheckDelay] (exponential from baseDelay, capped
  /// at maxDelay) rather than the 5-minute failure cooldown: a closed gate is
  /// a "not yet", not an error, and the common case — consent resolving a
  /// second or two after the first frame — must not cost a five-minute wait.
  void _scheduleGateRecheck() {
    _gateAttempts++;
    _timer?.cancel();
    _timer = Timer(_retry.gateRecheckDelay(_gateAttempts), () {
      if (_disposed) return;
      unawaited(load());
    });
  }

  void _dropHandle() {
    safeUnawaited(_contentSub?.cancel(), debugName: 'subscription');
    safeUnawaited(_paidSub?.cancel(), debugName: 'subscription');
    _contentSub = null;
    _paidSub = null;
    final handle = _handle;
    _handle = null;
    if (handle != null) safeUnawaited(handle.dispose(), debugName: 'handle');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // An ad that reached the screen but is torn down before its dismiss event
    // arrives still happened — record it, or the cap under-counts and the next
    // ad could fire too soon.
    _recordImpressionIfPending();
    _timer?.cancel();
    _timer = null;
    _exitCoordinator();
    _dropHandle();
    _state.dispose();
  }
}
