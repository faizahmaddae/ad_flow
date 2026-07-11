import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ad_flow_config.dart';
import '../core/ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../core/ad_load_state.dart';
import '../policy/ad_gate.dart';
import '../policy/retry_policy.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';

/// Loads one native ad slot (template or platform-factory rendering).
///
/// Same load discipline as the banner controller — gate-checked loads,
/// retry with backoff, cooldown, auto re-arm — but no refresh loop: native
/// ads stay until [reload] or [dispose].
class NativeAdController implements AdController {
  /// Creates a controller for the native slot.
  NativeAdController({
    required AdSdk sdk,
    required AdGate gate,
    required NativeConfig config,
    required String adUnitId,
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid;

  /// The gate/cap slot name for native ads.
  static const slot = 'native';

  final AdSdk _sdk;
  final AdGate _gate;
  final NativeConfig _config;
  final String _adUnitId;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  NativeHandle? _handle;
  StreamSubscription<AdPaidEvent>? _paidSub;
  Timer? _timer;
  int _attempts = 0;
  bool _disposed = false;

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// The loaded native ad, ready for `buildWidget()`. Null unless [state]
  /// is [AdLoaded].
  NativeHandle? get handle => _handle;

  /// Height to reserve before the ad loads: the template minimums
  /// (small ≈ 90, medium ≈ 320), or 100 for factory rendering.
  double get reservedHeight => switch (_config.templateKind) {
    NativeTemplateKind.small => 90,
    NativeTemplateKind.medium => 320,
    null => 100,
  };

  @override
  Future<void> load() async {
    if (_disposed) return;
    if (_state.value is AdLoading || _state.value is AdLoaded) return;
    // Set Loading synchronously, before any await, so a concurrent load()
    // call sees it immediately and bails instead of racing to a second
    // in-flight SDK load (each would overwrite _handle, leaking the
    // loser's ad).
    _state.value = const AdLoading();

    final allowed = await _gate.canLoad(slot);
    if (_disposed) return;
    if (!allowed) {
      _state.value = const AdIdle();
      _scheduleGateRecheck();
      return;
    }

    try {
      final handle = await _sdk.loadNative(
        NativeLoadSpec(
          adUnitId: _adUnitId,
          templateKind: _config.templateKind,
          factoryId: _config.factoryId,
          factoryExtras: _config.factoryExtras,
        ),
      );
      if (_disposed) {
        unawaited(handle.dispose());
        return;
      }
      _handle = handle;
      _paidSub = handle.paidEvents.listen(_onPaid ?? (_) {});
      _attempts = 0;
      _state.value = const AdLoaded();
    } on AdFlowError catch (e) {
      if (_disposed) return;
      _state.value = AdFailed(e);
      _scheduleRetry();
    }
  }

  /// Disposes the current ad and loads a fresh one (native ads never
  /// refresh on their own).
  ///
  /// A no-op while a load is already in flight: resetting to [AdIdle]
  /// here would defeat [load]'s own synchronous re-entry guard (ADR-024)
  /// and let two concurrent SDK loads race, each overwriting [_handle]
  /// with no dispose for the loser (review finding #4). Let the in-flight
  /// load finish naturally instead.
  Future<void> reload() async {
    if (_disposed) return;
    if (_state.value is AdLoading) return;
    _timer?.cancel();
    _dropHandle();
    _state.value = const AdIdle();
    await load();
  }

  void _scheduleRetry() {
    _attempts++;
    _timer?.cancel();
    if (_retry.shouldRetry(_attempts)) {
      _timer = Timer(_retry.nextDelay(_attempts), () {
        // Only act while still failed — a direct load() call (e.g. a UI
        // retry action) may have already recovered to AdLoaded by the
        // time this fires. Stomping that back to AdIdle would leak the
        // current handle and force an unrelated second load (review
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
  /// one load attempt happened to land while the gate was shut stays idle
  /// forever with nothing left to prompt a reload.
  void _scheduleGateRecheck() {
    _timer?.cancel();
    _timer = Timer(_retry.cooldown, () {
      if (_disposed) return;
      unawaited(load());
    });
  }

  void _dropHandle() {
    unawaited(_paidSub?.cancel());
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
    _dropHandle();
    _state.dispose();
  }
}
