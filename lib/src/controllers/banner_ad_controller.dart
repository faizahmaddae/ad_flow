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
    void Function(String slotName, AdBlockReason reason)? onBlocked,
    void Function()? onDisposed,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _coordinator = coordinator,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid,
       _onBlocked = onBlocked,
       _onDisposed = onDisposed;

  /// The gate/cap slot name for banners.
  static const slotName = 'banner';

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
  final void Function(String slotName, AdBlockReason reason)? _onBlocked;

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
  final ValueNotifier<int> _revision = ValueNotifier(0);
  BannerHandle? _handle;
  StreamSubscription<AdPaidEvent>? _paidSub;
  StreamSubscription<ViewAdEvent>? _eventSub;
  Timer? _timer;
  int _attempts = 0;
  int _gateAttempts = 0;
  int? _width;
  int? _loadedWidth;

  /// The consent generation the mounted banner was REQUESTED under. When
  /// [AdGate.consentGeneration] advances past it, the ad renders/measures under
  /// stale consent/forwarding and `recheckGate` drops-and-reloads it — the
  /// already-loaded counterpart of the mid-load check in [load] / [_refresh].
  /// Internal.
  int _loadedGeneration = 0;
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

  /// Which network filled the current ad (mediation observability), or null
  /// when nothing is loaded / the SDK reported nothing.
  AdResponseSummary? get response => _handle?.response;

  /// This slot's sizing strategy — lets [AdFlowBanner] pick the right pre-load
  /// placeholder per kind (exact for fixed, the 50dp floor for anchored
  /// adaptive, zero for inline adaptive).
  BannerKind get kind => _config.kind;

  /// Height to reserve before the ad loads, avoiding layout shift: exact for
  /// fixed sizes. For **anchored adaptive** this is the documented **50dp
  /// floor** — the documented minimum, and the only figure that is safe to
  /// assume client-side: the height the platform actually renders is resolved
  /// after load and cannot be pre-computed (ADR-073). A loaded ad grows the box
  /// to its exact `handle.dimensions`. **Inline adaptive** also returns 50 here, but
  /// [AdFlowBanner] reserves `0` for it (its real height is unknown until the
  /// ad loads) unless an explicit `placeholderHeight` is passed.
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
    // A load OR a background refresh is already in flight for the OLD width:
    // let it finish (resetting to AdIdle here would defeat load()'s
    // synchronous re-entry guard and race two SDK loads — review finding #4;
    // and dropping the handle under an in-flight _refresh() would let its
    // completion swap a stale-width ad over whatever the concurrent load
    // installed, leaking a live BannerAd — 2026-07 audit). Both paths
    // re-check `_width` when they complete and re-request then, so rapid
    // rotation coalesces instead of firing a request per frame.
    if (_state.value is AdLoading || _refreshing) return;
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

      // The width this request is being made AT. _width can change underneath
      // us while the load is in flight (the user rotates), so capture it here
      // and reconcile after the load completes rather than mislabelling the
      // ad.
      final requestWidth = _width;
      // The consent generation this request is dispatched under (release gate
      // #2): a mutation landing while the request is in flight makes the ad
      // stale-consent, so it is dropped-and-reloaded on completion below.
      final requestGeneration = _gate.consentGeneration;

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

      // Watchdog: a load callback that never arrives (the plugin has no
      // timeout of its own) fails this attempt instead of pinning the slot at
      // AdLoading; a late handle is disposed, never installed (I-C).
      final handle = await watchAdLoad(
        pending: _sdk.loadBanner(
          BannerLoadSpec(
            adUnitId: _adUnitId,
            size: size,
            collapsible: _config.collapsible,
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
        // Consent mutated while this banner was in flight — it was requested
        // (and its mediation signal forwarded) under the OLD consent. Drop it
        // unshown and reload through the re-forwarded gate, so it never
        // renders a stale-consent impression (release gate #2).
        safeUnawaited(handle.dispose(), debugName: 'handle');
        await _reloadAtCurrentWidth();
        return;
      }
      if (!_gate.isEnabled) {
        // disableAds() / graph-dispose landed WHILE this banner was in flight:
        // the gate passed at request time, but ads are no longer enabled.
        // recheckGate cannot drop an AdLoading controller (no handle yet), so
        // drop the freshly-loaded handle HERE — synchronously, in the same turn
        // as the AdLoaded write below — before it is ever published or
        // installed (5.1.2 in-flight-load race). enableAds() re-warms via the
        // gate recheck. A pure bool read: no transient internalError can wrongly
        // drop good inventory (the consent-staleness path is the generation
        // check above).
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
      _loadedWidth = requestWidth;
      _loadedGeneration = requestGeneration;
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

  @override
  Future<void> recheckGate() async {
    if (_disposed) return;
    final state = _state.value;
    if (state is AdLoaded) {
      // A mounted banner requested under a now-stale consent generation
      // renders and measures under the OLD consent/forwarding — drop it and
      // re-request at the current width through the fresh gate before checking
      // mere permission (release gate #2). The already-loaded counterpart of
      // the mid-load check in load() / _refresh(). A load OR background refresh
      // in flight is left alone: it stamps its own generation and
      // drops-and-reloads itself on completion, so it never installs a
      // stale-consent ad either.
      if (_loadedGeneration != _gate.consentGeneration) {
        if (_state.value is AdLoading || _refreshing) return;
        await _reloadAtCurrentWidth();
        return;
      }
      final blocked = await _gate.loadBlockReason(slotName);
      if (_disposed || blocked == null) return;
      // Indeterminate is not "revoked": a transient collaborator hiccup must
      // never destroy the live mounted ad (4.0 audit).
      if (blocked == AdBlockReason.internalError) return;
      if (_state.value is! AdLoaded) return; // changed while awaiting
      // The mounted ad is no longer PERMITTED (Remove-Ads bought, consent
      // withdrawn, the owning graph disposed). With minRefresh off by
      // default (ADR-041) nothing else ever re-checks the gate for a live
      // banner — while AdMob's server-side auto-refresh keeps requesting
      // fresh ads for the mounted view. Drop it (2026-07 audit).
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

  /// Arms the opt-in client-side refresh, if one is configured.
  ///
  /// No config, no timer (ADR-041) — AdMob's own server-side auto-refresh is
  /// on by default and already does this job.
  void _scheduleRefresh() {
    final configured = _config.minRefresh;
    if (configured == null) return;
    final interval = configured < minRefreshFloor
        ? minRefreshFloor
        : configured;
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
      final blocked = await _gate.loadBlockReason(slotName);
      if (blocked != null) {
        if (_disposed) return;
        // Indeterminate (a collaborator hiccup) keeps the live ad and skips
        // this refresh cycle — only a DEFINITE "no longer permitted"
        // (Remove-Ads bought, consent withdrawn) may take the ad down. Re-arm
        // the normal refresh timer, or the opt-in refresh loop would die on
        // one hiccup (4.0 audit).
        if (blocked == AdBlockReason.internalError) {
          _scheduleRefresh();
          return;
        }
        // NOT a failure — ads are no longer PERMITTED. Unlike a failed
        // refresh, the current ad may not stay: drop it, report why, then
        // re-check the gate later.
        _dropHandle();
        _noteBlocked(blocked);
        _state.value = AdBlocked(blocked);
        _scheduleGateRecheck();
        return;
      }
      if (_disposed) return;
      final requestWidth = _width;
      final requestGeneration = _gate.consentGeneration;
      final size = _sizeSpec();
      if (size == null) return; // adaptive with no width — cannot refresh
      // Watchdog: a hung replacement load lands in the catch below (keep the
      // live ad, back off); its late handle is disposed, never swapped in.
      final handle = await watchAdLoad(
        pending: _sdk.loadBanner(
          BannerLoadSpec(
            adUnitId: _adUnitId,
            size: size,
            collapsible: _config.collapsible,
            request: _config.request,
          ),
        ),
        timeout: _retry.loadTimeout,
        disposeLate: (late) => late.dispose(),
        slot: slotName,
      );
      if (_disposed || _state.value is! AdLoaded) {
        // The world changed while the replacement was loading: the controller
        // was disposed, or the ad this refresh set out to replace is gone (the
        // gate closed and dropped it, or a resize-driven reload took over).
        // Installing the replacement now would stomp the newer state and leak
        // whatever it overwrote — release it and let the current owner of the
        // slot carry on (2026-07 audit).
        safeUnawaited(handle.dispose(), debugName: 'handle');
        return;
      }
      if (_gate.consentGeneration != requestGeneration) {
        // Consent mutated while this replacement was loading — it carries the
        // OLD consent/forwarding. Don't swap it in; drop the current ad and
        // reload fresh through the re-forwarded gate (release gate #2).
        safeUnawaited(handle.dispose(), debugName: 'handle');
        _refreshing = false;
        await _reloadAtCurrentWidth();
        return;
      }
      // The replacement is here: swap atomically, THEN release the old ad.
      final old = _handle;
      final oldPaidSub = _paidSub;
      final oldEventSub = _eventSub;
      _handle = handle;
      // Isolate the paid-event callback exactly like the initial load path —
      // the refresh swap used a raw `_onPaid?.call(...)`, so a throwing (or
      // async-rejecting) app `onPaidEvent` on a REFRESHED banner escaped as
      // an unhandled zone error while the same hook was contained on the
      // first load (4.1 audit).
      _paidSub = handle.paidEvents.listen(_dispatchPaid);
      _eventSub = handle.events.listen(_onViewEvent);
      _loadedWidth = requestWidth;
      _loadedGeneration = requestGeneration;
      safeUnawaited(oldPaidSub?.cancel(), debugName: 'subscription');
      safeUnawaited(oldEventSub?.cancel(), debugName: 'subscription');
      if (old != null) safeUnawaited(old.dispose(), debugName: 'handle');
      // `AdLoaded == AdLoaded`, so writing the state again would NOT notify —
      // the widget would keep rendering the old, now-disposed handle. Bump the
      // revision instead; AdFlowBanner listens to both.
      _revision.value++;
      _attempts = 0;
      _scheduleRefresh();
      // The layout width changed while this replacement was in flight (a
      // rotation during the refresh — resize() defers to us): the ad just
      // swapped in is already the wrong size, so re-request at the current
      // width, exactly as load() reconciles after a mid-load rotation
      // (2026-07 audit).
      if (_width != requestWidth) unawaited(_reloadAtCurrentWidth());
    } catch (_) {
      // A failed refresh (no-fill, network) must NOT take down the ad that is
      // already on screen — that was the old behaviour's worst property. Keep
      // it, back off, and try again.
      if (_disposed) return;
      // Only back off if there IS still a current ad to keep. If the slot
      // moved on while this refresh was in flight (a gate-closed drop, a
      // resize-driven reload), the shared `_timer` now belongs to THAT path's
      // recovery — cancelling it here and arming a refresh timer (whose
      // callback no-ops outside AdLoaded) would destroy the slot's only
      // re-arm and wedge it blank forever (2026-07 audit).
      if (_state.value is! AdLoaded) return;
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
      BannerKind.anchoredAdaptive when width != null =>
        AnchoredAdaptiveSizeSpec(width: width),
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
      case ViewAdEvent.closed:
        // The user left the ad's overlay/landing page — starts the latch's
        // short grace window so an in-app overlay click (which never
        // produces a foreground event) cannot strand the latch and eat the
        // next genuine warm return (2026-07 audit).
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
    _revision.dispose();
  }
}
