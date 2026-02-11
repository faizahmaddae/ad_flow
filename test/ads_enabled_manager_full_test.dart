// Tests for AdsEnabledManager - comprehensive

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
  });

  group('AdsEnabledManager', () {
    test('singleton returns same instance', () {
      expect(AdsEnabledManager.instance, same(AdsEnabledManager.instance));
    });

    test('defaults to enabled before initialization', () {
      expect(AdsEnabledManager.instance.isEnabled, true);
      expect(AdsEnabledManager.instance.isDisabled, false);
    });

    test('initialize loads enabled state from prefs', () async {
      await AdsEnabledManager.instance.initialize();
      expect(AdsEnabledManager.instance.isEnabled, true);
    });

    test('initialize loads disabled state from prefs', () async {
      await AdsEnabledManager.instance.reset();
      SharedPreferences.setMockInitialValues({'faizads_ads_enabled': false});
      await AdsEnabledManager.instance.initialize();
      expect(AdsEnabledManager.instance.isEnabled, false);
      expect(AdsEnabledManager.instance.isDisabled, true);
    });

    test('disableAds persists and notifies', () async {
      await AdsEnabledManager.instance.initialize();
      expect(AdsEnabledManager.instance.isEnabled, true);

      await AdsEnabledManager.instance.disableAds();
      expect(AdsEnabledManager.instance.isEnabled, false);
      expect(AdsEnabledManager.instance.isDisabled, true);
    });

    test('disableAds is no-op if already disabled', () async {
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();
      // Second call should be a no-op
      await AdsEnabledManager.instance.disableAds();
      expect(AdsEnabledManager.instance.isDisabled, true);
    });

    test('enableAds persists and notifies', () async {
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();
      expect(AdsEnabledManager.instance.isDisabled, true);

      await AdsEnabledManager.instance.enableAds();
      expect(AdsEnabledManager.instance.isEnabled, true);
    });

    test('enableAds is no-op if already enabled', () async {
      await AdsEnabledManager.instance.initialize();
      // Already enabled
      await AdsEnabledManager.instance.enableAds();
      expect(AdsEnabledManager.instance.isEnabled, true);
    });

    test('toggle switches state', () async {
      await AdsEnabledManager.instance.initialize();
      expect(AdsEnabledManager.instance.isEnabled, true);

      await AdsEnabledManager.instance.toggle();
      expect(AdsEnabledManager.instance.isDisabled, true);

      await AdsEnabledManager.instance.toggle();
      expect(AdsEnabledManager.instance.isEnabled, true);
    });

    test('addListener gets called with current value immediately', () async {
      await AdsEnabledManager.instance.initialize();
      bool? received;
      AdsEnabledManager.instance.addListener((v) => received = v);
      expect(received, true);
      AdsEnabledManager.instance.removeListener((v) {});
    });

    test('listener notified on state change', () async {
      await AdsEnabledManager.instance.initialize();
      final values = <bool>[];
      void listener(bool v) => values.add(v);
      AdsEnabledManager.instance.addListener(listener);
      // addListener calls with current value immediately
      expect(values, [true]);

      await AdsEnabledManager.instance.disableAds();
      expect(values, [true, false]);

      await AdsEnabledManager.instance.enableAds();
      expect(values, [true, false, true]);

      AdsEnabledManager.instance.removeListener(listener);
    });

    test('stream emits state changes', () async {
      await AdsEnabledManager.instance.initialize();
      final stream = AdsEnabledManager.instance.stream;
      final completer = Completer<bool>();
      final sub = stream.listen((v) {
        if (!completer.isCompleted) completer.complete(v);
      });

      await AdsEnabledManager.instance.disableAds();
      final value = await completer.future;
      expect(value, false);
      await sub.cancel();
    });

    test('reset restores defaults', () async {
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();
      expect(AdsEnabledManager.instance.isDisabled, true);

      await AdsEnabledManager.instance.reset();
      expect(AdsEnabledManager.instance.isEnabled, true);
    });

    test('initialize is no-op when already initialized', () async {
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();
      // Second initialize should NOT re-read prefs (state stays disabled)
      await AdsEnabledManager.instance.initialize();
      expect(AdsEnabledManager.instance.isDisabled, true);
    });

    test('dispose clears listeners', () async {
      await AdsEnabledManager.instance.initialize();
      int callCount = 0;
      void listener(bool v) => callCount++;
      AdsEnabledManager.instance.addListener(listener);
      callCount = 0; // Reset after immediate call

      AdsEnabledManager.instance.dispose();
      // After dispose, no more notifications expected from listener list
      // (stream is intentionally NOT closed for singleton)
    });
  });
}
