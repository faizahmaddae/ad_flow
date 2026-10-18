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
  ///
  /// Holds for any [attempt], however large: the gate re-check's counter
  /// grows for as long as the gate stays closed (see [gateRecheckDelay]).
  Duration nextDelay(int attempt) {
    assert(attempt >= 1, 'nextDelay is defined for attempt >= 1');
    // In double, with the exponent clamped. In `int` the product overflowed
    // (from attempt 52 with the default 5 s base) and wrapped to zero or
    // below, which the clamp further down turned into a 0 ms delay. Clamping
    // at 63 changes nothing else: 2^63 ms is longer than any Duration.
    final doublings = math.min(attempt - 1, 63);
    final base = _config.baseDelay.inMilliseconds * math.pow(2.0, doublings);
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
  ///
  /// Never shorter than one second, whatever the config says (ADR-077). The
  /// re-arm resets the attempts and loads again, for as long as loads keep
  /// failing, and each turn is a real SDK load request. `AdFlowConfig.validate`
  /// rejects only a negative cooldown, so with a zero one and nothing to wait
  /// between the attempts (`maxAttempts` 0 or 1, or a [nextDelay] of 0 ms)
  /// every turn would run on a zero-delay timer: a busy loop. The retries
  /// between attempts keep the configured delays: they stop at `maxAttempts`.
  Duration get cooldown {
    final cooldown = _config.cooldown;
    return cooldown < _minCooldown ? _minCooldown : cooldown;
  }

  /// The shortest [cooldown]: far below the default (5 minutes), so no
  /// default schedule moves.
  static const _minCooldown = Duration(seconds: 1);

  /// The per-load watchdog bound (null = disabled) — see
  /// [RetryConfig.loadTimeout].
  Duration? get loadTimeout => _config.loadTimeout;

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
  /// settles into a cheap once-a-minute check rather than spinning. The
  /// controllers reset [attempt] only on a successful load, so it keeps
  /// growing while the gate stays shut — hours of re-checks still get
  /// [RetryConfig.maxDelay], never a zero delay.
  ///
  /// Never shorter than one second, whatever the config says (ADR-076).
  /// [nextDelay] reads `baseDelay` and `maxDelay` in whole milliseconds, so
  /// either one under 1 ms makes every delay 0 ms, and validation does not
  /// stop that: `AdFlowConfig.validate` rejects a zero `baseDelay`, not a
  /// sub-millisecond one, and a policy handed to a controller directly is
  /// never validated. A failure retry may run that fast (it stops at
  /// `maxAttempts`); this re-check may not, because it runs for as long as
  /// the gate stays shut, and on a zero-delay timer it is a busy loop.
  Duration gateRecheckDelay(int attempt) {
    final delay = nextDelay(attempt);
    return delay < _minGateRecheckDelay ? _minGateRecheckDelay : delay;
  }

  /// The shortest [gateRecheckDelay]: below the default `baseDelay` (5 s),
  /// so no default schedule moves.
  static const _minGateRecheckDelay = Duration(seconds: 1);
}
