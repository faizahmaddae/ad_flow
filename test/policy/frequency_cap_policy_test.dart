import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryKeyValueStore store;
  late DateTime now;

  setUp(() {
    store = InMemoryKeyValueStore();
    now = DateTime(2026, 7, 11, 12);
  });

  StoredFrequencyCapPolicy policy({
    Map<String, FrequencyCap> slotCaps = const {},
    FrequencyCap globalCap = const FrequencyCap(),
  }) => StoredFrequencyCapPolicy(
    store: store,
    slotCaps: slotCaps,
    globalCap: globalCap,
    now: () => now,
  );

  void advance(Duration d) => now = now.add(d);

  group('per-slot caps', () {
    test('uncapped slot with no global limits always shows', () async {
      final caps = policy();
      expect(await caps.canShow('interstitial'), isTrue);
      await caps.recordImpression('interstitial');
      expect(await caps.canShow('interstitial'), isTrue);
    });

    test('maxPerSession blocks after the budget, per slot', () async {
      final caps = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerSession: 2)},
      );
      await caps.recordImpression('interstitial');
      expect(await caps.canShow('interstitial'), isTrue);
      await caps.recordImpression('interstitial');
      expect(await caps.canShow('interstitial'), isFalse);
      // Other slots are unaffected.
      expect(await caps.canShow('rewarded'), isTrue);
    });

    test('minGap blocks until the gap has elapsed', () async {
      final caps = policy(
        slotCaps: {
          'interstitial': const FrequencyCap(minGap: Duration(seconds: 30)),
        },
      );
      await caps.recordImpression('interstitial');
      expect(await caps.canShow('interstitial'), isFalse);
      advance(const Duration(seconds: 29));
      expect(await caps.canShow('interstitial'), isFalse);
      advance(const Duration(seconds: 1));
      expect(await caps.canShow('interstitial'), isTrue);
    });

    test('minGap longer than the pruned history window still works', () async {
      final caps = policy(
        slotCaps: {'app_open': const FrequencyCap(minGap: Duration(hours: 4))},
      );
      await caps.recordImpression('app_open');
      advance(const Duration(hours: 2)); // history pruned by now
      expect(await caps.canShow('app_open'), isFalse);
      advance(const Duration(hours: 2));
      expect(await caps.canShow('app_open'), isTrue);
    });

    test('maxPerHour uses a rolling window', () async {
      final caps = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerHour: 2)},
      );
      await caps.recordImpression('interstitial');
      advance(const Duration(minutes: 10));
      await caps.recordImpression('interstitial');
      expect(await caps.canShow('interstitial'), isFalse);
      // 51 min after the first impression: still 2 in the window.
      advance(const Duration(minutes: 41));
      expect(await caps.canShow('interstitial'), isFalse);
      // 61 min after the first: it falls out of the window.
      advance(const Duration(minutes: 10));
      expect(await caps.canShow('interstitial'), isTrue);
    });

    test(
      'minGap survives a restart (new policy over the same store)',
      () async {
        final first = policy(
          slotCaps: {
            'interstitial': const FrequencyCap(minGap: Duration(minutes: 5)),
          },
        );
        await first.recordImpression('interstitial');

        final second = policy(
          slotCaps: {
            'interstitial': const FrequencyCap(minGap: Duration(minutes: 5)),
          },
        );
        expect(await second.canShow('interstitial'), isFalse);
        advance(const Duration(minutes: 5));
        expect(await second.canShow('interstitial'), isTrue);
      },
    );

    test('session counts do NOT survive a restart', () async {
      final first = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerSession: 1)},
      );
      await first.recordImpression('interstitial');
      expect(await first.canShow('interstitial'), isFalse);

      final second = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerSession: 1)},
      );
      expect(await second.canShow('interstitial'), isTrue);
    });
  });

  group('global cross-format cap (ADR-009)', () {
    test(
      'an interstitial impression blocks an app-open via global minGap',
      () async {
        final caps = policy(
          globalCap: const FrequencyCap(minGap: Duration(seconds: 15)),
        );
        await caps.recordImpression('interstitial');
        expect(await caps.canShow('app_open'), isFalse);
        advance(const Duration(seconds: 15));
        expect(await caps.canShow('app_open'), isTrue);
      },
    );

    test('global maxPerSession counts impressions across all slots', () async {
      final caps = policy(globalCap: const FrequencyCap(maxPerSession: 2));
      await caps.recordImpression('interstitial');
      await caps.recordImpression('rewarded');
      expect(await caps.canShow('app_open'), isFalse);
    });

    test('slot cap and global cap must BOTH allow', () async {
      final caps = policy(
        slotCaps: {
          'interstitial': const FrequencyCap(minGap: Duration(seconds: 60)),
        },
        globalCap: const FrequencyCap(minGap: Duration(seconds: 15)),
      );
      await caps.recordImpression('interstitial');
      advance(const Duration(seconds: 20)); // global OK, slot not
      expect(await caps.canShow('interstitial'), isFalse);
      expect(await caps.canShow('rewarded'), isTrue); // only global applies
    });
  });

  group('a broken device clock must not permanently block every ad', () {
    // Routine on this package's target population: cheap Android handsets with
    // a dead RTC boot to a garbage date and only correct once NTP lands (which
    // on a weak network can be minutes AFTER the app launched), and users of
    // ad-supported games routinely set the clock forward to skip cooldowns.
    // A persisted FUTURE-dated impression makes `now - last` negative, which
    // is always < minGap — so every full-screen ad was blocked forever, across
    // restarts, with no way to recover short of clearing app data.

    test('a future-dated minGap timestamp does not block forever', () async {
      final beforeRollback = policy(
        slotCaps: {
          'interstitial': const FrequencyCap(minGap: Duration(minutes: 1)),
        },
      );
      // The clock reads a year ahead; one ad shows and stamps that far-future
      // timestamp into the persisted store.
      now = DateTime(2027, 7, 11, 12);
      await beforeRollback.recordImpression('interstitial');

      // NTP corrects the clock. New session, same store.
      now = DateTime(2026, 7, 11, 12);
      final afterRollback = policy(
        slotCaps: {
          'interstitial': const FrequencyCap(minGap: Duration(minutes: 1)),
        },
      );

      expect(
        await afterRollback.canShow('interstitial'),
        isTrue,
        reason: 'a timestamp in the future is garbage, not a recent '
            'impression — it must be ignored, not treated as "0 seconds ago"',
      );
    });

    test('future-dated history does not exhaust maxPerHour forever', () async {
      final beforeRollback = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerHour: 2)},
      );
      now = DateTime(2027, 7, 11, 12);
      await beforeRollback.recordImpression('interstitial');
      await beforeRollback.recordImpression('interstitial');

      now = DateTime(2026, 7, 11, 12);
      final afterRollback = policy(
        slotCaps: {'interstitial': const FrequencyCap(maxPerHour: 2)},
      );

      expect(
        await afterRollback.canShow('interstitial'),
        isTrue,
        reason: 'future timestamps must not count toward the rolling hour',
      );
    });

    test('the global cap recovers too (it blocks EVERY format)', () async {
      final beforeRollback = policy(
        globalCap: const FrequencyCap(minGap: Duration(minutes: 1)),
      );
      now = DateTime(2027, 7, 11, 12);
      await beforeRollback.recordImpression('interstitial');

      now = DateTime(2026, 7, 11, 12);
      final afterRollback = policy(
        globalCap: const FrequencyCap(minGap: Duration(minutes: 1)),
      );

      expect(await afterRollback.canShow('rewarded'), isTrue);
      expect(await afterRollback.canShow('app_open'), isTrue);
    });

    test('a normal past timestamp still enforces minGap', () async {
      final caps = policy(
        slotCaps: {
          'interstitial': const FrequencyCap(minGap: Duration(minutes: 1)),
        },
      );
      await caps.recordImpression('interstitial');
      advance(const Duration(seconds: 30));
      expect(
        await caps.canShow('interstitial'),
        isFalse,
        reason: 'the rollback guard must not weaken normal capping',
      );
    });
  });
}
