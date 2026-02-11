// Copyright 2024 - AdMob Integration Package
// Shared mixins and contract for ad managers to reduce code duplication

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'ad_config.dart';

// ============================================================================
// AD MANAGER CONTRACT
// ============================================================================

/// Common contract for all ad managers in ad_flow.
///
/// All ad managers implement this interface, enabling type-safe collections
/// and ensuring consistent API across ad formats.
///
/// ```dart
/// // Work with any ad manager generically
/// void disposeAll(List<AdManager> managers) {
///   for (final m in managers) {
///     m.dispose();
///   }
/// }
/// ```
abstract class AdManager {
  /// Whether an ad is currently loaded and ready.
  bool get isLoaded;

  /// Whether an ad is currently being loaded.
  bool get isLoading;

  /// Whether the manager has been disposed.
  bool get isDisposed;

  /// Whether a fullscreen ad is currently being shown.
  ///
  /// Always `false` for non-fullscreen ad types (banner, native).
  bool get isShowing => false;

  /// Add a listener for status changes (loaded, loading, dismissed, etc.).
  void addStatusListener(VoidCallback listener);

  /// Remove a previously added listener.
  void removeStatusListener(VoidCallback listener);

  /// Dispose the manager and free all resources.
  Future<void> dispose();
}

// ============================================================================
// STATUS NOTIFIER MIXIN
// ============================================================================

/// Provides status listener notification for ad managers.
///
/// Encapsulates the common pattern of tracking disposed state and
/// notifying UI listeners when ad status changes (loaded, loading,
/// showing, dismissed, etc.).
///
/// All ad managers use this mixin for consistent status notification:
/// ```dart
/// class MyAdManager with AdStatusNotifier, AdRetryHandler
///     implements AdManager {
///   void _onAdLoaded() {
///     notifyStatusListeners(); // Notify UI
///   }
///
///   Future<void> dispose() async {
///     disposeNotifier(); // Clears listeners, marks disposed
///   }
/// }
/// ```
mixin AdStatusNotifier {
  final List<VoidCallback> _statusListeners = [];
  bool _adNotifierDisposed = false;

  /// Whether this ad manager has been disposed.
  bool get isDisposed => _adNotifierDisposed;

  /// Add a listener that will be called when the ad status changes.
  void addStatusListener(VoidCallback listener) {
    _statusListeners.add(listener);
  }

  /// Remove a previously added listener.
  void removeStatusListener(VoidCallback listener) {
    _statusListeners.remove(listener);
  }

  /// Notify all listeners of a status change.
  ///
  /// Safe from concurrent modification — iterates a copy via `List.of()`.
  /// No-op if the manager has been disposed.
  @protected
  void notifyStatusListeners() {
    if (_adNotifierDisposed) return;
    for (final listener in List.of(_statusListeners)) {
      listener();
    }
  }

  /// Marks the manager as disposed and clears all listeners.
  ///
  /// Call this in your manager's `dispose()` method.
  @protected
  void disposeNotifier() {
    _adNotifierDisposed = true;
    _statusListeners.clear();
  }

  /// Resets the disposed flag to allow reuse.
  ///
  /// Managers are accessed via lazy getters on [AdFlow], so they may be
  /// reused after disposal. Call this at the start of `loadAd()`.
  @protected
  void resetDisposedState() {
    _adNotifierDisposed = false;
  }
}

// ============================================================================
// RETRY HANDLER MIXIN
// ============================================================================

/// Provides retry logic with linear backoff and cooldown for ad loading.
///
/// Encapsulates the common pattern of retrying failed ad loads with
/// linearly increasing delays (`retryDelay * attempt`), entering a
/// cooldown period after max retries, and tracking cancellable retry
/// timers.
///
/// Uses [Timer] instead of `Future.delayed` for explicit cancellation
/// on dispose, preventing post-dispose callbacks.
///
/// ```dart
/// class MyAdManager with AdStatusNotifier, AdRetryHandler
///     implements AdManager {
///   Future<void> loadAd() async {
///     resetDisposedState();
///     if (isInRetryCooldown(managerName: 'MyAdManager')) return;
///     // ... load ad ...
///   }
///
///   void _onAdFailedToLoad() {
///     handleLoadFailure(
///       checkDisposed: () => isDisposed,
///       onRetry: () => loadAd(),
///       managerName: 'MyAdManager',
///     );
///   }
///
///   Future<void> dispose() async {
///     disposeNotifier();
///     cancelRetryTimer();
///   }
/// }
/// ```
mixin AdRetryHandler {
  int _retryAttempts = 0;
  DateTime? _lastMaxRetryFailureTime;
  Timer? _retryTimer;

  /// Number of load attempts made since last success or cooldown reset.
  int get retryAttempts => _retryAttempts;

  /// Checks if the manager is in retry cooldown after exhausting max retries.
  ///
  /// Returns `true` if in cooldown (caller should skip loading).
  /// If cooldown has expired, resets attempt counter and returns `false`.
  ///
  /// [managerName] is used for debug logging.
  bool isInRetryCooldown({String? managerName}) {
    if (_retryAttempts >= AdFlowConfig.current.maxLoadRetries &&
        _lastMaxRetryFailureTime != null) {
      final elapsed = DateTime.now().difference(_lastMaxRetryFailureTime!);
      if (elapsed < AdFlowConfig.current.retryCooldownAfterMaxAttempts) {
        final remaining =
            AdFlowConfig.current.retryCooldownAfterMaxAttempts - elapsed;
        debugPrint(
          '${managerName ?? 'AdManager'}: In cooldown after max retries '
          '(${remaining.inSeconds}s remaining)',
        );
        return true;
      } else {
        _retryAttempts = 0;
        _lastMaxRetryFailureTime = null;
      }
    }
    return false;
  }

  /// Records a failed load attempt and optionally schedules a retry.
  ///
  /// Returns `true` if a retry was scheduled, `false` if max retries exhausted.
  ///
  /// Uses a cancellable [Timer] that is properly cleaned up on
  /// [cancelRetryTimer] / dispose. Delay increases linearly:
  /// `retryDelay * attempt` (e.g. 5s, 10s, 15s for attempts 1, 2, 3).
  ///
  /// [checkDisposed] returns the current disposed state at timer fire time.
  /// [onRetry] is called after delay if retry is scheduled.
  /// [managerName] is used for debug logging.
  bool handleLoadFailure({
    required bool Function() checkDisposed,
    required VoidCallback onRetry,
    String? managerName,
  }) {
    _retryAttempts++;
    final name = managerName ?? 'AdManager';

    if (_retryAttempts < AdFlowConfig.current.maxLoadRetries) {
      debugPrint('$name: Retrying load (attempt $_retryAttempts)...');
      _retryTimer?.cancel();
      _retryTimer = Timer(
        AdFlowConfig.current.retryDelay * _retryAttempts,
        () {
          if (checkDisposed()) return;
          onRetry();
        },
      );
      return true;
    } else {
      _lastMaxRetryFailureTime = DateTime.now();
      debugPrint(
        '$name: Max retries exhausted, entering '
        '${AdFlowConfig.current.retryCooldownAfterMaxAttempts.inMinutes}min cooldown',
      );
      return false;
    }
  }

  /// Resets attempt counter on successful load.
  void resetRetryAttempts() {
    _retryAttempts = 0;
  }

  /// Resets all retry state (attempts, cooldown timestamp, timer).
  void resetRetryState() {
    _retryAttempts = 0;
    _lastMaxRetryFailureTime = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Cancels any pending retry timer.
  ///
  /// Call this in your manager's `dispose()` to prevent post-dispose callbacks.
  void cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
