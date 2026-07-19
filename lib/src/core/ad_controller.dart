import 'package:flutter/foundation.dart';

import 'ad_load_state.dart';

/// Common surface of every ad controller.
abstract interface class AdController {
  /// Reactive load state (subscribe with `ValueListenableBuilder`).
  ValueListenable<AdLoadState> get state;

  /// Loads an ad if the gate allows and none is loaded/loading.
  Future<void> load();

  /// Re-evaluates whether this slot's ad is still PERMITTED, right now.
  ///
  /// Drops a live/warm ad whose permission has gone away (Remove-Ads bought,
  /// consent withdrawn, the owning `AdFlow` disposed) and kicks a load when
  /// the slot is idle and newly permitted. `AdFlow` calls this on every
  /// controller after `disableAds`/`enableAds` and on `dispose()` — apps
  /// normally never need to call it, but it is safe to call at any time
  /// (2026-07 audit).
  Future<void> recheckGate();

  /// Invalidates an ad that was REQUESTED under a now-stale consent state and
  /// re-requests it under the fresh one — called after a consent /
  /// privacy-options mutation (release gate).
  ///
  /// A warm (not-yet-shown) full-screen ad, or a visible banner/native ad, was
  /// requested — and renders/measures — under the consent that applied at load
  /// time. After the user changes consent, that ad is privacy-stale even
  /// though showing it makes no new request: its impression and measurement
  /// still reflect the old choice. So a warm/visible ad is DROPPED and
  /// reloaded through the (re-forwarded) gate. A full-screen ad that is
  /// currently on screen is NOT interrupted — its impression already
  /// happened — but the next one it preloads on dismissal goes through the
  /// fresh gate.
  Future<void> invalidateForConsentChange();

  /// Cancels timers, disposes the current handle and stops the controller.
  void dispose();
}

/// Controllers for full-screen formats (interstitial, rewarded, rewarded
/// interstitial, app open).
abstract interface class FullScreenAdController implements AdController {
  /// Checks the gate, shows the warm ad, records the impression and
  /// preloads the next one on dismissal. Returns whether an ad was
  /// actually shown.
  ///
  /// 3.0: the reward callback lives only on the rewarded formats
  /// (`RewardedAdController.show(onReward:)` /
  /// `RewardedInterstitialAdController.show(onReward:)`) — it was silently
  /// ignored by interstitial and app-open, which is exactly the kind of
  /// API lie this interface no longer tells.
  Future<bool> show();
}
