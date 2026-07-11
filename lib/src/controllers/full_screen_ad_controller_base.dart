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
    if (!await _gate.canLoad(slot)) return;
    if (_disposed) return;

    _state.value = const AdLoading();
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
    if (!await _gate.canShow(slot)) return false;
    if (_disposed) return false;
    if (!canShowExtra()) return false;

    _state.value = const AdShowing(); // re-entry guard before any await
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
    await handle.show(onUserEarnedReward: onRewardOnce);
    onShown();
    return true;
  }

  void _onContentEvent(FullScreenAdEvent event) {
    if (_disposed) return;
    switch (event) {
      case AdShowedEvent():
        _coordinator.enter();
        _enteredCoordinator = true;
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
        if (_disposed) return;
        _state.value = const AdIdle();
        unawaited(load());
      });
    } else {
      _timer = Timer(_retry.cooldown, () {
        if (_disposed) return;
        _attempts = 0;
        _state.value = const AdIdle();
        unawaited(load());
      });
    }
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
