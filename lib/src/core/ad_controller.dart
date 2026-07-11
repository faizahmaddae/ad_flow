import 'package:flutter/foundation.dart';

import '../seam/ad_sdk_types.dart';
import 'ad_load_state.dart';

/// Common surface of every ad controller.
abstract interface class AdController {
  /// Reactive load state (subscribe with `ValueListenableBuilder`).
  ValueListenable<AdLoadState> get state;

  /// Loads an ad if the gate allows and none is loaded/loading.
  Future<void> load();

  /// Cancels timers, disposes the current handle and stops the controller.
  void dispose();
}

/// Controllers for full-screen formats (interstitial, rewarded, rewarded
/// interstitial, app open).
abstract interface class FullScreenAdController implements AdController {
  /// Checks the gate, shows the warm ad, records the impression and
  /// preloads the next one on dismissal.
  ///
  /// Returns whether an ad was actually shown. [onReward] is required by
  /// the rewarded formats and ignored elsewhere.
  Future<bool> show({OnUserEarnedReward? onReward});
}
