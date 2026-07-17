import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preloaded full-screen ads EXPIRE (2026-07 audit).
///
/// Google documents full-screen ads as expiring after ~1 hour (4h for
/// app-open): a stale ad shown late may fail to display, or display but not
/// count. Before this, only app-open enforced an age; an interstitial
/// preloaded at session start and shown three hours later was silently
/// revenue-dead inventory occupying the slot's one natural break.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    now = DateTime(2026, 7, 17, 12);
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  final blocked = <AdBlockReason>[];

  InterstitialAdController controller({Duration? maxAdAge}) =>
      InterstitialAdController(
        onBlocked: (slot, reason) => blocked.add(reason),
        sdk: sdk,
        gate: AdGate(
          canRequestAds: sdk.canRequestAds,
          isEnabled: () => true,
          caps: caps,
          coordinator: coordinator,
        ),
        caps: caps,
        coordinator: coordinator,
        config: InterstitialConfig(
          adUnitId: const PlatformAdUnitId(android: 'unit-i'),
          maxAdAge: maxAdAge,
        ),
        adUnitId: 'unit-i',
        retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        now: () => now,
      );

  test('the expiry timer proactively replaces a stale warm ad', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: const Duration(minutes: 55));
      c.load();
      async.flushMicrotasks();
      final first = sdk.interstitials.single;
      expect(c.isReady, isTrue);

      // Keep the injectable policy clock in step with fakeAsync's elapse.
      now = now.add(const Duration(minutes: 56));
      async.elapse(const Duration(minutes: 56));
      async.flushMicrotasks();

      expect(
        first.disposed,
        isTrue,
        reason: 'the stale ad must be discarded, never shown',
      );
      expect(
        sdk.interstitials,
        hasLength(2),
        reason: 'a fresh ad must be warm for the next natural break',
      );
      expect(c.isReady, isTrue);
      c.dispose();
    });
  });

  test('show() at expiry (timer never fired — suspended app) discards and '
      'reloads instead of showing', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: const Duration(minutes: 55));
      c.load();
      async.flushMicrotasks();
      final first = sdk.interstitials.single;

      // The wall clock jumps past the age (the app was suspended, so the
      // Dart timer never ran) — only the show-time check can catch this.
      now = now.add(const Duration(hours: 2));
      var shown = true;
      c.show().then((v) => shown = v);
      async.flushMicrotasks();

      expect(shown, isFalse);
      expect(first.showCalls, 0, reason: 'a stale ad must never be shown');
      expect(first.disposed, isTrue);
      // Not lastBlockReason: the immediate successful reload rightly clears
      // that snapshot — the one-shot callback is the durable record.
      expect(blocked, contains(AdBlockReason.expired));
      expect(sdk.interstitials, hasLength(2), reason: 'fresh one warming');
      c.dispose();
    });
  });

  test('maxAdAge: null disables expiry entirely', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: null);
      c.load();
      async.flushMicrotasks();

      now = now.add(const Duration(hours: 6));
      async.elapse(const Duration(hours: 6));
      async.flushMicrotasks();

      expect(sdk.interstitials, hasLength(1));
      var shown = false;
      c.show().then((v) => shown = v);
      async.flushMicrotasks();
      expect(shown, isTrue);
      c.dispose();
    });
  });

  test('a show comfortably inside the age window is unaffected', () {
    fakeAsync((async) {
      final c = controller(maxAdAge: const Duration(minutes: 55));
      c.load();
      async.flushMicrotasks();

      now = now.add(const Duration(minutes: 30));
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();

      var shown = false;
      c.show().then((v) => shown = v);
      async.flushMicrotasks();
      expect(shown, isTrue);
      c.dispose();
    });
  });
}
