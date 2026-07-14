import 'dart:async';

import '../config/ad_flow_config.dart';
import '../core/ad_block_reason.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Presents the mandatory intro screen for a rewarded interstitial;
/// resolves to whether the user chose to continue (false = skipped).
typedef RewardedIntroPresenter =
    Future<bool> Function(RewardIntroContent content);

/// Preloads and shows rewarded interstitial ads — always behind the
/// policy-mandated intro screen (ADR-013).
///
/// `show(...)` first presents the intro (reward disclosure + skip option)
/// via the injected [RewardedIntroPresenter]; the ad plays only if the
/// user did not skip. This ordering is enforced by construction — there is
/// no code path to the ad that bypasses the intro.
class RewardedInterstitialAdController extends FullScreenAdControllerBase {
  /// Creates the rewarded interstitial controller.
  ///
  /// [showIntro] presents the intro screen; the widgets layer provides
  /// `RewardedIntroScreen.show` as the standard presenter.
  RewardedInterstitialAdController({
    required super.sdk,
    required super.gate,
    required super.caps,
    required super.coordinator,
    required RewardedInterstitialConfig config,
    required super.adUnitId,
    required RewardedIntroPresenter showIntro,
    super.retry,
    super.onPaid,
    super.onBlocked,
  }) : _config = config,
       _showIntro = showIntro,
       super(slot: slotName);

  /// The gate/cap slot name for rewarded interstitials.
  static const slotName = 'rewarded_interstitial';

  final RewardedInterstitialConfig _config;
  final RewardedIntroPresenter _showIntro;
  bool _introShowing = false;

  @override
  Future<FullScreenAdHandle> loadHandle() => sdk.loadRewardedInterstitial(
    adUnitId,
    const AdRequestOptions(),
    ssv: _config.ssv,
  );

  @override
  Future<bool> show({OnUserEarnedReward? onReward}) async {
    // Only bother the user with the intro when an ad is actually warm.
    if (!isReady) {
      noteBlocked(AdBlockReason.notReady);
      unawaited(load());
      return false;
    }
    if (_introShowing) return false;
    _introShowing = true;
    try {
      final proceed = await _showIntro(_config.intro);
      if (!proceed) {
        // Skipped — policy working as intended, not a fault.
        noteBlocked(AdBlockReason.introSkipped);
        return false;
      }
    } finally {
      _introShowing = false;
    }
    return super.show(onReward: onReward);
  }
}
