import 'dart:async';

import '../config/ad_flow_config.dart';
import '../controllers/app_open_ad_controller.dart';
import '../policy/full_screen_ad_coordinator.dart';
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
/// Cold-start rule: the underlying platform notifier emits a foreground
/// event on app start too, so the FIRST event after [start] never shows an
/// ad (it just warms the preload) unless [AppOpenConfig.showOnColdStart]
/// is explicitly on.
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
  bool _firstEventSeen = false;

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
    unawaited(_sub?.cancel());
    _sub = null;
  }

  Future<void> _onForeground(AppForegroundEvent event) async {
    if (!_firstEventSeen) {
      _firstEventSeen = true;
      if (!_config.showOnColdStart) {
        // Cold start: never show, just make sure one is warm.
        unawaited(_controller.load());
        return;
      }
    }
    if (_withinPostDismissSuppression()) {
      // Another full-screen ad (of any format) just closed — never stack
      // an app-open ad right behind it (review finding #7). Still keep
      // one warm for the next legitimate opportunity.
      unawaited(_controller.load());
      return;
    }
    // The controller enforces gate, caps, coordinator and expiry; a
    // false result also re-warms the next ad.
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
