import 'dart:async';

import '../config/ad_flow_config.dart';
import '../controllers/app_open_ad_controller.dart';
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
  AppOpenAdManager({
    required AppOpenAdController controller,
    required AdSdk sdk,
    required AppOpenConfig config,
  }) : _controller = controller,
       _sdk = sdk,
       _config = config;

  final AppOpenAdController _controller;
  final AdSdk _sdk;
  final AppOpenConfig _config;

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
    // The controller enforces gate, caps, coordinator and expiry; a
    // false result also re-warms the next ad.
    await _controller.show();
  }

  /// Stops the manager. Does NOT dispose the controller (the facade owns
  /// controller lifecycles).
  void dispose() => stop();
}
