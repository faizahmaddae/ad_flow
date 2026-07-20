import 'dart:async';

import '../core/ad_load_state.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Runtime server-side-verification handling shared by the rewarded and
/// rewarded-interstitial controllers (4.1 audit; hardened 5.1).
///
/// Config-time SSV is frozen at startup, but real apps learn the `userId` at
/// login and the per-show `customData` (which mission earned the reward) long
/// after the ad preloaded. [setServerSideVerification] applies an override to
/// the warm ad AND every future load, replacing the config value.
///
/// The load-bearing invariant:
///
/// **A rewarded ad is never externally ready or showable until the LATEST
/// required SSV payload has settled successfully.**
///
/// - **Set while a load is in flight.** The load already dispatched with the
///   previous payload. The override is re-attached in [finalizeLoadedHandle],
///   which the base engine `await`s BEFORE publishing `AdLoaded` — so the ad
///   is never showable carrying the stale payload, and a `show()` from an
///   `AdLoaded` listener always sees the settled value. A re-attach failure
///   there fails the load closed (drop + retry, re-dispatching the override).
/// - **Set on a warm ad.** The ad is made not-ready ([isReady] returns false
///   via [_attaching]) while the new payload attaches, then ready again once
///   it settles — so a concurrent/immediate `show()` cannot use the old
///   payload mid-attach.
/// - **Concurrent updates.** Every update takes a monotonic [_ssvGeneration];
///   only the latest generation's completion resolves readiness or (on
///   failure) drops the ad, so a stale completion arriving out of order cannot
///   clobber the latest value.
/// - **Attach failure on a warm ad.** Drops the now-stale ad (a fresh load
///   re-dispatches with the override) and rethrows, so a caller granting
///   high-value rewards learns its payload did not attach.
mixin RuntimeSsvController on FullScreenAdControllerBase {
  ServerSideVerification? _ssvOverride;

  /// A load was in flight when the override was set — re-attach on install.
  bool _reapplyPending = false;

  /// Monotonic update counter. The highest generation wins, even when native
  /// completions arrive out of order.
  int _ssvGeneration = 0;

  /// A warm-handle attach for the latest generation has not settled yet, so
  /// the ad is not externally ready/showable.
  bool _attaching = false;

  /// The config-time SSV for this format (`_config.ssv`).
  ServerSideVerification? get configuredSsv;

  /// The SSV a load should dispatch with — the runtime override if set, else
  /// the configured value.
  ServerSideVerification? get effectiveSsv => _ssvOverride ?? configuredSsv;

  /// Attaches [ssv] to the (correctly-typed) warm [handle].
  Future<void> attachSsv(FullScreenAdHandle handle, ServerSideVerification ssv);

  /// Not externally ready while a required SSV override is still settling onto
  /// the warm ad — extends the base readiness so `show()` (which gates on
  /// [isReady]) and callers alike observe "not yet".
  @override
  bool get isReady => super.isReady && !_attaching;

  /// Applies [ssv] to the currently warm ad (if any) AND every future load,
  /// replacing the config value.
  ///
  /// Rethrows if attaching to a warm ad fails (and DROPS the now-stale ad so it
  /// can never be shown with the wrong verification). If a load is in flight,
  /// the override is re-attached on completion, before the ad becomes showable.
  Future<void> setServerSideVerification(ServerSideVerification ssv) async {
    _ssvOverride = ssv;
    final generation = ++_ssvGeneration;
    final handle = currentHandle;
    // super.isReady deliberately ignores [_attaching]: a re-attach in flight
    // still has a warm handle to update again with the newer value.
    if (super.isReady && handle != null) {
      // Warm ad: not-ready while the new payload attaches, so a concurrent
      // show() cannot use the old one mid-attach.
      _attaching = true;
      try {
        await attachSsv(handle, ssv);
      } catch (_) {
        // A newer update superseded this one — it owns the outcome; a stale
        // failure must not drop the ad the latest update already validated.
        if (generation != _ssvGeneration) return;
        _attaching = false;
        // The warm ad now carries a stale/failed payload. Drop it and warm a
        // fresh one (re-dispatched with the override) so nothing showable is
        // verified with the wrong data, then surface the failure.
        discardCurrentAd();
        rethrow;
      }
      // Superseded by a newer update — let its completion resolve readiness.
      if (generation != _ssvGeneration) return;
      _attaching = false;
      return;
    }
    // No warm handle to update directly. If a load is in flight it dispatched
    // with the previous payload — re-attach the latest once it installs, in
    // finalizeLoadedHandle (before AdLoaded is published).
    if (state.value is AdLoading) _reapplyPending = true;
  }

  @override
  Future<void> finalizeLoadedHandle() async {
    await super.finalizeLoadedHandle();
    // Loop so an override set DURING this finalization (rare: two rapid updates
    // straddling load completion) still lands the latest — each pass attaches
    // the current _ssvOverride. Runs while the state is still AdLoading, so a
    // throw propagates to the base engine, which fails the load closed.
    while (_reapplyPending) {
      _reapplyPending = false;
      final ssv = _ssvOverride;
      final handle = currentHandle;
      if (ssv == null || handle == null) return;
      await attachSsv(handle, ssv);
    }
  }
}
