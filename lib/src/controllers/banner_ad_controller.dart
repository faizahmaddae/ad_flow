import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ad_flow_config.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../core/ad_load_state.dart';
import '../policy/ad_gate.dart';
import '../policy/full_screen_ad_coordinator.dart';
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
  /// [coordinator] — when given, the controller reports a click/open on this
  /// banner to it, so the app-open manager knows the foreground event that
  /// follows is a return FROM AN AD and does not stack an app-open ad on it
  /// (ADR-042). `AdFlow.banner()` passes the shared coordinator for you.
  BannerAdController({
    required AdSdk sdk,
    required AdGate gate,
    required BannerConfig config,
    required String adUnitId,
    FullScreenAdCoordinator? coordinator,
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
    void Function(String slot, AdBlockReason reason)? onBlocked,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _coordinator = coordinator,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid,
       _onBlocked = onBlocked;

  /// The gate/cap slot name for banners.
  static const slot = 'banner';

  /// Refresh intervals below this are clamped (AdMob guidance is ≥ 60s;
  /// 30s is the hard floor).
  static const minRefreshFloor = Duration(seconds: 30);

  final AdSdk _sdk;
  final AdGate _gate;
  final BannerConfig _config;
  final String _adUnitId;
  final FullScreenAdCoordinator? _coordinator;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;
  final void Function(String slot, AdBlockReason reason)? _onBlocked;

  AdBlockReason? _lastBlockReason;

  /// Why this slot last refused to load, or null if nothing is blocking it
  /// (ADR-045). A gate-blocked load reports [AdIdle], which is also what "not
  /// requested yet" looks like — this is what tells them apart.
  AdBlockReason? get lastBlockReason => _lastBlockReason;

  void _noteBlocked(AdBlockReason reason) {
    _lastBlockReason = reason;
    _onBlocked?.call(slot, reason);
  }

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  final ValueNotifier<int> _revision = ValueNotifier(0);
  BannerHandle? _handle;
  StreamSubscription<AdPaidEvent>? _paidSub;
  StreamSubscription<ViewAdEvent>? _eventSub;
  Timer? _timer;
  int _attempts = 0;
  int _gateAttempts = 0;
  int? _width;
  int? _loadedWidth;
  bool _refreshing = false;
  bool _disposed = false;

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// Bumped every time [handle] is replaced by a *different* live ad — a
  /// client-side refresh swap (ADR-041).
  ///
  /// [state] cannot carry this: the swap goes `AdLoaded → AdLoaded`, and
  /// `ValueNotifier` skips `notifyListeners()` when the new value equals the
  /// old one, so a widget listening only to [state] would go on rendering the
  /// previous, now-disposed handle. `AdFlowBanner` listens to both.
  ValueListenable<int> get revision => _revision;

  /// The loaded banner, ready for `buildWidget()`. Null unless [state] is
  /// [AdLoaded].
  BannerHandle? get handle => _handle;

  /// This slot's sizing strategy — lets [AdFlowBanner] compute a better,
  /// device-aware placeholder for adaptive kinds than [reservedHeight]'s
  /// width-only floor estimate (review finding #8).
  BannerKind get kind => _config.kind;

  /// Height to reserve before the ad loads, avoiding layout shift: exact
  /// for fixed sizes. For adaptive kinds this is only the documented
  /// *floor* (AdMob's anchored adaptive banners are 50–90dp depending on
  /// device/width — there is no pure-width formula, per Google's own
  /// docs), so real ads on wider layouts commonly land taller than this
  /// — prefer [AdFlowBanner]'s own device-aware estimate, or pass an
  /// explicit `placeholderHeight`, for adaptive placements.
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

  /// The width the currently loaded ad was actually REQUESTED at, or null if
  /// nothing is loaded. [AdFlowBanner] compares this to its layout width to
  /// detect a rotation/fold and drive [resize].
  int? get loadedWidth => _loadedWidth;

  /// Re-requests the banner at a new layout [width] after a rotation, fold or
  /// window resize.
  ///
  /// An anchored/inline adaptive banner is requested FOR a specific width, so
  /// after a rotation an ad sized for the old width sits letterboxed in the
  /// slot — poor viewability, lost revenue — and, because the controller
  /// cached the stale width, EVERY subsequent refresh re-requested that wrong
  /// size too. Google's guidance is to reload an adaptive banner when the
  /// orientation changes.
  ///
  /// A no-op for [BannerKind.fixed] (its size is not width-derived) and when
  /// the width has not actually changed — a plain rebuild must never re-request
  /// an ad (that would be an ad-request storm, i.e. invalid traffic).
  Future<void> resize(int width) async {
    if (_disposed || _config.kind == BannerKind.fixed) return;
    if (_width == width) return;
    _width = width;
    // A load is already in flight for the OLD width: let it finish (resetting
    // to AdIdle here would defeat load()'s synchronous re-entry guard and race
    // two SDK loads — review finding #4). load() re-checks the width when it
    // completes and re-requests then, so rapid rotation coalesces instead of
    // firing a request per frame.
    if (_state.value is AdLoading) return;
    await _reloadAtCurrentWidth();
  }

  /// Drops the current (wrong-width) ad and requests a fresh one at [_width].
  Future<void> _reloadAtCurrentWidth() {
    _timer?.cancel();
    _dropHandle();
    _loadedWidth = null;
    _state.value = const AdIdle();
    return load();
  }

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

    final blocked = await _gate.loadBlockReason(slot);
    if (_disposed) return;
    if (blocked != null) {
      _noteBlocked(blocked);
      _state.value = const AdIdle();
      _scheduleGateRecheck();
      return;
    }

    // The width this request is being made AT. _width can change underneath us
    // while the load is in flight (the user rotates), so capture it here and
    // reconcile after the load completes rather than mislabelling the ad.
    final requestWidth = _width;

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
      _eventSub = handle.events.listen(_onViewEvent);
      _attempts = 0;
      _gateAttempts = 0;
      _lastBlockReason = null;
      _loadedWidth = requestWidth;
      _state.value = const AdLoaded();
      _scheduleRefresh();
      // The layout width changed while this request was in flight (the user
      // rotated mid-load): the ad we just got is already the wrong size, so
      // re-request at the current width.
      if (_width != requestWidth) unawaited(_reloadAtCurrentWidth());
    } catch (e) {
      // Not just AdFlowError: a MissingPluginException/PlatformException from
      // the channel used to escape this catch and pin the banner at AdLoading
      // with no retry armed — a permanently blank banner, on exactly the weak
      // devices/networks this package targets.
      if (_disposed) return;
      _state.value = AdFailed(asAdFlowError(e, AdFlowErrorKind.loadFailed));
      _scheduleRetry();
    }
  }

  /// Arms the opt-in client-side refresh, if one is configured.
  ///
  /// No config, no timer (ADR-041) — AdMob's own server-side auto-refresh is
  /// on by default and already does this job.
  void _scheduleRefresh() {
    final configured = _config.minRefresh;
    if (configured == null) return;
    final interval = configured < minRefreshFloor ? minRefreshFloor : configured;
    _timer?.cancel();
    _timer = Timer(interval, _refresh);
  }

  /// Loads a replacement ad **in the background** and swaps it in only once it
  /// has actually arrived (ADR-041).
  ///
  /// The old code dropped the live handle, went `AdIdle` and started a fresh
  /// load — so the slot went BLANK for the entire duration of that load, on
  /// every single refresh cycle. On a weak network that is a multi-second hole
  /// in the middle of the screen, every minute; and a refresh that failed
  /// (no-fill — routine) left the slot empty until a retry finally succeeded,
  /// having destroyed a perfectly good ad to get there.
  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    if (_state.value is! AdLoaded) return; // nothing on screen to refresh
    _refreshing = true;
    try {
      if (_disposed) return;
      if (!await _gate.canLoad(slot)) {
        // NOT a failure — ads are no longer PERMITTED (Remove-Ads bought,
        // consent withdrawn). Unlike a failed refresh, the current ad may not
        // stay: drop it and go idle, then re-check the gate later.
        if (_disposed) return;
        _dropHandle();
        _state.value = const AdIdle();
        _scheduleGateRecheck();
        return;
      }
      if (_disposed) return;
      final requestWidth = _width;
      final size = _sizeSpec();
      if (size == null) return; // adaptive with no width — cannot refresh
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
      // The replacement is here: swap atomically, THEN release the old ad.
      final old = _handle;
      final oldPaidSub = _paidSub;
      final oldEventSub = _eventSub;
      _handle = handle;
      _paidSub = handle.paidEvents.listen(_onPaid ?? (_) {});
      _eventSub = handle.events.listen(_onViewEvent);
      _loadedWidth = requestWidth;
      unawaited(oldPaidSub?.cancel());
      unawaited(oldEventSub?.cancel());
      if (old != null) unawaited(old.dispose());
      // `AdLoaded == AdLoaded`, so writing the state again would NOT notify —
      // the widget would keep rendering the old, now-disposed handle. Bump the
      // revision instead; AdFlowBanner listens to both.
      _revision.value++;
      _attempts = 0;
      _scheduleRefresh();
    } catch (_) {
      // A failed refresh (no-fill, network) must NOT take down the ad that is
      // already on screen — that was the old behaviour's worst property. Keep
      // it, back off, and try again.
      if (_disposed) return;
      _attempts++;
      _timer?.cancel();
      _timer = Timer(
        _retry.shouldRetry(_attempts)
            ? _retry.nextDelay(_attempts)
            : _retry.cooldown,
        () {
          if (_disposed) return;
          if (!_retry.shouldRetry(_attempts)) _attempts = 0;
          unawaited(_refresh());
        },
      );
    } finally {
      _refreshing = false;
    }
  }

  /// The size spec for the current config/width, or null when an adaptive
  /// banner has no width yet.
  BannerSizeSpec? _sizeSpec() {
    final width = _width;
    return switch (_config.kind) {
      BannerKind.anchoredAdaptive when width != null => AnchoredAdaptiveSizeSpec(
        width: width,
      ),
      BannerKind.inlineAdaptive when width != null => InlineAdaptiveSizeSpec(
        width: width,
        maxHeight: _config.maxInlineHeight,
      ),
      BannerKind.anchoredAdaptive || BannerKind.inlineAdaptive => null,
      BannerKind.fixed => FixedSizeSpec(_config.fixedSize),
    };
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

  /// Re-checks the gate after a backoff when a load was blocked (consent not
  /// settled / ads disabled) rather than failed — otherwise a banner whose
  /// refresh or initial load happened to land while the gate was shut stays
  /// blank forever with nothing left to prompt a reload.
  ///
  /// [RetryPolicy.gateRecheckDelay], not the 5-minute failure cooldown: a
  /// first-frame banner (ADR-032) routinely reaches the gate before consent
  /// has settled, and reusing the cooldown left it blank for the first five
  /// minutes of every new install.
  void _scheduleGateRecheck() {
    _gateAttempts++;
    _timer?.cancel();
    _timer = Timer(_retry.gateRecheckDelay(_gateAttempts), () {
      if (_disposed) return;
      unawaited(load());
    });
  }

  /// A click on this banner opens the landing page and backgrounds the app.
  /// Tell the coordinator, so the app-open manager treats the foreground event
  /// that follows as a return FROM AN AD rather than a fresh warm start —
  /// otherwise the user closes the landing page and is immediately handed an
  /// app-open ad (ADR-042).
  void _onViewEvent(ViewAdEvent event) {
    if (_disposed) return;
    switch (event) {
      case ViewAdEvent.opened || ViewAdEvent.clicked:
        _coordinator?.noteViewAdOpened();
      case ViewAdEvent.closed || ViewAdEvent.impression:
        break;
    }
  }

  void _dropHandle() {
    unawaited(_paidSub?.cancel());
    unawaited(_eventSub?.cancel());
    _paidSub = null;
    _eventSub = null;
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
    _revision.dispose();
  }
}
