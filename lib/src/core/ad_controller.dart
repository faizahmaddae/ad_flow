import 'package:flutter/foundation.dart';

import 'ad_load_state.dart';
import 'ad_show_result.dart';

/// Common surface of every ad controller.
abstract interface class AdController {
  /// Reactive load state (subscribe with `ValueListenableBuilder`).
  ValueListenable<AdLoadState> get state;

  /// Loads an ad if the gate allows and none is loaded/loading.
  Future<void> load();

  /// Re-evaluates this slot against the current gate, right now, and repairs a
  /// live/warm ad that no longer matches it.
  ///
  /// Two things can make a mounted or warm ad wrong:
  /// - **Permission went away** (Remove-Ads bought, consent withdrawn, the
  ///   owning `AdFlow` disposed) — the ad is dropped. An idle slot that is
  ///   newly permitted starts a load.
  /// - **Consent changed** (a consent / privacy-options mutation bumps the
  ///   internal consent generation) — an ad requested under the old consent is
  ///   privacy-stale even though showing it makes no new request: its
  ///   impression and measurement still reflect the old choice. So a warm
  ///   full-screen ad, or a visible banner/native ad, is DROPPED and reloaded
  ///   through the fresh gate. A full-screen ad already ON SCREEN is
  ///   NOT interrupted — its impression already happened — but the next one it
  ///   preloads on dismissal goes through the fresh gate.
  ///
  /// `AdFlow` calls this on every controller after `disableAds`/`enableAds`,
  /// after any consent mutation, and on `dispose()`. Apps normally never need
  /// to call it, but it is safe to call at any time (2026-07 audit).
  Future<void> recheckGate();

  /// Cancels timers, disposes the current handle and stops the controller.
  void dispose();
}

/// Controllers for full-screen formats (interstitial, rewarded, rewarded
/// interstitial, app open).
abstract interface class FullScreenAdController implements AdController {
  /// Checks the gate, shows the warm ad, records the impression and
  /// preloads the next one on dismissal.
  ///
  /// Completes when the ad has CLOSED (6.0) — code after `await show()` runs
  /// once the user is back in the app — or at once when nothing was shown.
  /// The [AdShowResult] says which, and why.
  ///
  /// The reward callback lives only on the rewarded formats
  /// (`RewardedAdController.show(onReward:)` /
  /// `RewardedInterstitialAdController.show(onReward:)`); their result also
  /// carries the reward.
  Future<AdShowResult> show();

  /// Whether [show] would show an ad right now — a synchronous hint for UI
  /// (6.0). [show] re-checks everything and remains the authority.
  bool get canShow;
}
