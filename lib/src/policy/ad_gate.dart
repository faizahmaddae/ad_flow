import 'frequency_cap_policy.dart';
import 'full_screen_ad_coordinator.dart';

/// The composed check every controller runs before loading.
///
/// - [canLoad]: request configuration applied AND consent gate open AND ads
///   enabled (Remove-Ads off). Guards invariant 1 — no `load()` before
///   consent — and the config-before-load ordering (review-fix #5 / ADR-028).
/// - [canShow]: [canLoad] AND the slot's frequency caps allow it AND no
///   other full-screen ad is currently visible. **Not used on the actual
///   show path** — see its own doc for why.
class AdGate {
  /// Creates a gate.
  ///
  /// [canRequestAds] is the *cheap, current* consent answer (wire it to
  /// `AdSdk.canRequestAds`) — it must NOT re-run the consent flow.
  /// [isEnabled] reflects the app's Remove-Ads state.
  /// [configReady] completes once `updateRequestConfiguration` has been
  /// applied; [canLoad] awaits it so no ad request (preloaded OR on-demand)
  /// can go out before test-device / COPPA / content-rating settings are set
  /// — critical now that startup runs in the background (ADR-032/ADR-033).
  /// It is bounded by the facade's init timeout, so it never hangs. Omit it
  /// (the default is an already-complete future) when config timing is not
  /// under test.
  AdGate({
    required Future<bool> Function() canRequestAds,
    required bool Function() isEnabled,
    required FrequencyCapPolicy caps,
    required FullScreenAdCoordinator coordinator,
    Future<void>? configReady,
    Future<void> Function()? settleConsent,
  }) : _canRequestAds = canRequestAds,
       _isEnabled = isEnabled,
       _caps = caps,
       _coordinator = coordinator,
       _configReady = configReady ?? Future<void>.value(),
       _settleConsent = settleConsent;

  final Future<bool> Function() _canRequestAds;
  final bool Function() _isEnabled;
  final FrequencyCapPolicy _caps;
  final FullScreenAdCoordinator _coordinator;
  final Future<void> _configReady;
  final Future<void> Function()? _settleConsent;

  /// Whether [slot] may load an ad now.
  Future<bool> canLoad(String slot) async {
    if (!_isEnabled()) return false;
    // Never request an ad before request configuration is applied — an
    // on-demand banner/native mounted on the first frame (ADR-032) can reach
    // here while the background init/config is still in flight; loading now
    // would send an untagged/untest-flagged first request (review-fix #5).
    await _configReady;
    // Then wait for the consent flow to actually SETTLE, rather than reading a
    // still-false canRequestAds() and failing fast.
    //
    // This closes the gap ADR-032 opened. Startup is non-blocking, so the app
    // renders and mounts its banner/native on the first frame — but the config
    // gate above (SDK init, no user interaction, ~1s) always opens well BEFORE
    // consent (a network-bound info update, and possibly an ATT prompt and a
    // GDPR form the user must read). So a first-frame view ad used to arrive
    // here, get a hard `false`, go idle and re-arm only after RetryConfig's
    // 5-minute cooldown — leaving every new install with blank banner and
    // native slots for the first five minutes of its first session.
    //
    // The callback also RE-ATTEMPTS a consent flow that previously FAILED
    // (see AdFlow._settleConsent), which is what lets an offline launch start
    // serving ads once the network returns instead of staying dead all session.
    await _settleConsent?.call();
    return _isEnabled() && await _canRequestAds();
  }

  /// Whether [slot] could show a full-screen ad right now — a best-effort,
  /// **non-atomic** snapshot for informational/UI use only (e.g. graying
  /// out a "Watch Ad" button).
  ///
  /// ⚠️ Do NOT use this to decide whether to actually call `show()`. The
  /// coordinator check below is `await`-separated from any coordinator
  /// *claim*, so two callers can each observe "nothing is showing" in the
  /// same turn and both proceed — the exact double-show-across-formats
  /// race ADR-024 fixed. `FullScreenAdControllerBase.show()` does NOT
  /// call this method; it claims `FullScreenAdCoordinator.tryEnter()`
  /// synchronously as its first action instead, which is the only safe
  /// way to gate a real show. This method exists for read-only queries
  /// where a stale/racy answer is an acceptable UX nit, never a policy
  /// violation (review finding #6).
  Future<bool> canShow(String slot) async {
    if (_coordinator.isFullScreenAdVisible) return false;
    if (!await canLoad(slot)) return false;
    return _caps.canShow(slot);
  }
}
