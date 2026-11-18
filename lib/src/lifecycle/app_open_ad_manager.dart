import 'dart:async';

import '../config/ad_flow_config.dart';
import '../controllers/app_open_ad_controller.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_show_result.dart';
import '../core/callback_guard.dart';
import '../policy/full_screen_ad_coordinator.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'launch_latch.dart';

/// The single owner of app-open behaviour (v1 trap: two reactors coordinated
/// through statics fought each other — the facade creates exactly one manager
/// and nothing else reacts to foreground).
///
/// Two legitimate product moments:
///
/// - **Resume** — a genuine background→foreground return, driven by the seam's
///   foreground events (backed by `AppStateEventNotifier`, the only correct
///   signal; iOS `inactive` is NOT backgrounding). On by default
///   ([AppOpenConfig.showOnResume]); all policy is delegated to the controller
///   and gate: consent, enabled, frequency caps, coordinator suppression,
///   expiry.
/// - **Launch** — a real cold process launch, taken explicitly with
///   [showAtLaunch] from the app's loading screen. NOT faked from a lifecycle
///   event (`AppStateEventNotifier` never replays the cold-launch foreground),
///   and one-shot per process.
///
/// Invariant 3 ("never show on a cold launch by surprise") holds structurally
/// on the resume path: at a real cold launch nothing is loaded yet, so
/// `show()` finds no warm ad. The launch path is opt-in.
class AppOpenAdManager {
  /// Creates the manager. Call [start] to begin reacting to foreground
  /// returns.
  ///
  /// [coordinator] — when provided, the SAME [FullScreenAdCoordinator]
  /// instance shared with every other controller — lets the manager avoid
  /// showing an app-open ad immediately behind another format's dismiss
  /// (review finding #7). [postDismissSuppression] is the minimum gap enforced;
  /// [now] is an injectable clock for tests.
  AppOpenAdManager({
    required AppOpenAdController controller,
    required AdSdk sdk,
    required AppOpenConfig config,
    FullScreenAdCoordinator? coordinator,
    Duration postDismissSuppression = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _controller = controller,
       _sdk = sdk,
       _config = config,
       _coordinator = coordinator,
       _postDismissSuppression = postDismissSuppression,
       _now = now ?? DateTime.now;

  final AppOpenAdController _controller;
  final AdSdk _sdk;
  final AppOpenConfig _config;
  final FullScreenAdCoordinator? _coordinator;
  final Duration _postDismissSuppression;
  final DateTime Function() _now;

  StreamSubscription<AppForegroundEvent>? _sub;
  bool _disposed = false;

  /// The app-open slot's controller (state, readiness, block reasons).
  AppOpenAdController get controller => _controller;

  /// Whether the manager is currently reacting to foreground events.
  bool get isStarted => _sub != null;

  /// Starts listening and warms the first preload. Idempotent.
  void start() {
    if (_disposed || _sub != null) return;
    _sub = _sdk.appForegroundEvents.listen(_onForeground);
    unawaited(_controller.load());
  }

  /// Takes the one-shot cold-launch opportunity: shows an app-open ad while
  /// the app's loading screen is up, and completes when the ad has CLOSED —
  /// keep the loading screen until then, then enter the app (6.0).
  ///
  /// ```dart
  /// await ads.appOpen?.showAtLaunch();
  /// navigator.pushReplacement(home);
  /// ```
  ///
  /// - Waits up to [maxWait] (3 s by default) for the ad to finish loading —
  ///   at a real cold launch the first load is usually still in flight, which
  ///   is why a launch ad that is only shown when "already ready" almost never
  ///   shows. `Duration.zero` shows only an ad that is already warm.
  /// - Never for a first-time user: when no consent from an earlier launch is
  ///   on the device it returns at once (`blocked(consentNotGranted)`), so a
  ///   launch ad never follows the consent form.
  /// - One-shot per process launch, surviving `AdFlow` reinitialization: a
  ///   later call returns `blocked(notReady)` at once, so it can never turn
  ///   into a surprise ad in the middle of the session.
  /// - The controller still enforces consent, caps, other full-screen ads,
  ///   expiry and Remove-Ads.
  ///
  /// With [AppOpenConfig.showOnResume] off, the slot stops loading after this
  /// call: a launch-only ad is never shown again in this process.
  Future<AdShowResult> showAtLaunch({
    Duration maxWait = const Duration(seconds: 3),
  }) async {
    if (_disposed) return const AdShowResult.blocked(AdBlockReason.notReady);
    // Consume the one-shot up front: even a launch with no ad spends the
    // launch moment, so no "launch" ad can appear seconds into the session.
    if (!LaunchLatch.consume()) {
      return const AdShowResult.blocked(AdBlockReason.notReady);
    }
    try {
      if (!await _hasEarlierConsent()) {
        return const AdShowResult.blocked(AdBlockReason.consentNotGranted);
      }
      await _waitUntilReady(maxWait);
      if (_disposed) return const AdShowResult.blocked(AdBlockReason.notReady);
      // show() refuses (and reports) a not-ready ad itself.
      final result = _controller.show();
      // Launch-only: the launch is done — stop maintaining inventory. An ad
      // now on screen finishes normally; its dismiss does not reload.
      if (!_config.showOnResume) _controller.retire();
      return await result;
    } finally {
      if (!_config.showOnResume) _controller.retire();
    }
  }

  /// Whether consent from an earlier launch is on the device — the SDK's
  /// cached answer, read without waiting for this launch's consent flow.
  Future<bool> _hasEarlierConsent() async {
    try {
      return await _sdk.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  /// Completes when the ad is ready, or after [maxWait], whichever is first.
  Future<void> _waitUntilReady(Duration maxWait) {
    if (_controller.isReady || maxWait <= Duration.zero) {
      return Future<void>.value();
    }
    final ready = Completer<void>();
    void check() {
      if (_controller.isReady && !ready.isCompleted) ready.complete();
    }

    final state = _controller.state;
    state.addListener(check);
    final timer = Timer(maxWait, () {
      if (!ready.isCompleted) ready.complete();
    });
    return ready.future.whenComplete(() {
      timer.cancel();
      try {
        state.removeListener(check);
      } catch (_) {
        // The controller was disposed while waiting.
      }
    });
  }

  Future<void> _onForeground(AppForegroundEvent event) async {
    // Launch-only never shows (or reloads) on a resume.
    if (!_config.showOnResume) return;
    // The user is coming back from a banner/native ad they just clicked: this
    // foreground event is a return FROM AN AD, not a genuine warm return
    // (ADR-042). One-shot — the next return is a normal one.
    if (_coordinator?.consumeViewAdOpened() ?? false) {
      unawaited(_controller.load());
      return;
    }
    if (_withinPostDismissSuppression()) {
      // Another full-screen ad (of any format) just closed — never stack
      // an app-open ad right behind it (review finding #7). Still keep
      // one warm for the next legitimate opportunity.
      unawaited(_controller.load());
      return;
    }
    // There is deliberately no "first event is the cold start" latch here
    // (ADR-043): `AppStateEventNotifier` does not replay the cold-launch
    // foreground, so the first event received is a real background→return.
    // The controller enforces gate, caps, coordinator and the 4h expiry; a
    // refusal also re-warms the next ad.
    await _controller.show();
  }

  bool _withinPostDismissSuppression() {
    if (_postDismissSuppression <= Duration.zero) return false;
    final lastExit = _coordinator?.lastExitAt;
    if (lastExit == null) return false;
    return _now().difference(lastExit) < _postDismissSuppression;
  }

  /// Stops reacting to foreground events (the controller keeps its ad).
  void stop() {
    safeUnawaited(_sub?.cancel(), debugName: 'subscription');
    _sub = null;
  }

  /// Stops the manager. Does NOT dispose the controller (the facade owns
  /// controller lifecycles).
  void dispose() {
    _disposed = true;
    stop();
  }
}
