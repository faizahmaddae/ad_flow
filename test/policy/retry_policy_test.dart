import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// random() == 0.5 makes the jitter multiplier exactly 1.0.
  RetryPolicy noJitter(RetryConfig config) =>
      RetryPolicy(config, random: () => 0.5);

  group('shouldRetry', () {
    test('allows retries below maxAttempts, stops at the budget', () {
      final policy = noJitter(const RetryConfig(maxAttempts: 3));
      expect(policy.shouldRetry(1), isTrue);
      expect(policy.shouldRetry(2), isTrue);
      expect(policy.shouldRetry(3), isFalse);
    });

    test('maxAttempts 0 disables retries', () {
      final policy = noJitter(const RetryConfig(maxAttempts: 0));
      expect(policy.shouldRetry(1), isFalse);
    });
  });

  group('nextDelay', () {
    test('doubles per attempt from baseDelay (jitter neutral)', () {
      final policy = noJitter(
        const RetryConfig(
          baseDelay: Duration(seconds: 5),
          maxDelay: Duration(minutes: 5),
        ),
      );
      expect(policy.nextDelay(1), const Duration(seconds: 5));
      expect(policy.nextDelay(2), const Duration(seconds: 10));
      expect(policy.nextDelay(3), const Duration(seconds: 20));
      expect(policy.nextDelay(4), const Duration(seconds: 40));
    });

    test('caps at maxDelay', () {
      final policy = noJitter(
        const RetryConfig(
          baseDelay: Duration(seconds: 5),
          maxDelay: Duration(seconds: 12),
        ),
      );
      expect(policy.nextDelay(1), const Duration(seconds: 5));
      expect(policy.nextDelay(2), const Duration(seconds: 10));
      expect(policy.nextDelay(3), const Duration(seconds: 12));
      expect(policy.nextDelay(10), const Duration(seconds: 12));
    });

    test('jitter spreads delays within ±jitterFactor', () {
      const config = RetryConfig(
        baseDelay: Duration(seconds: 10),
        maxDelay: Duration(minutes: 5),
        jitterFactor: 0.25,
      );
      final low = RetryPolicy(config, random: () => 0.0).nextDelay(1);
      final high = RetryPolicy(config, random: () => 0.999999).nextDelay(1);

      expect(low, const Duration(milliseconds: 7500)); // 10s * 0.75
      expect(
        high.inMilliseconds,
        closeTo(12500, 10), // 10s * ~1.25
      );
      expect(low, isNot(equals(high)));
    });

    test('jittered delay never exceeds maxDelay and never goes negative', () {
      const config = RetryConfig(
        baseDelay: Duration(seconds: 50),
        maxDelay: Duration(seconds: 60),
        jitterFactor: 1.0,
      );
      final high = RetryPolicy(config, random: () => 0.999999).nextDelay(4);
      final low = RetryPolicy(config, random: () => 0.0).nextDelay(1);
      expect(high, lessThanOrEqualTo(const Duration(seconds: 60)));
      expect(low, greaterThanOrEqualTo(Duration.zero));
    });

    test('successive real-random delays vary (lockstep guard)', () {
      final policy = RetryPolicy(const RetryConfig(jitterFactor: 0.25));
      final delays = {for (var i = 0; i < 8; i++) policy.nextDelay(1)};
      expect(delays.length, greaterThan(1));
    });
  });

  test('cooldown passes through from config', () {
    final policy = noJitter(const RetryConfig(cooldown: Duration(minutes: 7)));
    expect(policy.cooldown, const Duration(minutes: 7));
  });

  test('gateRecheckDelay backs off exponentially and caps at maxDelay, '
      'NEVER at the failure cooldown (ADR-035 — the 5-minute cooldown here '
      'is what blanked first-frame banners for five minutes)', () {
    final policy = noJitter(
      const RetryConfig(
        baseDelay: Duration(seconds: 5),
        maxDelay: Duration(minutes: 1),
        cooldown: Duration(minutes: 5),
      ),
    );
    expect(policy.gateRecheckDelay(1), const Duration(seconds: 5));
    expect(policy.gateRecheckDelay(2), const Duration(seconds: 10));
    expect(policy.gateRecheckDelay(3), const Duration(seconds: 20));
    expect(policy.gateRecheckDelay(4), const Duration(seconds: 40));
    expect(policy.gateRecheckDelay(5), const Duration(minutes: 1));
    // A permanently closed gate (Remove-Ads, declined consent) settles into
    // a cheap once-a-minute check — never the 5-minute failure cooldown.
    expect(policy.gateRecheckDelay(50), const Duration(minutes: 1));
  });

  group('large attempt counts never wrap to a zero delay', () {
    // `baseDelay * 2^(attempt - 1)` used to be computed in `int`, which
    // overflows. With the defaults it gave gateRecheckDelay(51) = 60 s,
    // (52) = 0, (53) = 60 s, (55) = 0, and 0 for every attempt from 62 on: a
    // gate closed for about an hour (Remove-Ads bought, consent declined) was
    // then re-checked on a zero-delay timer, over and over.
    const config = RetryConfig(); // 5 s base, 1 min cap, ±25% jitter
    const attempts = [52, 53, 55, 61, 62, 64, 100, 10000, 1000000];

    test('stay at maxDelay once capped (jitter neutral)', () {
      final policy = noJitter(config);
      for (final attempt in attempts) {
        expect(
          policy.nextDelay(attempt),
          config.maxDelay,
          reason: 'nextDelay($attempt)',
        );
        expect(
          policy.gateRecheckDelay(attempt),
          config.maxDelay,
          reason: 'gateRecheckDelay($attempt)',
        );
      }
    });

    test('stay within [maxDelay * (1 - jitter), maxDelay] at the jitter '
        'extremes', () {
      final low = RetryPolicy(config, random: () => 0.0);
      final high = RetryPolicy(config, random: () => 0.999999);
      for (final attempt in attempts) {
        expect(
          low.nextDelay(attempt),
          const Duration(seconds: 45), // 60 s * 0.75
          reason: 'low nextDelay($attempt)',
        );
        expect(
          low.gateRecheckDelay(attempt),
          const Duration(seconds: 45),
          reason: 'low gateRecheckDelay($attempt)',
        );
        expect(
          high.nextDelay(attempt),
          config.maxDelay, // 60 s * ~1.25, clamped
          reason: 'high nextDelay($attempt)',
        );
        expect(
          high.gateRecheckDelay(attempt),
          config.maxDelay,
          reason: 'high gateRecheckDelay($attempt)',
        );
      }
    });

    test('never shrink as attempts grow, 1 to 10000 (jitter neutral)', () {
      final policy = noJitter(config);
      var previous = Duration.zero;
      for (var attempt = 1; attempt <= 10000; attempt++) {
        final delay = policy.gateRecheckDelay(attempt);
        expect(
          delay,
          greaterThanOrEqualTo(previous),
          reason: 'gateRecheckDelay($attempt) after $previous',
        );
        previous = delay;
      }
      expect(previous, config.maxDelay);
    });

    test('a long baseDelay cannot overflow the product either', () {
      // 1 day = 86,400,000 ms: in `int` the product overflowed from attempt
      // 38, no matter how the power itself was computed.
      final policy = noJitter(
        const RetryConfig(
          baseDelay: Duration(days: 1),
          maxDelay: Duration(days: 7),
        ),
      );
      expect(policy.nextDelay(1), const Duration(days: 1));
      expect(policy.nextDelay(3), const Duration(days: 4));
      for (final attempt in [38, 40, ...attempts]) {
        expect(
          policy.nextDelay(attempt),
          const Duration(days: 7),
          reason: 'nextDelay($attempt)',
        );
      }
    });
  });

  group('a closed gate is re-checked at most once a second (ADR-076)', () {
    // nextDelay reads baseDelay and maxDelay in whole milliseconds, so a base
    // or a cap under 1 ms makes every delay 0 ms. Failure retries stop at
    // maxAttempts, but the gate re-check's counter grows for as long as the
    // gate stays closed, so a 0 ms gate re-check was a busy loop.
    // AdFlowConfig.validate() rejects a zero baseDelay, not a sub-millisecond
    // one, and a hand-built RetryPolicy is never validated at all.
    const second = Duration(seconds: 1);
    const configs = {
      'zero base and cap': RetryConfig(
        baseDelay: Duration.zero,
        maxDelay: Duration.zero,
      ),
      'sub-millisecond base and cap': RetryConfig(
        baseDelay: Duration(microseconds: 500),
        maxDelay: Duration(microseconds: 500),
      ),
      'zero base, default cap': RetryConfig(baseDelay: Duration.zero),
      'default base, zero cap': RetryConfig(maxDelay: Duration.zero),
      '1 ms base and cap': RetryConfig(
        baseDelay: Duration(milliseconds: 1),
        maxDelay: Duration(milliseconds: 1),
      ),
    };

    test('gateRecheckDelay is 1 s when the configured delays are all '
        'shorter, at any attempt and any jitter', () {
      for (final MapEntry(key: name, value: config) in configs.entries) {
        for (final r in [0.0, 0.5, 0.999999]) {
          final policy = RetryPolicy(config, random: () => r);
          for (final attempt in [1, 2, 10, 52, 61, 1000000]) {
            expect(
              policy.gateRecheckDelay(attempt),
              second,
              reason: '$name, random() = $r, gateRecheckDelay($attempt)',
            );
          }
        }
      }
    });

    test('delays of 1 s or more are unchanged, shorter ones become 1 s, and '
        'failure retries keep the configured delays', () {
      final policy = noJitter(
        const RetryConfig(
          baseDelay: Duration(milliseconds: 250),
          maxDelay: Duration(seconds: 4),
        ),
      );
      const attempts = [1, 2, 3, 4, 5, 6];
      expect(
        [for (final attempt in attempts) policy.gateRecheckDelay(attempt)],
        const [
          second,
          second,
          second,
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 4),
        ],
      );
      expect(
        [for (final attempt in attempts) policy.nextDelay(attempt)],
        const [
          Duration(milliseconds: 250),
          Duration(milliseconds: 500),
          second,
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 4),
        ],
      );
    });

    test('the floor applies after the jitter', () {
      // A 1 s base at the low jitter extreme (±25%) is 750 ms.
      final low = RetryPolicy(
        const RetryConfig(baseDelay: Duration(seconds: 1)),
        random: () => 0.0,
      );
      expect(low.nextDelay(1), const Duration(milliseconds: 750));
      expect(low.gateRecheckDelay(1), second);
    });
  });
}
