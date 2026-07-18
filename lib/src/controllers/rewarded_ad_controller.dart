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
    super.now,
  }) : _config = config,
       super(slot: slotName, maxAdAge: config.maxAdAge);

  /// The gate/cap slot name for rewarded ads.
  static const slotName = 'rewarded';

  final RewardedConfig _config;
  ServerSideVerification? _ssvOverride;

  /// Applies [ssv] to the currently warm ad AND every future load,
  /// replacing [RewardedConfig.ssv] (2026-07 audit).
  ///
  /// Config-time SSV is frozen at startup, but real apps learn the SSV
  /// `userId` at login and the per-show `customData` (which mission earned
  /// the reward) moments before `show()`. Call this any time; rethrows an
  /// `AdFlowError` if attaching to the warm ad fails — a caller granting
  /// high-value rewards must know its verification payload did not attach.
  Future<void> setServerSideVerification(ServerSideVerification ssv) async {
    _ssvOverride = ssv;
    final handle = currentHandle;
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
  Future<FullScreenAdHandle> loadHandle() => sdk.loadRewarded(
    adUnitId,
    _config.request,
    ssv: _ssvOverride ?? _config.ssv,
  );
}
