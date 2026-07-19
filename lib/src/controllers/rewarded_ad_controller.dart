import '../config/ad_flow_config.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';
import 'runtime_ssv.dart';

/// Preloads and shows rewarded ads.
///
/// Pass `onReward` to `show(...)` to grant the reward — the base engine
/// guarantees it fires at most once per ad. Configure
/// [RewardedConfig.ssv] for server-side verification of high-value rewards.
///
/// [setServerSideVerification] applies a runtime SSV override to the warm ad
/// and every future load, with the in-flight and failure guarantees the
/// [RuntimeSsvController] mixin documents.
class RewardedAdController extends FullScreenAdControllerBase
    with RuntimeSsvController {
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
    super.now,
  }) : _config = config,
       super(slot: slotName, maxAdAge: config.maxAdAge);

  /// The gate/cap slot name for rewarded ads.
  static const slotName = 'rewarded';

  final RewardedConfig _config;

  @override
  ServerSideVerification? get configuredSsv => _config.ssv;

  @override
  Future<void> attachSsv(
    FullScreenAdHandle handle,
    ServerSideVerification ssv,
  ) async {
    if (handle is RewardedHandle) {
      await handle.updateServerSideVerification(ssv);
    }
  }

  /// Shows the warm rewarded ad; [onReward] fires (at most once) when the
  /// user earns the reward.
  @override
  Future<bool> show({OnUserEarnedReward? onReward}) =>
      showEngine(onReward: onReward);

  @override
  Future<FullScreenAdHandle> loadHandle() =>
      sdk.loadRewarded(adUnitId, _config.request, ssv: effectiveSsv);
}
