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

/// Remembers how tall anchored adaptive banners actually rendered, per
/// requested width.
///
/// An anchored adaptive banner's height is only known once the platform has
/// built it (ADR-073), so a banner that has never loaded reserves the 50dp
/// floor and then grows into its real size — about 100–150dp for Google's
/// large anchored format (ADR-078). Without a memory that jump repeats on
/// every screen that mounts a new banner. With one, the first banner to load
/// at a width records its height, and every later banner at that width
/// reserves it before its own ad arrives: no layout shift, which is also what
/// AdMob's accidental-click guidance asks for (ADR-079).
///
/// `AdFlow.banner()` shares one per `AdFlow`; a [BannerAdController] built
/// without one remembers only its own loads. In memory only (a new process
/// starts empty) and keyed by width alone: the height also depends on the
/// screen height, so a slot resized vertically at the same width can be a few
/// dp off until its own ad loads and the box takes the exact size.
final class BannerHeightMemory {
  final _heights = <(int, AnchoredBannerSize), double>{};

  /// The height an anchored adaptive banner of [size] last rendered at when
  /// requested at [width], or null if none has loaded at that width yet. The
  /// large and classic sizes are remembered apart.
  double? heightFor(
    int width, {
    AnchoredBannerSize size = AnchoredBannerSize.large,
  }) => _heights[(width, size)];

  /// Records that a banner of [size] requested at [width] rendered [height]
  /// tall. A non-positive [height] is ignored.
  void remember(
    int width,
    double height, {
    AnchoredBannerSize size = AnchoredBannerSize.large,
  }) {
    if (height > 0) _heights[(width, size)] = height;
  }
}

/// Loads and refreshes one banner slot.
///
/// - Every load is gate-checked (invariant 1).
/// - Failures retry with [RetryPolicy] backoff; after the attempt budget a
///   cooldown timer auto re-arms the load (v1 never re-armed banners).
/// - While loaded, AdMob refreshes the ad server-side (configured per ad unit
///   in the AdMob console); there is no client-side refresh timer (ADR-041).
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
  /// [heightMemory] — shared with other banner controllers so a banner
  /// reserves the height earlier banners of its width rendered at (see
  /// [BannerHeightMemory]); `AdFlow.banner()` passes its own. Without one this
  /// controller remembers only its own loads.
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
    BannerHeightMemory? heightMemory,
  }) : _sdk = sdk,
       _gate = gate,
       _config = config,
       _adUnitId = adUnitId,
       _coordinator = coordinator,
       _retry = retry ?? RetryPolicy(const RetryConfig()),
       _onPaid = onPaid,
       _onBlocked = onBlocked,
       _onDisposed = onDisposed,
       _heightMemory = heightMemory ?? BannerHeightMemory();

  /// The gate/cap slot name for banners.
  static const slotName = 'banner';

  final AdSdk _sdk;
  final AdGate _gate;
  final BannerConfig _config;
  final String _adUnitId;
  final FullScreenAdCoordinator? _coordinator;
  final RetryPolicy _retry;
  final void Function(AdPaidEvent event)? _onPaid;
  final void Function(String slotName, AdBlockReason reason)? _onBlocked;
  final BannerHeightMemory _heightMemory;

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
  /// stale consent and `recheckGate` drops-and-reloads it — the already-loaded
  /// counterpart of the mid-load check in [load]. Internal.
  int _loadedGeneration = 0;
  bool _disposed = false;

  @override
  ValueListenable<AdLoadState> get state => _state;

  /// The loaded banner, ready for `buildWidget()`. Null unless [state] is
  /// [AdLoaded].
  BannerHandle? get handle => _handle;

  /// Which network filled the current ad (mediation observability), or null
  /// when nothing is loaded / the SDK reported nothing.
  AdResponseSummary? get response => _handle?.response;

  /// This slot's sizing strategy — lets [AdFlowBanner] pick the right pre-load
  /// placeholder per kind (exact for fixed, the remembered height or the 50dp
  /// floor for anchored adaptive, zero for inline adaptive).
  BannerKind get kind => _config.kind;

  /// Height to reserve before the ad loads, avoiding layout shift: exact for
  /// fixed sizes. For **anchored adaptive** it is the height a banner at the
  /// current width already rendered at, from the [BannerHeightMemory]
  /// (ADR-079), and otherwise the documented **50dp floor** — the only figure
  /// safe to assume before anything has loaded, because the height the
  /// platform renders is resolved after load (ADR-073). A loaded ad always
  /// sizes the box to its exact `handle.dimensions`. **Inline adaptive** also
  /// returns 50 here, but [AdFlowBanner] reserves `0` for it (its real height
  /// varies per creative) unless an explicit `placeholderHeight` is passed.
  double get reservedHeight => switch (_config.kind) {
    BannerKind.fixed => switch (_config.fixedSize) {
      FixedBannerSize.banner => 50,
      FixedBannerSize.largeBanner => 100,
      FixedBannerSize.mediumRectangle => 250,
      FixedBannerSize.fullBanner => 60,
      FixedBannerSize.leaderboard => 90,
    },
    BannerKind.anchoredAdaptive => _rememberedHeight ?? 50,
    BannerKind.inlineAdaptive => 50,
  };

  /// What [BannerHeightMemory] knows for the current width, if anything.
  double? get _rememberedHeight {
    final width = _width;
    return width == null
        ? null
        : _heightMemory.heightFor(width, size: _config.anchoredSize);
  }

  /// Teaches [BannerHeightMemory] the height [handle] rendered at, requested at
  /// [width]. Anchored adaptive only: a fixed slot's height is already exact,
  /// and an inline adaptive height varies per creative, so remembering it
  /// would be a guess (ADR-070).
  void _rememberHeight(BannerHandle handle, int? width) {
    if (_config.kind != BannerKind.anchoredAdaptive || width == null) return;
    _heightMemory.remember(
      width,
      handle.dimensions.value.height,
      size: _config.anchoredSize,
    );
  }

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
    // two SDK loads — review finding #4). The load re-checks `_width` when it
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
          size = AnchoredAdaptiveSizeSpec(
            width: _width!,
            size: _config.anchoredSize,
          );
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
      _rememberHeight(handle, requestWidth);
      _loadedGeneration = requestGeneration;
      _state.value = const AdLoaded();
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
      // the mid-load check in load().
      if (_loadedGeneration != _gate.consentGeneration) {
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
      // withdrawn, the owning graph disposed). Nothing else ever re-checks the
      // gate for a live banner — while AdMob's server-side auto-refresh keeps
      // requesting fresh ads for the mounted view. Drop it (2026-07 audit).
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
  }
}
