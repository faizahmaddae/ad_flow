import 'dart:async';

import '../config/ad_flow_config.dart';
import '../core/ad_block_reason.dart';
import '../core/ad_load_state.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';
import 'runtime_ssv.dart';

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
class RewardedInterstitialAdController extends FullScreenAdControllerBase
    with RuntimeSsvController {
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
    super.now,
  }) : _config = config,
       _showIntro = showIntro,
       super(slot: slotName, maxAdAge: config.maxAdAge);

  /// The gate/cap slot name for rewarded interstitials.
  static const slotName = 'rewarded_interstitial';

  final RewardedInterstitialConfig _config;
  final RewardedIntroPresenter _showIntro;

  @override
  ServerSideVerification? get configuredSsv => _config.ssv;

  @override
  Future<void> attachSsv(
    FullScreenAdHandle handle,
    ServerSideVerification ssv,
  ) async {
    if (handle is RewardedInterstitialHandle) {
      await handle.updateServerSideVerification(ssv);
    }
  }

  @override
  Future<FullScreenAdHandle> loadHandle() => sdk.loadRewardedInterstitial(
    adUnitId,
    _config.request,
    ssv: effectiveSsv,
  );

  /// Shows the mandatory intro, then the ad — as ONE atomic reservation
  /// (4.0 audit).
  ///
  /// The base engine runs every policy check (consent, per-slot AND global
  /// frequency caps, expiry, coordinator) BEFORE the intro is presented, and
  /// holds the full-screen claim through it. Two failure modes this removes:
  /// a user who accepted the intro could still be refused by a check that
  /// only ran afterwards ("no ad, no reward, no explanation"), and a warm
  /// return during the intro could stack an app-open ad over it.
  @override
  Future<bool> show({OnUserEarnedReward? onReward}) async {
    // Re-entrant show while the sequence (intro or ad) is on screen: the
    // engine's AdShowing guard would reject anyway, but bail here so the
    // notReady branch below cannot misreport it.
    if (state.value is AdShowing) return false;
    // Only bother the user with the intro when an ad is actually warm.
    if (!isReady) {
      noteBlocked(AdBlockReason.notReady);
      unawaited(load());
      return false;
    }
    return showEngine(onReward: onReward, confirm: _presentIntro);
  }

  /// The engine's confirm hook: presents the intro; false = skipped.
  Future<bool> _presentIntro() async {
    final proceed = await _showIntro(_config.intro);
    if (!proceed) {
      // Skipped — policy working as intended, not a fault.
      noteBlocked(AdBlockReason.introSkipped);
    }
    return proceed;
  }
}
