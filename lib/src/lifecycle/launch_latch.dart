/// Process-scoped one-shot cold-launch latch backing
/// `AppOpenAdManager.showAtLaunchIfReady`.
///
/// INTERNAL — this file is deliberately NOT exported from
/// `package:ad_flow/ad_flow.dart`, so none of these members are part of the
/// production public API. Tests reset the latch through
/// `package:ad_flow/ad_flow_testing.dart`'s `resetAppOpenLaunchOpportunity()`.
///
/// The cold launch of a process is a single moment, and the latch must survive
/// `AdFlow` reinitialization within a process (a second `initialize()` must not
/// mint a second launch show), which cannot be expressed as injected instance
/// state — so it is a `static` (invariant 9's second sanctioned exception,
/// allow-listed in `no_global_state_test`).
abstract final class LaunchLatch {
  static bool _consumed = false;

  /// Consumes the one-shot; returns true iff it was still available.
  static bool consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }

  /// Test-only: restore the one-shot. Reached via `ad_flow_testing.dart`.
  static void reset() => _consumed = false;
}
