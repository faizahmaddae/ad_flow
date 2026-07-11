import 'package:flutter/foundation.dart';

/// Single source of truth for "is a full-screen ad on screen right now?".
///
/// Injected (never static — v1 trap #6) into every full-screen controller
/// and the app-open manager, so an app-open ad can never fire over an
/// interstitial and vice versa.
class FullScreenAdCoordinator {
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);
  int _depth = 0;

  /// Whether a full-screen ad is currently showing.
  bool get isFullScreenAdVisible => _depth > 0;

  /// Reactive view of [isFullScreenAdVisible].
  ValueListenable<bool> get visible => _visible;

  /// Marks a full-screen ad as visible. Call from the `AdShowedEvent`
  /// handler; must be balanced by [exit].
  void enter() {
    _depth++;
    _visible.value = true;
  }

  /// Marks the full-screen ad as gone. Call from dismiss AND fail-to-show
  /// handlers. Unbalanced calls are clamped at zero (defensive: a missed
  /// enter must never wedge suppression on).
  void exit() {
    if (_depth > 0) _depth--;
    _visible.value = _depth > 0;
  }

  /// Releases the notifier.
  void dispose() => _visible.dispose();
}
