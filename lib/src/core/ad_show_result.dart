import 'package:flutter/foundation.dart';

import '../seam/ad_sdk_types.dart';
import 'ad_block_reason.dart';
import 'ad_flow_error.dart';

/// What happened to a full-screen `show()` call (6.0).
///
/// `show()` completes when the ad has **closed** — code after
/// `await ads.interstitial?.show()` runs once the user is back in the app — or
/// at once when nothing was shown:
///
/// ```dart
/// final result = await ads.interstitial?.show();
/// // the next level starts here, after the ad
///
/// final reward = (await ads.rewarded?.show())?.reward;
/// if (reward != null) grantCoins(reward.amount);
/// ```
@immutable
class AdShowResult {
  /// The ad reached the screen and has closed. [reward] is set when the user
  /// of a rewarded format earned the reward.
  const AdShowResult.shown({this.reward}) : blockReason = null, error = null;

  /// Nothing was shown: the show was refused for [blockReason] — no ad ready
  /// yet, a frequency cap, consent, Remove-Ads, the rewarded intro skipped…
  /// Most reasons are normal (see [AdBlockReason]).
  const AdShowResult.blocked(AdBlockReason this.blockReason)
    : reward = null,
      error = null;

  /// The SDK could not show the ad.
  const AdShowResult.failed(AdFlowError this.error)
    : reward = null,
      blockReason = null;

  /// The reward the user earned, for a rewarded format; null otherwise.
  final RewardEarned? reward;

  /// Why nothing was shown, for a refused show; null otherwise.
  final AdBlockReason? blockReason;

  /// What went wrong, for a show the SDK failed; null otherwise.
  final AdFlowError? error;

  /// Whether the ad reached the screen.
  bool get shown => blockReason == null && error == null;

  @override
  bool operator ==(Object other) =>
      other is AdShowResult &&
      other.reward == reward &&
      other.blockReason == blockReason &&
      other.error == error;

  @override
  int get hashCode => Object.hash(reward, blockReason, error);

  @override
  String toString() => shown
      ? 'AdShowResult.shown(reward: $reward)'
      : blockReason != null
      ? 'AdShowResult.blocked(${blockReason!.name})'
      : 'AdShowResult.failed($error)';
}
