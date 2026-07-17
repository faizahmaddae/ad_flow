import '../config/ad_flow_config.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Preloads and shows interstitial ads at natural breaks.
///
/// Policy guardrails on top of the shared full-screen engine:
/// - frequency caps (per-slot + global) via the gate;
/// - optional user-action pacing: report natural-break actions with
///   [recordUserAction]; once the app starts reporting, an interstitial
///   shows only after [InterstitialConfig.minActionsBetween] actions since
///   the last one (AdMob guidance: at most one ad per two user actions).
///   Apps that never call [recordUserAction] are paced by caps alone.
class InterstitialAdController extends FullScreenAdControllerBase {
  /// Creates the interstitial controller.
  InterstitialAdController({
    required super.sdk,
    required super.gate,
    required super.caps,
    required super.coordinator,
    required InterstitialConfig config,
    required super.adUnitId,
    super.retry,
    super.onPaid,
    super.onBlocked,
    super.now,
  }) : _config = config,
       super(slot: slotName, maxAdAge: config.maxAdAge);

  /// The gate/cap slot name for interstitials.
  static const slotName = 'interstitial';

  final InterstitialConfig _config;

  bool _actionTrackingActive = false;
  int _actionsSinceLastShow = 0;

  /// Reports one user action (a natural transition: level end, screen
  /// change, task completed). Activates action pacing on first call.
  void recordUserAction() {
    _actionTrackingActive = true;
    _actionsSinceLastShow++;
  }

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadInterstitial(adUnitId, const AdRequestOptions());

  @override
  bool canShowExtra() =>
      !_actionTrackingActive ||
      _actionsSinceLastShow >= _config.minActionsBetween;

  @override
  void onShown() => _actionsSinceLastShow = 0;
}
