import 'frequency_cap_policy.dart';
import 'full_screen_ad_coordinator.dart';

/// The composed check every controller runs before loading AND showing.
///
/// - [canLoad]: consent gate open AND ads enabled (Remove-Ads off).
///   Guards invariant 1 — no `load()` before consent.
/// - [canShow]: [canLoad] AND the slot's frequency caps allow it AND no
///   other full-screen ad is currently visible.
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

  /// Whether [slot] may show a full-screen ad now.
  Future<bool> canShow(String slot) async {
    if (_coordinator.isFullScreenAdVisible) return false;
    if (!await canLoad(slot)) return false;
    return _caps.canShow(slot);
  }
}
