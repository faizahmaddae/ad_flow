import 'dart:math' as math;

import '../config/ad_flow_config.dart';

/// Exponential backoff with jitter, a max attempt count and a cooldown
/// (ADR-008). Pure math — the controllers own the timers.
///
/// Semantics: `attempt` is the number of failures so far (1-based after the
/// first failure). While [shouldRetry] is true, wait [nextDelay] and try
/// again; once it turns false, wait [cooldown], reset the attempt counter,
/// and auto re-arm.
class RetryPolicy {
  /// Creates a policy from a [RetryConfig]. [random] (returning values in
  /// the half-open range 0 to 1) is injectable for deterministic tests.
  RetryPolicy(this._config, {double Function()? random})
    : _random = random ?? math.Random().nextDouble;

  final RetryConfig _config;
  final double Function() _random;

  /// Whether another retry is allowed after [attempt] failures.
  ///
  /// With `maxAttempts: 3`: fail #1 → retry, fail #2 → retry, fail #3 →
  /// false (3 total attempts, matching v1's documented behavior).
  /// `maxAttempts: 0` disables retries entirely.
  bool shouldRetry(int attempt) => attempt < _config.maxAttempts;

  /// The backoff delay after [attempt] failures (1-based): `baseDelay *
  /// 2^(attempt-1)`, jittered by ±`jitterFactor`, capped at `maxDelay`.
  Duration nextDelay(int attempt) {
    assert(attempt >= 1, 'nextDelay is defined for attempt >= 1');
    final base = _config.baseDelay.inMilliseconds * math.pow(2, attempt - 1);
    final capped = math.min(base, _config.maxDelay.inMilliseconds.toDouble());
    // random() in [0,1) → jitter multiplier in [1-j, 1+j).
    final jittered = capped * (1 + _config.jitterFactor * (2 * _random() - 1));
    final millis = jittered
        .clamp(0, _config.maxDelay.inMilliseconds.toDouble())
        .round();
    return Duration(milliseconds: millis);
  }

  /// How long to back off after the attempt budget is exhausted, before
  /// auto re-arming.
  Duration get cooldown => _config.cooldown;

  /// How long to wait before re-checking a gate that was CLOSED (consent not
  /// settled yet, or ads disabled) — as opposed to a load that FAILED.
  ///
  /// This is a different question from [nextDelay]: a closed gate is not an
  /// error, it is a "not yet", and the common case (consent resolving a second
  /// or two after the first frame) wants a prompt re-check. Re-using
  /// [cooldown] here — 5 minutes by default — is what left first-frame banner
  /// and native slots blank for the first five minutes of every new install.
  ///
  /// Backs off exponentially from [RetryConfig.baseDelay] and caps at
  /// [RetryConfig.maxDelay] (never at the far longer [cooldown]), so a
  /// permanently closed gate (the user bought Remove-Ads, or declined consent)
  /// settles into a cheap once-a-minute check rather than spinning.
  Duration gateRecheckDelay(int attempt) => nextDelay(attempt);
}
