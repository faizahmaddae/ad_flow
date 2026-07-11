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
}
