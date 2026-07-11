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

/// Loads and refreshes one banner slot.
///
/// - Every load is gate-checked (invariant 1).
/// - Failures retry with [RetryPolicy] backoff; after the attempt budget a
///   cooldown timer auto re-arms the load (v1 never re-armed banners).
/// - While loaded, the ad refreshes every [BannerConfig.minRefresh]
///   (clamped to ≥ 30s per AdMob guidance).
class BannerAdController implements AdController {
  /// Creates a controller for the banner slot.
  ///
  /// [adUnitId] is the already-resolved unit ID for the current platform
  /// (test-mode substitution happens in `AdFlowConfig`). [onPaid] receives
  /// impression-level revenue events.
  BannerAdController({
    required AdSdk sdk,
    required AdGate gate,
    required BannerConfig config,
    required String adUnitId,
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid;

  /// The gate/cap slot name for banners.
  static const slot = 'banner';

  /// Refresh intervals below this are clamped (AdMob guidance is ≥ 60s;
  /// 30s is the hard floor).
  static const minRefreshFloor = Duration(seconds: 30);

  final AdSdk _sdk;
  final AdGate _gate;
  final BannerConfig _config;
  final String _adUnitId;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  BannerHandle? _handle;
  StreamSubscription<AdPaidEvent>? _paidSub;
  Timer? _timer;
  int _attempts = 0;
  int? _width;
  bool _disposed = false;

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// The loaded banner, ready for `buildWidget()`. Null unless [state] is
  /// [AdLoaded].
  BannerHandle? get handle => _handle;

  /// Height to reserve before the ad loads, avoiding layout shift:
  /// exact for fixed sizes, a 50px estimate for adaptive banners.
  double get reservedHeight => switch (_config.kind) {
    BannerKind.fixed => switch (_config.fixedSize) {
      FixedBannerSize.banner => 50,
      FixedBannerSize.largeBanner => 100,
      FixedBannerSize.mediumRectangle => 250,
      FixedBannerSize.fullBanner => 60,
      FixedBannerSize.leaderboard => 90,
    },
    BannerKind.anchoredAdaptive || BannerKind.inlineAdaptive => 50,
  };

  /// Loads the banner. [width] (logical px) is required the first time for
  /// adaptive kinds — `AdFlowBanner` passes its layout width; later calls
  /// (refresh, re-arm) reuse the last width.
  @override
  Future<void> load({int? width}) async {
    if (_disposed) return;
    if (width != null) _width = width;
    if (_state.value is AdLoading || _state.value is AdLoaded) return;
    // Set Loading synchronously, before any await, so a concurrent load()
    // call sees it immediately and bails instead of racing to a second
    // in-flight SDK load (each would overwrite _handle, leaking the
    // loser's banner).
    _state.value = const AdLoading();

    final allowed = await _gate.canLoad(slot);
    if (_disposed) return;
    if (!allowed) {
      _state.value = const AdIdle();
      _scheduleGateRecheck();
      return;
    }

    final BannerSizeSpec size;
    switch (_config.kind) {
      case BannerKind.anchoredAdaptive || BannerKind.inlineAdaptive
          when _width == null:
        _state.value = const AdFailed(
          AdFlowError(
            AdFlowErrorKind.invalidConfig,
            'Adaptive banners need a width: call load(width: ...) or host '
            'the controller in an AdFlowBanner.',
          ),
        );
        return;
      case BannerKind.anchoredAdaptive:
        size = AnchoredAdaptiveSizeSpec(width: _width!);
      case BannerKind.inlineAdaptive:
        size = InlineAdaptiveSizeSpec(
          width: _width!,
          maxHeight: _config.maxInlineHeight,
        );
      case BannerKind.fixed:
        size = FixedSizeSpec(_config.fixedSize);
    }

    try {
      final handle = await _sdk.loadBanner(
        BannerLoadSpec(
          adUnitId: _adUnitId,
          size: size,
          collapsible: _config.collapsible,
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
      _scheduleRefresh();
    } on AdFlowError catch (e) {
      if (_disposed) return;
      _state.value = AdFailed(e);
      _scheduleRetry();
    }
  }

  void _scheduleRefresh() {
    final interval = _config.minRefresh < minRefreshFloor
        ? minRefreshFloor
        : _config.minRefresh;
    _timer?.cancel();
    _timer = Timer(interval, () {
      if (_disposed || _state.value is! AdLoaded) return;
      _dropHandle();
      _state.value = const AdIdle();
      unawaited(load());
    });
  }

  void _scheduleRetry() {
    _attempts++;
    _timer?.cancel();
    if (_retry.shouldRetry(_attempts)) {
      _timer = Timer(_retry.nextDelay(_attempts), () {
        // Only act while still failed — a direct load() call may have
        // already recovered to AdLoaded by the time this fires. Stomping
        // that back to AdIdle would leak the current handle and force an
        // unrelated second load (review finding #3).
        if (_disposed || _state.value is! AdFailed) return;
        _state.value = const AdIdle();
        unawaited(load());
      });
    } else {
      // Budget exhausted: cool down, then auto re-arm from scratch.
      _timer = Timer(_retry.cooldown, () {
        if (_disposed || _state.value is! AdFailed) return;
        _attempts = 0;
        _state.value = const AdIdle();
        unawaited(load());
      });
    }
  }

  /// Re-checks the gate after a cooldown when a load was blocked (consent
  /// closed / ads disabled) rather than failed — otherwise a banner whose
  /// refresh or initial load happened to land while the gate was shut
  /// stays blank forever with nothing left to prompt a reload.
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
