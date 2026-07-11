import 'frequency_cap_policy.dart';
import 'full_screen_ad_coordinator.dart';

/// The composed check every controller runs before loading.
///
/// - [canLoad]: consent gate open AND ads enabled (Remove-Ads off).
///   Guards invariant 1 — no `load()` before consent.
/// - [canShow]: [canLoad] AND the slot's frequency caps allow it AND no
///   other full-screen ad is currently visible. **Not used on the actual
///   show path** — see its own doc for why.
class AdGate {
  /// Creates a gate.
  ///
  /// [canRequestAds] is the *cheap, current* consent answer (wire it to
  /// `AdSdk.canRequestAds`) — it must NOT re-run the consent flow.
  /// [isEnabled] reflects the app's Remove-Ads state.
  AdGate({
    required Future<bool> Function() canRequestAds,
    required bool Function() isEnabled,
    required FrequencyCapPolicy caps,
    required FullScreenAdCoordinator coordinator,
  }) : _canRequestAds = canRequestAds,
       _isEnabled = isEnabled,
       _caps = caps,
       _coordinator = coordinator;

  final Future<bool> Function() _canRequestAds;
  final bool Function() _isEnabled;
  final FrequencyCapPolicy _caps;
  final FullScreenAdCoordinator _coordinator;

  /// Whether [slot] may load an ad now.
  Future<bool> canLoad(String slot) async {
    if (!_isEnabled()) return false;
    return _canRequestAds();
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
