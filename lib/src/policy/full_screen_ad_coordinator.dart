import 'package:flutter/foundation.dart';

/// Single source of truth for "is a full-screen ad on screen right now?".
///
/// Injected (never static — v1 trap #6) into every full-screen controller
/// and the app-open manager, so an app-open ad can never fire over an
/// interstitial and vice versa.
class FullScreenAdCoordinator {
  /// Creates a coordinator. [now] is an injectable clock (tests only) for
  /// [lastExitAt].
  FullScreenAdCoordinator({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);
  final DateTime Function() _now;
  int _depth = 0;
  DateTime? _lastExitAt;

  /// When the last full-screen ad (of any format) exited, or `null` if
  /// none has yet this session. Consulted by [AppOpenAdManager] to avoid
  /// showing an app-open ad immediately behind another format's dismiss
  /// (review finding #7) — purely informational otherwise, and does not
  /// affect [tryEnter]/[isFullScreenAdVisible] at all.
  DateTime? get lastExitAt => _lastExitAt;

  /// Whether a full-screen ad is currently showing.
  bool get isFullScreenAdVisible => _depth > 0;

  /// Reactive view of [isFullScreenAdVisible].
  ValueListenable<bool> get visible => _visible;

  /// Marks a full-screen ad as visible. Must be balanced by [exit].
  void enter() {
    _depth++;
    _visible.value = true;
  }

  /// Atomically checks [isFullScreenAdVisible] and claims the coordinator
  /// in one synchronous step — no `await` between the check and the entry.
  ///
  /// This is the ONLY safe way for two independently-gated controllers
  /// (e.g. interstitial + app open) to race for the coordinator: an
  /// `await`-separated check-then-enter lets both controllers observe
  /// "nothing is showing" before either has entered, so both proceed to
  /// show. A plain synchronous method has no such window — Dart's
  /// single-threaded event loop guarantees nothing else runs between this
  /// method's check and its own [enter] call.
  bool tryEnter() {
    if (isFullScreenAdVisible) return false;
    enter();
    return true;
  }

  /// Marks the full-screen ad as gone. Call from dismiss AND fail-to-show
  /// handlers. Unbalanced calls are clamped at zero (defensive: a missed
  /// enter must never wedge suppression on).
  void exit() {
    if (_depth > 0) _depth--;
    if (_depth == 0) _lastExitAt = _now();
    _visible.value = _depth > 0;
  }

  /// Releases the notifier.
  void dispose() => _visible.dispose();
}
