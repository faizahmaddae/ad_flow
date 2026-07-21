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
import '../policy/full_screen_ad_coordinator.dart';
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
  ///
  /// [coordinator] — when given, a click/open on this native ad is reported to
  /// it, so the app-open manager does not stack an app-open ad on the foreground
  /// event that follows (ADR-042). `AdFlow.native()` passes it for you.
  NativeAdController({
    required AdSdk sdk,
    required AdGate gate,
    required NativeConfig config,
    required String adUnitId,
    FullScreenAdCoordinator? coordinator,
    RetryPolicy? retry,
    void Function(AdPaidEvent event)? onPaid,
    void Function(String slotName, AdBlockReason reason)? onBlocked,
    void Function()? onDisposed,
    DateTime Function()? now,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _coordinator = coordinator,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid,
       _onBlocked = onBlocked,
       _onDisposed = onDisposed,
       _now = now ?? DateTime.now;

  /// The gate/cap slot name for native ads.
  static const slotName = 'native';

  final AdSdk _sdk;
  final AdGate _gate;
  final NativeConfig _config;
  final String _adUnitId;
  final FullScreenAdCoordinator? _coordinator;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;
  final void Function(String slotName, AdBlockReason reason)? _onBlocked;
  final DateTime Function() _now;
  DateTime? _loadedAt;

  /// Notified exactly once, when [dispose] runs — lets the minting `AdFlow`
  /// drop this controller from its recheck registry (2026-07 audit).
  final void Function()? _onDisposed;

  AdBlockReason? _lastBlockReason;

  /// Why this slot last refused to load, or null if nothing is blocking it
  /// (ADR-045). A gate-blocked load reports [AdIdle], which is also what "not
  /// requested yet" looks like — this is what tells them apart.
  AdBlockReason? get lastBlockReason => _lastBlockReason;

  void _noteBlocked(AdBlockReason reason) {
    _lastBlockReason = reason;
    final onBlocked = _onBlocked;
    if (onBlocked != null) {
      guardedCallback(
        () => onBlocked(slotName, reason),
        debugName: 'onAdBlocked',
      );
    }
  }

  /// Forwards a paid event to the app with its slot tag, isolated (an
  /// analytics-hook bug must never surface as an unhandled stream error).
  void _dispatchPaid(AdPaidEvent event) {
    final onPaid = _onPaid;
    if (onPaid == null) return;
    guardedCallback(
      () => onPaid(event.taggedWithSlot(slotName)),
      debugName: 'onPaidEvent',
    );
  }

  final ValueNotifier<AdLoadState> _state = ValueNotifier(const AdIdle());
  NativeHandle? _handle;
  StreamSubscription<AdPaidEvent>? _paidSub;
  StreamSubscription<ViewAdEvent>? _eventSub;
  Timer? _timer;
  int _attempts = 0;
  int _gateAttempts = 0;

  /// The consent generation the mounted ad was REQUESTED under. When
  /// [AdGate.consentGeneration] advances past it, the ad carries a stale
  /// consent/forwarding state and `recheckGate` drops-and-reloads it — the
  /// already-loaded counterpart of the mid-load check in [load]. Internal.
  int _loadedGeneration = 0;
  bool _disposed = false;

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// The loaded native ad, ready for `buildWidget()`. Null unless [state]
  /// is [AdLoaded].
  NativeHandle? get handle => _handle;

  /// Which network filled the current ad (mediation observability), or null
  /// when nothing is loaded / the SDK reported nothing.
  AdResponseSummary? get response => _handle?.response;

  /// Height to reserve before the ad loads: the template minimums
  /// (small ≈ 90, medium ≈ 320), or 100 for factory rendering.
  double get reservedHeight => switch (_config.templateKind) {
    NativeTemplateKind.small => 90,
    NativeTemplateKind.medium => 320,
    null => 100,
  };

  /// Whether the loaded native ad has outlived [NativeConfig.maxAdAge].
  ///
  /// Google documents native ads as expiring after ~1 hour: a stale ad may
  /// stop earning or violate policy if left rendering. The expiry timer drops
  /// and reloads a stale ad proactively; this getter is the belt-and-suspenders
  /// check (timers do not fire while the app is suspended).
  bool get isExpired {
    final loadedAt = _loadedAt;
    final maxAdAge = _config.maxAdAge;
    if (loadedAt == null || maxAdAge == null) return false;
    return _now().difference(loadedAt) >= maxAdAge;
  }

  /// Arms the expiry replacement for the ad just loaded, reusing the shared
  /// single-slot [_timer]: while `AdLoaded` no retry or gate-recheck timer is
  /// pending, and every transition out of `AdLoaded` (reload, recheckGate drop,
  /// dispose) cancels it. Best-effort — [reload] on a resume covers a timer
  /// that could not fire while suspended.
  void _scheduleExpiry() {
    final maxAdAge = _config.maxAdAge;
    if (maxAdAge == null) return;
    _timer?.cancel();
    _timer = Timer(maxAdAge, () {
      if (_disposed || _state.value is! AdLoaded || !isExpired) return;
      _noteBlocked(AdBlockReason.expired);
      unawaited(reload());
    });
  }

  @override
  Future<void> load() async {
    if (_disposed) return;
    if (_state.value is AdLoading || _state.value is AdLoaded) return;
    // Set Loading synchronously, before any await, so a concurrent load()
    // call sees it immediately and bails instead of racing to a second
    // in-flight SDK load (each would overwrite _handle, leaking the
    // loser's ad).
    _state.value = const AdLoading();

    // ONE try around the whole async body, gate await included — any escape
    // path that is not a state write + timer arm leaves the slot pinned at
    // AdLoading forever (4.0 audit; the gate await used to sit outside).
    try {
      final blocked = await _gate.loadBlockReason(slotName);
      if (_disposed) return;
      if (blocked != null) {
        _noteBlocked(blocked);
        // A refused load is a STATE (3.0) — see AdBlocked.
        _state.value = AdBlocked(blocked);
        _scheduleGateRecheck();
        return;
      }

      final requestGeneration = _gate.consentGeneration;
      // Watchdog: a load callback that never arrives (the plugin has no
      // timeout of its own) fails this attempt instead of pinning the slot at
      // AdLoading; a late handle is disposed, never installed (I-C).
      final handle = await watchAdLoad(
        pending: _sdk.loadNative(
          NativeLoadSpec(
            adUnitId: _adUnitId,
            templateKind: _config.templateKind,
            factoryId: _config.factoryId,
            factoryExtras: _config.factoryExtras,
            request: _config.request,
          ),
        ),
        timeout: _retry.loadTimeout,
        disposeLate: (late) => late.dispose(),
        slot: slotName,
      );
      if (_disposed) {
        safeUnawaited(handle.dispose(), debugName: 'handle');
        return;
      }
      if (_gate.consentGeneration != requestGeneration) {
        // Consent mutated while this native ad was in flight — it carries the
        // OLD consent/forwarding. Drop it unshown and reload through the
        // re-forwarded gate (release gate #2).
        safeUnawaited(handle.dispose(), debugName: 'handle');
        _state.value = const AdIdle();
        unawaited(load());
        return;
      }
      if (!_gate.isEnabled) {
        // disableAds() / graph-dispose landed WHILE this native ad was in
        // flight: the gate passed at request time, but ads are no longer
        // enabled. recheckGate cannot drop an AdLoading controller (no handle
        // yet), so drop the freshly-loaded handle HERE — synchronously, in the
        // same turn as the AdLoaded write below — before it is ever published
        // or installed (5.1.2). enableAds() re-warms via the gate recheck. A
        // pure bool read: no transient internalError can wrongly drop good
        // inventory (consent-staleness is the generation check above).
        safeUnawaited(handle.dispose(), debugName: 'handle');
        _noteBlocked(AdBlockReason.adsDisabled);
        _state.value = const AdBlocked(AdBlockReason.adsDisabled);
        _scheduleGateRecheck();
        return;
      }
      _handle = handle;
      _paidSub = handle.paidEvents.listen(_dispatchPaid);
      _eventSub = handle.events.listen(_onViewEvent);
      _attempts = 0;
      _gateAttempts = 0;
      _lastBlockReason = null;
      _loadedGeneration = requestGeneration;
      _loadedAt = _now();
      _state.value = const AdLoaded();
      _scheduleExpiry();
    } catch (e) {
      // See BannerAdController.load: catch everything, not just AdFlowError —
      // a raw platform exception must degrade to AdFailed + retry, never pin
      // the slot at AdLoading forever.
      if (_disposed) return;
      _state.value = AdFailed(asAdFlowError(e, AdFlowErrorKind.loadFailed));
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

  @override
  Future<void> recheckGate() async {
    if (_disposed) return;
    final state = _state.value;
    if (state is AdLoaded) {
      // A mounted ad requested under a now-stale consent generation renders and
      // measures under the OLD consent/forwarding — drop it and reload through
      // the fresh gate before checking mere permission (release gate #2). The
      // already-loaded counterpart of the mid-load check in load(). reload()
      // no-ops while a load is already in flight.
      if (_loadedGeneration != _gate.consentGeneration) {
        await reload();
        return;
      }
      final blocked = await _gate.loadBlockReason(slotName);
      if (_disposed || blocked == null) return;
      // Indeterminate is not "revoked": a transient collaborator hiccup must
      // never destroy the live mounted ad (4.0 audit).
      if (blocked == AdBlockReason.internalError) return;
      if (_state.value is! AdLoaded) return; // changed while awaiting
      // No longer permitted (Remove-Ads, consent withdrawn, graph disposed):
      // native ads have no refresh loop at all, so nothing else would ever
      // drop a mounted ad (2026-07 audit).
      _timer?.cancel();
      _dropHandle();
      _noteBlocked(blocked);
      _state.value = AdBlocked(blocked);
      _scheduleGateRecheck();
    } else if (state is AdIdle || state is AdFailed || state is AdBlocked) {
      if (state is AdFailed) _state.value = const AdIdle();
      await load();
    }
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

  /// Re-checks the gate after a backoff when a load was blocked (consent not
  /// settled / ads disabled) rather than failed — otherwise a slot whose one
  /// load attempt happened to land while the gate was shut stays idle forever
  /// with nothing left to prompt a reload.
  ///
  /// [RetryPolicy.gateRecheckDelay], not the 5-minute failure cooldown — see
  /// `BannerAdController._scheduleGateRecheck`.
  void _scheduleGateRecheck() {
    _gateAttempts++;
    _timer?.cancel();
    _timer = Timer(_retry.gateRecheckDelay(_gateAttempts), () {
      if (_disposed) return;
      unawaited(load());
    });
  }

  /// A click on this native ad backgrounds the app; tell the coordinator so the
  /// foreground event that follows is treated as a return FROM AN AD, not a
  /// fresh warm start (ADR-042).
  void _onViewEvent(ViewAdEvent event) {
    if (_disposed) return;
    switch (event) {
      case ViewAdEvent.opened || ViewAdEvent.clicked:
        _coordinator?.noteViewAdOpened();
      case ViewAdEvent.closed:
        // See BannerAdController._onViewEvent: starts the latch's grace
        // window so an in-app overlay click cannot strand it.
        _coordinator?.noteViewAdClosed();
      case ViewAdEvent.impression:
        break;
    }
  }

  void _dropHandle() {
    safeUnawaited(_paidSub?.cancel(), debugName: 'subscription');
    safeUnawaited(_eventSub?.cancel(), debugName: 'subscription');
    _paidSub = null;
    _eventSub = null;
    final handle = _handle;
    _handle = null;
    if (handle != null) safeUnawaited(handle.dispose(), debugName: 'handle');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDisposed?.call();
    _timer?.cancel();
    _timer = null;
    _dropHandle();
    _state.dispose();
  }
}
