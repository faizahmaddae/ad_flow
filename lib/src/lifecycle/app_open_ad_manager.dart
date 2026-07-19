import 'dart:async';

import '../config/ad_flow_config.dart';
import '../controllers/app_open_ad_controller.dart';
import '../policy/full_screen_ad_coordinator.dart';
import '../core/callback_guard.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';

/// The single owner of app-open-on-foreground behavior (v1 trap: two
/// reactors coordinated through statics fought each other — the facade
/// creates exactly one manager and nothing else reacts to foreground).
///
/// Subscribes to the seam's foreground events (backed by
/// `AppStateEventNotifier` — the only correct signal; iOS `inactive` is
/// NOT backgrounding) and shows the warm ad on every foreground return,
/// with all policy checks delegated to the controller and gate:
/// consent, enabled, frequency caps, coordinator suppression, 4h expiry.
///
/// Cold-start rule (ADR-043): every foreground return may show an ad,
/// **including the first one**. `AppStateEventNotifier` does NOT replay the
/// cold-launch foreground — the seam only calls `startListening()` once the app
/// is already foregrounded — so the first event the manager ever receives is a
/// genuine background→return. Invariant 3 ("never show on a cold launch") holds
/// structurally: at cold launch no ad is loaded yet, so there is nothing to
/// show.
class AppOpenAdManager {
  /// Creates the manager. Call [start] to begin reacting to foreground
  /// returns.
  ///
  /// [coordinator] — when provided, the SAME [FullScreenAdCoordinator]
  /// instance shared with every other controller — lets the manager avoid
  /// showing an app-open ad immediately behind another format's dismiss
  /// (review finding #7: on dismiss, the coordinator clears synchronously,
  /// before the app's own warm-start signal necessarily settles, so
  /// without this only a non-zero `globalFrequencyCap.minGap` stood
  /// between an interstitial closing and an app-open opening — and that's
  /// an app-configurable value that can be zero). [postDismissSuppression]
  /// is the minimum gap enforced; [now] is an injectable clock for tests.
  AppOpenAdManager({
    required AppOpenAdController controller,
    required AdSdk sdk,
    required AppOpenConfig config,
    FullScreenAdCoordinator? coordinator,
    Duration postDismissSuppression = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _controller = controller,
       _sdk = sdk,
       _coordinator = coordinator,
       _postDismissSuppression = postDismissSuppression,
       _now = now ?? DateTime.now;

  final AppOpenAdController _controller;
  final AdSdk _sdk;
  final FullScreenAdCoordinator? _coordinator;
  final Duration _postDismissSuppression;
  final DateTime Function() _now;

  StreamSubscription<AppForegroundEvent>? _sub;

  /// Whether the manager is currently reacting to foreground events.
  bool get isStarted => _sub != null;

  /// Starts listening and warms the first preload. Idempotent.
  void start() {
    if (_sub != null) return;
    _sub = _sdk.appForegroundEvents.listen(_onForeground);
    unawaited(_controller.load());
  }

  /// Stops reacting to foreground events (the controller keeps its ad).
  void stop() {
    safeUnawaited(_sub?.cancel(), debugName: 'subscription');
    _sub = null;
  }

  Future<void> _onForeground(AppForegroundEvent event) async {
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
    // latch here any more. `AppStateEventNotifier` does not replay the
    // cold-launch foreground — the seam calls `startListening()` only once the
    // app is already foregrounded — so the first event we ever receive is a
    // real background→return, and swallowing it threw away one app-open
    // impression in EVERY session. Invariant 3 (never show on a cold launch)
    // is upheld structurally instead: at cold launch nothing is loaded yet, so
    // `show()` finds no warm ad and returns false. The controller enforces
    // gate, caps, coordinator and the 4h expiry; a false result also re-warms
    // the next ad.
    await _controller.show();
  }

  bool _withinPostDismissSuppression() {
    if (_postDismissSuppression <= Duration.zero) return false;
    final lastExit = _coordinator?.lastExitAt;
    if (lastExit == null) return false;
    return _now().difference(lastExit) < _postDismissSuppression;
  }

  /// Stops the manager. Does NOT dispose the controller (the facade owns
  /// controller lifecycles).
  void dispose() => stop();
}
