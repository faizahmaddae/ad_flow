import 'dart:async';

import '../config/ad_flow_config.dart';
import '../controllers/app_open_ad_controller.dart';
import '../policy/full_screen_ad_coordinator.dart';
import '../core/callback_guard.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';

/// A one-shot, process-scoped latch for the cold-launch app-open opportunity
/// (5.1).
///
/// The cold launch of a process is a single moment; an app may take at most one
/// app-open show for it, via [AppOpenAdManager.showAtLaunchIfReady]. This latch
/// makes that "once per process" hold even across [AdFlow] reinitialization — a
/// second `initialize()` builds a new manager but shares the same process
/// latch, so it cannot mint a second launch show. Injectable so tests get
/// isolation; the manager's default is process-global by design.
class LaunchOpportunity {
  bool _consumed = false;

  /// Whether the one-shot launch opportunity is still available.
  bool get isAvailable => !_consumed;

  /// Consumes the one-shot; returns true iff it was still available.
  bool consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// The single owner of app-open behaviour (v1 trap: two reactors coordinated
/// through statics fought each other — the facade creates exactly one manager
/// and nothing else reacts to foreground).
///
/// Two legitimate product moments, selected by [AppOpenConfig.triggerMode]:
///
/// - **Resume** — a genuine background→foreground return, driven by the seam's
///   foreground events (backed by `AppStateEventNotifier`, the only correct
///   signal; iOS `inactive` is NOT backgrounding). Shown on every return, with
///   all policy delegated to the controller and gate: consent, enabled,
///   frequency caps, coordinator suppression, expiry.
/// - **Launch** — a real cold process launch, taken explicitly via
///   [showAtLaunchIfReady] from the app's loading screen. NOT faked from a
///   lifecycle event (`AppStateEventNotifier` never replays the cold-launch
///   foreground — the seam calls `startListening()` only once the app is
///   already foregrounded), and one-shot per process.
///
/// The default [AppOpenTriggerMode.resumeOnly] preserves the v5 behaviour. In
/// all modes [start] preloads one ad so it can be ready for either moment.
///
/// Invariant 3 ("never show on a cold launch by surprise") holds structurally
/// on the resume path: at a real cold launch nothing is loaded yet, so
/// `show()` finds no warm ad. The launch path is opt-in and only ever shows an
/// already-ready ad.
class AppOpenAdManager {
  /// Creates the manager. Call [start] to begin reacting to foreground
  /// returns.
  ///
  /// [coordinator] — when provided, the SAME [FullScreenAdCoordinator]
  /// instance shared with every other controller — lets the manager avoid
  /// showing an app-open ad immediately behind another format's dismiss
  /// (review finding #7). [postDismissSuppression] is the minimum gap enforced;
  /// [now] is an injectable clock for tests. [launchOpportunity] overrides the
  /// process-global cold-launch latch (tests inject their own for isolation).
  AppOpenAdManager({
    required AppOpenAdController controller,
    required AdSdk sdk,
    required AppOpenConfig config,
    FullScreenAdCoordinator? coordinator,
    Duration postDismissSuppression = const Duration(seconds: 1),
    DateTime Function()? now,
    LaunchOpportunity? launchOpportunity,
  }) : _controller = controller,
       _sdk = sdk,
       _config = config,
       _coordinator = coordinator,
       _postDismissSuppression = postDismissSuppression,
       _now = now ?? DateTime.now,
       _launch = launchOpportunity ?? _processLaunchOpportunity;

  /// The sole process-global cold-launch latch (invariant 9's second
  /// sanctioned exception, like `AdFlow._instance` — see the
  /// no_global_state_test allow-list and ADR-067). Shared across [AdFlow]
  /// reinitialization so a second `initialize()` cannot hand out a second
  /// launch show. Never reset in production; tests inject their own.
  static final LaunchOpportunity _processLaunchOpportunity = LaunchOpportunity();

  final AppOpenAdController _controller;
  final AdSdk _sdk;
  final AppOpenConfig _config;
  final FullScreenAdCoordinator? _coordinator;
  final Duration _postDismissSuppression;
  final DateTime Function() _now;
  final LaunchOpportunity _launch;

  StreamSubscription<AppForegroundEvent>? _sub;
  bool _disposed = false;

  /// Whether the manager is currently reacting to foreground events.
  bool get isStarted => _sub != null;

  /// Starts listening and warms the first preload. Idempotent.
  ///
  /// In every mode this preloads an ad so one can be ready for a launch or a
  /// resume; whether it SHOWS on a foreground return is decided by
  /// [AppOpenConfig.triggerMode].
  void start() {
    if (_disposed || _sub != null) return;
    _sub = _sdk.appForegroundEvents.listen(_onForeground);
    unawaited(_controller.load());
  }

  /// Takes the one-shot cold-launch opportunity: shows an ALREADY-ready
  /// app-open ad, if the mode permits and one is warm, at real process launch.
  ///
  /// Call this from your real loading/startup screen, immediately before
  /// entering main content — after the loading screen has done its actual work.
  /// Contract:
  ///
  /// - It NEVER waits for network, UMP, SDK init, or a load. If no ad is ready
  ///   right now, it returns `false` immediately.
  /// - It is one-shot per process launch (surviving [AdFlow] reinitialization):
  ///   a mid-session or post-reinit call returns `false`. So a `false` here can
  ///   never turn into a surprise app-open ad after the user is in main content.
  /// - It is a no-op (`false`) under [AppOpenTriggerMode.resumeOnly].
  /// - The controller still enforces consent, caps, coordinator, expiry and
  ///   Remove-Ads; a refusal there also returns `false` (and re-warms the next).
  Future<bool> showAtLaunchIfReady() async {
    if (_disposed) return false;
    if (_config.triggerMode == AppOpenTriggerMode.resumeOnly) return false;
    // Consume the one-shot up front — even a not-ready launch spends the
    // launch moment, so we never show a "launch" ad seconds into the session.
    if (!_launch.consume()) return false;
    // Only an already-ready ad; never wait for a load.
    if (!_controller.isReady) return false;
    return _controller.show();
  }

  Future<void> _onForeground(AppForegroundEvent event) async {
    // launchOnly never auto-shows on resume — but keep one warm (it is the
    // launch path's inventory).
    if (_config.triggerMode == AppOpenTriggerMode.launchOnly) {
      unawaited(_controller.load());
      return;
    }
    // The user is coming back from a banner/native ad they just clicked: this
    // foreground event is a return FROM AN AD, not a genuine warm return
    // (ADR-042). One-shot — the next return is a normal one.
    if (_coordinator?.consumeViewAdOpened() ?? false) {
      unawaited(_controller.load());
      return;
    }
    // The app says a blocking banner/native ad currently occupies the screen —
    // do not stack an app-open ad over it (ADR-042).
    if (_coordinator?.blockingViewAdVisible ?? false) {
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
    // NOTE (ADR-043): there is deliberately no "first event is the cold start"
    // latch here. `AppStateEventNotifier` does not replay the cold-launch
    // foreground, so the first event we ever receive is a real
    // background→return. Invariant 3 (never show on a cold launch) is upheld
    // structurally: at cold launch nothing is loaded yet, so `show()` finds no
    // warm ad and returns false. A launch-moment show is the separate, explicit
    // [showAtLaunchIfReady] path. The controller enforces gate, caps,
    // coordinator and the 4h expiry; a false result also re-warms the next ad.
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
