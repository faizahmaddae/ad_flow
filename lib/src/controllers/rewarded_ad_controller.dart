import '../config/ad_flow_config.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Preloads and shows rewarded ads.
///
/// Pass `onReward` to `show(...)` to grant the reward — the base engine
/// guarantees it fires at most once per ad. Configure
/// [RewardedConfig.ssv] for server-side verification of high-value rewards.
class RewardedAdController extends FullScreenAdControllerBase {
  /// Creates the rewarded controller.
  RewardedAdController({
    required super.sdk,
    required super.gate,
    required super.caps,
    required super.coordinator,
    required RewardedConfig config,
    required super.adUnitId,
    super.retry,
    super.onPaid,
    super.onBlocked,
  }) : _config = config,
       super(slot: slotName);

  /// The gate/cap slot name for rewarded ads.
  static const slotName = 'rewarded';

  final RewardedConfig _config;

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadRewarded(adUnitId, const AdRequestOptions(), ssv: _config.ssv);
}
