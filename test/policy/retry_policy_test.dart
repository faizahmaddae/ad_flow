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
      final policy = RetryPolicy(
        const RetryConfig(jitterFactor: 0.25),
      );
      final delays = {for (var i = 0; i < 8; i++) policy.nextDelay(1)};
      expect(delays.length, greaterThan(1));
    });
  });

  test('cooldown passes through from config', () {
    final policy = noJitter(
      const RetryConfig(cooldown: Duration(minutes: 7)),
    );
    expect(policy.cooldown, const Duration(minutes: 7));
  });
}
