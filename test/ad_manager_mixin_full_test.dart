// Tests for AdStatusNotifier and AdRetryHandler mixins

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

/// Concrete test class using both mixins
class TestAdManager with AdStatusNotifier, AdRetryHandler implements AdManager {
  bool _isLoaded = false;
  bool _isLoading = false;

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get isShowing => false;

  int loadCallCount = 0;

  Future<void> loadAd() async {
    resetDisposedState();
    if (isInRetryCooldown(managerName: 'TestAd')) return;
    _isLoading = true;
    loadCallCount++;
    notifyStatusListeners();
  }

  void simulateLoadSuccess() {
    _isLoading = false;
    _isLoaded = true;
    resetRetryAttempts();
    notifyStatusListeners();
  }

  void simulateLoadFailure() {
    _isLoading = false;
    _isLoaded = false;
    handleLoadFailure(
      checkDisposed: () => isDisposed,
      onRetry: () => loadAd(),
      managerName: 'TestAd',
    );
    notifyStatusListeners();
  }

  @override
  Future<void> dispose() async {
    disposeNotifier();
    cancelRetryTimer();
  }

  // Public test wrappers for @protected mixin methods
  void testNotify() => notifyStatusListeners();
  void testDispose() => disposeNotifier();
  void testResetDisposed() => resetDisposedState();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AdFlowPlatform.platformOverride = TargetPlatform.android;
    AdFlowConfig.setCurrent(AdFlowConfig.testMode());
  });

  tearDown(() {
    AdFlowPlatform.reset();
    AdFlowConfig.resetCurrent();
  });

  group('AdStatusNotifier', () {
    test('starts not disposed', () {
      final manager = TestAdManager();
      expect(manager.isDisposed, false);
      manager.dispose();
    });

    test('addStatusListener and notifyStatusListeners', () {
      final manager = TestAdManager();
      int callCount = 0;
      manager.addStatusListener(() => callCount++);
      manager.testNotify();
      expect(callCount, 1);
      manager.testNotify();
      expect(callCount, 2);
      manager.dispose();
    });

    test('removeStatusListener stops notifications', () {
      final manager = TestAdManager();
      int callCount = 0;
      void listener() => callCount++;
      manager.addStatusListener(listener);
      manager.testNotify();
      expect(callCount, 1);
      manager.removeStatusListener(listener);
      manager.testNotify();
      expect(callCount, 1); // No change
      manager.dispose();
    });

    test('disposeNotifier clears listeners and sets disposed', () {
      final manager = TestAdManager();
      int callCount = 0;
      manager.addStatusListener(() => callCount++);
      manager.testDispose();
      expect(manager.isDisposed, true);
      manager.testNotify(); // No-op after dispose
      expect(callCount, 0);
    });

    test('notifyStatusListeners is no-op when disposed', () {
      final manager = TestAdManager();
      int callCount = 0;
      manager.addStatusListener(() => callCount++);
      manager.testDispose();
      manager.testNotify();
      expect(callCount, 0);
    });

    test('resetDisposedState allows reuse', () {
      final manager = TestAdManager();
      manager.testDispose();
      expect(manager.isDisposed, true);
      manager.testResetDisposed();
      expect(manager.isDisposed, false);
    });

    test('isShowing defaults to false', () {
      final manager = TestAdManager();
      expect(manager.isShowing, false);
      manager.dispose();
    });
  });

  group('AdRetryHandler', () {
    test('retryAttempts starts at 0', () {
      final manager = TestAdManager();
      expect(manager.retryAttempts, 0);
      manager.dispose();
    });

    test('handleLoadFailure increments retry attempts', () {
      final manager = TestAdManager();
      manager.simulateLoadFailure();
      expect(manager.retryAttempts, 1);
      manager.dispose();
    });

    test('handleLoadFailure schedules retry when under max', () async {
      final manager = TestAdManager();
      // maxLoadRetries defaults to 3

      manager.simulateLoadFailure(); // attempt 1
      expect(manager.retryAttempts, 1);

      // Wait for retry timer to fire
      await Future.delayed(const Duration(seconds: 6));
      // Retry should have been called
      expect(manager.loadCallCount, greaterThanOrEqualTo(1));
      manager.dispose();
    });

    test('handleLoadFailure enters cooldown after max retries', () {
      final manager = TestAdManager();
      // maxLoadRetries is 3
      manager.simulateLoadFailure(); // 1
      manager.simulateLoadFailure(); // 2
      manager.simulateLoadFailure(); // 3 - should enter cooldown

      expect(manager.retryAttempts, 3);
      expect(manager.isInRetryCooldown(managerName: 'TestAd'), true);
      manager.dispose();
    });

    test('isInRetryCooldown returns false before max retries', () {
      final manager = TestAdManager();
      manager.simulateLoadFailure(); // 1
      expect(manager.isInRetryCooldown(), false);
      manager.dispose();
    });

    test('resetRetryAttempts resets counter', () {
      final manager = TestAdManager();
      manager.simulateLoadFailure();
      expect(manager.retryAttempts, 1);
      manager.resetRetryAttempts();
      expect(manager.retryAttempts, 0);
      manager.dispose();
    });

    test('resetRetryState resets everything', () {
      final manager = TestAdManager();
      manager.simulateLoadFailure();
      manager.simulateLoadFailure();
      manager.simulateLoadFailure(); // Hit max
      expect(manager.isInRetryCooldown(), true);
      manager.resetRetryState();
      expect(manager.retryAttempts, 0);
      expect(manager.isInRetryCooldown(), false);
      manager.dispose();
    });

    test('cancelRetryTimer cancels pending timer', () async {
      final manager = TestAdManager();
      manager.simulateLoadFailure(); // schedules retry
      manager.cancelRetryTimer(); // cancel it
      final countBefore = manager.loadCallCount;
      await Future.delayed(const Duration(seconds: 6));
      expect(manager.loadCallCount, countBefore); // no retry happened
      manager.dispose();
    });

    test('retry not called when disposed', () async {
      final manager = TestAdManager();
      manager.simulateLoadFailure(); // schedules retry
      await manager.dispose(); // disposes and cancels timer
      final countBefore = manager.loadCallCount;
      await Future.delayed(const Duration(seconds: 6));
      expect(manager.loadCallCount, countBefore);
    });
  });
}
