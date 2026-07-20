import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Native ads EXPIRE (5.1 hardening).
///
/// Google documents native ads as expiring after ~1 hour; before this the
/// [NativeAdController] kept a loaded ad until manual reload/dispose, so a
/// long-lived screen could render revenue-dead (or policy-noncompliant) stale
/// inventory indefinitely. The controller now timestamps loads, arms an expiry
/// timer, and drops-and-reloads through the normal gate at [NativeConfig.maxAdAge].
void main() {
  late FakeAdSdk sdk;
  late bool consented;
  late DateTime now;
  final blocked = <AdBlockReason>[];

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    consented = true;
    now = DateTime(2026, 7, 20, 12);
    blocked.clear();
  });
  tearDown(() => sdk.dispose());

  NativeAdController controller({
    Duration? maxAdAge = const Duration(minutes: 55),
  }) => NativeAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => consented && sdk.canRequestAdsResult,
      isEnabled: () => true,
    ),
    config: NativeConfig(
      adUnitId: const PlatformAdUnitId(android: 'unit-n'),
      templateKind: NativeTemplateKind.medium,
      maxAdAge: maxAdAge,
    ),
    adUnitId: 'unit-n',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
    onBlocked: (slot, reason) => blocked.add(reason),
    now: () => now,
  );

  test(
    'the expiry timer discards a stale native ad and reloads a fresh one',
    () {
      fakeAsync((async) {
        final c = controller(maxAdAge: const Duration(minutes: 55));
        c.load();
        async.flushMicrotasks();
        final first = sdk.natives.single;
        expect(c.state.value, const AdLoaded());
        expect(c.isExpired, isFalse);

        now = now.add(const Duration(minutes: 56));
        async.elapse(const Duration(minutes: 56));
        async.flushMicrotasks();

        expect(
          first.disposed,
          isTrue,
          reason: 'stale inventory must never keep rendering past maxAdAge',
        );
        expect(sdk.natives, hasLength(2), reason: 'a fresh ad replaces it');
        expect(c.state.value, const AdLoaded());
        expect(c.handle, same(sdk.natives.last));
        expect(c.isExpired, isFalse); // new timestamp
        expect(blocked, contains(AdBlockReason.expired));
        c.dispose();
      });
    },
  );

  test('maxAdAge: null disables native expiry entirely', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: null);
      c.load();
      async.flushMicrotasks();

      now = now.add(const Duration(hours: 6));
      async.elapse(const Duration(hours: 6));
      async.flushMicrotasks();

      expect(sdk.natives, hasLength(1), reason: 'no expiry, no reload');
      expect(c.isExpired, isFalse);
      c.dispose();
    });
  });

  test(
    'resume after a long suspension: the overdue timer drops the aged ad',
    () {
      fakeAsync((async) {
        final c = controller(maxAdAge: const Duration(minutes: 55));
        c.load();
        async.flushMicrotasks();
        final first = sdk.natives.single;

        // App suspended ~2h (Dart timers do not fire while suspended); the wall
        // clock has jumped. On resume the overdue timer fires.
        now = now.add(const Duration(hours: 2));
        async.elapse(const Duration(hours: 2));
        async.flushMicrotasks();

        expect(first.disposed, isTrue);
        expect(sdk.natives, hasLength(2));
        expect(c.isExpired, isFalse);
        c.dispose();
      });
    },
  );

  test(
    'manual reload near expiry re-timestamps: no premature expiry after',
    () {
      fakeAsync((async) {
        final c = controller(maxAdAge: const Duration(minutes: 55));
        c.load();
        async.flushMicrotasks();
        final first = sdk.natives.single;

        // 54 minutes in — just under the age — the app manually reloads.
        now = now.add(const Duration(minutes: 54));
        async.elapse(const Duration(minutes: 54));
        c.reload();
        async.flushMicrotasks();
        expect(first.disposed, isTrue);
        expect(sdk.natives, hasLength(2));

        // Another 54 minutes: the fresh ad is only 54 min old — must NOT expire
        // on the original ad's stale timer.
        now = now.add(const Duration(minutes: 54));
        async.elapse(const Duration(minutes: 54));
        async.flushMicrotasks();
        expect(
          sdk.natives,
          hasLength(2),
          reason: 'no reload; the reloaded ad is still fresh',
        );
        expect(c.handle, same(sdk.natives.last));
        expect(sdk.natives.last.disposed, isFalse);
        c.dispose();
      });
    },
  );

  test('dispose cancels the expiry timer (no reload on a dead controller)', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: const Duration(minutes: 55));
      c.load();
      async.flushMicrotasks();
      expect(sdk.natives, hasLength(1));

      c.dispose();
      now = now.add(const Duration(hours: 2));
      async.elapse(const Duration(hours: 2));
      async.flushMicrotasks();

      expect(
        sdk.natives,
        hasLength(1),
        reason: 'a disposed controller never reloads',
      );
    });
  });

  test('consent withdrawal drops the ad; the expiry timer does not reload '
      'behind the closed gate', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: const Duration(minutes: 55));
      c.load();
      async.flushMicrotasks();
      final first = sdk.natives.single;

      // Consent withdrawn (e.g. via privacy options); the gate recheck drops
      // the live ad — and, doing so, cancels the shared timer (the expiry
      // timer is reclaimed for the gate re-check).
      consented = false;
      sdk.canRequestAdsResult = false;
      c.recheckGate();
      async.flushMicrotasks();

      expect(first.disposed, isTrue);
      expect(c.state.value, isA<AdBlocked>());

      // While the gate stays closed, no native ad ever renders again — every
      // re-check is re-blocked (a bounded window; the gate re-check backs off).
      now = now.add(const Duration(minutes: 5));
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(
        sdk.natives.every((n) => n.disposed),
        isTrue,
        reason: 'no undisposed ad may exist behind a closed gate',
      );
      expect(c.state.value, isA<AdBlocked>());
      c.dispose();
    });
  });

  test(
    'a failed replacement load after expiry drops the stale ad and retries',
    () {
      fakeAsync((async) {
        final c = controller(maxAdAge: const Duration(minutes: 55));
        c.load();
        async.flushMicrotasks();
        final first = sdk.natives.single;

        // The replacement will fail to fill.
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        now = now.add(const Duration(minutes: 56));
        async.elapse(const Duration(minutes: 56));
        async.flushMicrotasks();

        expect(
          first.disposed,
          isTrue,
          reason: 'the expired ad is gone regardless of the replacement',
        );
        expect(c.state.value, isA<AdFailed>());

        // Recovery: a later successful load restores an ad.
        sdk.alwaysLoadError = null;
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(c.state.value, const AdLoaded());
        c.dispose();
      });
    },
  );
}
