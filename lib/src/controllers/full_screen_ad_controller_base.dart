import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ad_flow_config.dart';
import '../core/ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../core/ad_load_state.dart';
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
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
  }) : _sdk = sdk,
       _gate = gate,
       _caps = caps,
       _coordinator = coordinator,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid;

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
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  FullScreenAdHandle? _handle;
  StreamSubscription<FullScreenAdEvent>? _contentSub;
  StreamSubscription<AdPaidEvent>? _paidSub;
  Timer? _timer;
  int _attempts = 0;
  bool _enteredCoordinator = false;
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
  @protected
  void discardCurrentAd() {
    if (_disposed) return;
    _dropHandle();
    _state.value = const AdIdle();
    unawaited(load());
  }

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// Whether a loaded ad is warm and ready to show.
  bool get isReady => _state.value is AdLoaded && _handle != null;

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

    final allowed = await _gate.canLoad(slot);
    if (_disposed) return;
    if (!allowed) {
      _state.value = const AdIdle();
      _scheduleGateRecheck();
      return;
    }

    try {
      final handle = await loadHandle();
      if (_disposed) {
        unawaited(handle.dispose());
        return;
      }
      _handle = handle;
      _contentSub = handle.contentEvents.listen(_onContentEvent);
      _paidSub = handle.paidEvents.listen(_onPaid ?? (_) {});
      _attempts = 0;
      _state.value = const AdLoaded();
      onLoaded();
    } on AdFlowError catch (e) {
      if (_disposed) return;
      _state.value = AdFailed(e);
      _scheduleRetry();
    }
  }

  @override
  Future<bool> show({OnUserEarnedReward? onReward}) async {
    if (_disposed) return false;
    if (_state.value is AdShowing) return false; // never double-show
    final handle = _handle;
    if (handle == null || _state.value is! AdLoaded) {
      unawaited(load()); // warm one up for the next natural break
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
    if (!_coordinator.tryEnter()) return false;
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

    if (!await _gate.canLoad(slot)) return rejectAndRollBack();
    if (_disposed) return false; // dispose() already rolled everything back
    if (!await _caps.canShow(slot)) return rejectAndRollBack();
    if (_disposed) return false;
    if (!canShowExtra()) return rejectAndRollBack();

    OnUserEarnedReward? onRewardOnce;
    if (onReward != null) {
      // A reward is granted at most once per ad, even if the SDK misfires.
      var granted = false;
      onRewardOnce = (reward) {
        if (granted) return;
        granted = true;
        onReward(reward);
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
        _state.value = AdFailed(
          AdFlowError(AdFlowErrorKind.showFailed, '$e'),
        );
        unawaited(load());
      }
      return false;
    }
    onShown();
    return true;
  }

  void _onContentEvent(FullScreenAdEvent event) {
    if (_disposed) return;
    switch (event) {
      case AdShowedEvent():
        // Coordinator entry already happened synchronously in show(); this
        // only records the confirmed impression.
        unawaited(_caps.recordImpression(slot));
      case AdDismissedEvent():
        // Single-use spent: dispose and immediately preload the next
        // (invariant 7, ADR-011).
        _exitCoordinator();
        _dropHandle();
        _state.value = const AdIdle();
        unawaited(load());
      case AdFailedToShowEvent(:final error):
        _exitCoordinator();
        _dropHandle();
        _state.value = AdFailed(error);
        unawaited(load()); // AdFailed passes the load guard → AdLoading
      case AdImpressionEvent() || AdClickedEvent():
        break;
    }
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

  /// Re-checks the gate after a cooldown when a load was blocked (consent
  /// closed / ads disabled) rather than failed — otherwise a slot whose
  /// one preload attempt happened to land while the gate was shut stays
  /// idle forever with nothing left to prompt a retry.
  void _scheduleGateRecheck() {
    _timer?.cancel();
    _timer = Timer(_retry.cooldown, () {
      if (_disposed) return;
      unawaited(load());
    });
  }

  void _dropHandle() {
    unawaited(_contentSub?.cancel());
    unawaited(_paidSub?.cancel());
    _contentSub = null;
    _paidSub = null;
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(handle.dispose());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _exitCoordinator();
    _dropHandle();
    _state.dispose();
  }
}
