// Copyright 2024 - AdMob Integration Package
// Ads Enabled Manager - Controls whether ads are shown (for Remove Ads feature)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback type for ads enabled status changes
typedef AdsEnabledCallback = void Function(bool isEnabled);

/// Manages the "Remove Ads" functionality with persistence.
///
/// This class provides:
/// - Centralized control over ad display
/// - Persistent storage of the ads enabled state
/// - Callbacks for state changes (for UI updates)
///
/// Usage:
/// ```dart
/// // Check if ads are enabled
/// if (AdsEnabledManager.instance.isEnabled) {
///   // Show ads
/// }
///
/// // Disable ads (after purchase)
/// await AdsEnabledManager.instance.disableAds();
///
/// // Re-enable ads (restore purchase failed, etc.)
/// await AdsEnabledManager.instance.enableAds();
/// ```
class AdsEnabledManager {
  AdsEnabledManager._();
  static final AdsEnabledManager _instance = AdsEnabledManager._();

  /// Singleton instance
  static AdsEnabledManager get instance => _instance;

  /// SharedPreferences key for storing ads enabled state
  static const String _prefsKey = 'faizads_ads_enabled';

  /// Whether ads are currently enabled
  bool _isEnabled = true;

  /// Whether the manager has been initialized (loaded from prefs)
  bool _isInitialized = false;

  /// List of listeners for state changes
  final List<AdsEnabledCallback> _listeners = [];

  /// StreamController for reactive updates
  final StreamController<bool> _streamController =
      StreamController<bool>.broadcast();

  /// Whether ads are enabled
  ///
  /// Returns `true` by default until [initialize] is called.
  /// After initialization, returns the persisted value.
  bool get isEnabled => _isEnabled;

  /// Whether ads are disabled (convenience getter)
  bool get isDisabled => !_isEnabled;

  /// Whether the manager has been initialized
  bool get isInitialized => _isInitialized;

  /// Stream of ads enabled status changes
  ///
  /// Use this for reactive UI updates:
  /// ```dart
  /// StreamBuilder<bool>(
  ///   stream: AdsEnabledManager.instance.stream,
  ///   builder: (context, snapshot) {
  ///     if (snapshot.data == false) return SizedBox.shrink();
  ///     return YourAdWidget();
  ///   },
  /// )
  /// ```
  Stream<bool> get stream => _streamController.stream;

  /// Initializes the manager by loading the persisted state.
  ///
  /// Call this early in your app's lifecycle, before showing any ads.
  /// This is automatically called by [AdFlow.initialize].
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefsKey) ?? true;
      _isInitialized = true;
      debugPrint('AdsEnabledManager: Initialized. Ads enabled: $_isEnabled');
    } catch (e) {
      debugPrint('AdsEnabledManager: Error loading state: $e');
      _isEnabled = true; // Default to enabled on error
      _isInitialized = true;
    }
  }

  /// Disables ads (call after successful "Remove Ads" purchase).
  ///
  /// This will:
  /// 1. Persist the disabled state
  /// 2. Notify all listeners
  /// 3. Update the stream
  ///
  /// Example:
  /// ```dart
  /// // After successful in-app purchase
  /// Future<void> onPurchaseComplete() async {
  ///   await AdsEnabledManager.instance.disableAds();
  ///   // Ads will no longer show anywhere in the app
  /// }
  /// ```
  Future<void> disableAds() async {
    if (!_isEnabled) return; // Already disabled

    _isEnabled = false;
    await _persist();
    _notifyListeners();
    debugPrint('AdsEnabledManager: ✅ Ads disabled');
  }

  /// Enables ads (call to restore ads, e.g., after restore purchase fails).
  ///
  /// This will:
  /// 1. Persist the enabled state
  /// 2. Notify all listeners
  /// 3. Update the stream
  Future<void> enableAds() async {
    if (_isEnabled) return; // Already enabled

    _isEnabled = true;
    await _persist();
    _notifyListeners();
    debugPrint('AdsEnabledManager: ✅ Ads enabled');
  }

  /// Toggles the ads enabled state.
  Future<void> toggle() async {
    if (_isEnabled) {
      await disableAds();
    } else {
      await enableAds();
    }
  }

  /// Adds a listener for ads enabled status changes.
  ///
  /// The callback will be called immediately with the current value,
  /// and again whenever the value changes.
  ///
  /// Remember to call [removeListener] when done to prevent memory leaks.
  void addListener(AdsEnabledCallback callback) {
    _listeners.add(callback);
    // Immediately notify with current value
    callback(_isEnabled);
  }

  /// Removes a previously added listener.
  void removeListener(AdsEnabledCallback callback) {
    _listeners.remove(callback);
  }

  /// Persists the current state to SharedPreferences.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, _isEnabled);
    } catch (e) {
      debugPrint('AdsEnabledManager: Error persisting state: $e');
    }
  }

  /// Notifies all listeners and the stream of the current state.
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener(_isEnabled);
    }
    _streamController.add(_isEnabled);
  }

  /// Clears the persisted state (for testing purposes).
  @visibleForTesting
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      _isEnabled = true;
      _isInitialized = false;
      _notifyListeners();
    } catch (e) {
      debugPrint('AdsEnabledManager: Error resetting state: $e');
    }
  }

  /// Disposes the manager (for cleanup).
  void dispose() {
    _listeners.clear();
    _streamController.close();
  }
}
