import 'dart:async';

import '../core/ad_load_state.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'full_screen_ad_controller_base.dart';

/// Runtime server-side-verification handling shared by the rewarded and
/// rewarded-interstitial controllers (4.1 audit).
///
/// Config-time SSV is frozen at startup, but real apps learn the `userId` at
/// login and the per-show `customData` (which mission earned the reward) long
/// after the ad preloaded. [setServerSideVerification] applies an override to
/// the warm ad AND every future load. Two lifecycle hazards this closes:
///
/// - **In-flight-load race.** If a load is in flight when the override is set,
///   there is no warm handle to update — the load already dispatched with the
///   *previous* payload and, left alone, would install an ad carrying it while
///   the caller believes the update applied. The override is re-attached to
///   the ad the moment it installs ([onLoaded]).
/// - **Update failure leaves a stale ad showable.** If attaching to the warm
///   ad fails, the ad still sits `AdLoaded` carrying the OLD payload and could
///   be shown with the wrong verification. The failure now DROPS that ad (and
///   warms a fresh one carrying the new override) before it rethrows.
mixin RuntimeSsvController on FullScreenAdControllerBase {
  ServerSideVerification? _ssvOverride;
  bool _reapplyPending = false;

  /// The config-time SSV for this format (`_config.ssv`).
  ServerSideVerification? get configuredSsv;

  /// The SSV a load should dispatch with — the runtime override if set, else
  /// the configured value.
  ServerSideVerification? get effectiveSsv => _ssvOverride ?? configuredSsv;

  /// Attaches [ssv] to the (correctly-typed) warm [handle].
  Future<void> attachSsv(FullScreenAdHandle handle, ServerSideVerification ssv);

  /// Applies [ssv] to the currently warm ad (if any) AND every future load,
  /// replacing the config value.
  ///
  /// Rethrows an `AdFlowError` if attaching to a warm ad fails — a caller
  /// granting high-value rewards must know its payload did not attach — and,
  /// in that case, DROPS the now-stale warm ad so it can never be shown with
  /// the wrong verification (4.1 audit). If a load is in flight, the override
  /// is re-attached to the resulting ad on completion.
  Future<void> setServerSideVerification(ServerSideVerification ssv) async {
    _ssvOverride = ssv;
    final handle = currentHandle;
    if (isReady && handle != null) {
      try {
        await attachSsv(handle, ssv);
      } catch (_) {
        // The warm ad now carries a stale/failed payload. Drop it and warm a
        // fresh one (which re-dispatches with the new override) so nothing
        // showable is verified with the wrong data, then surface the failure.
        discardCurrentAd();
        rethrow;
      }
      return;
    }
    // No warm handle to update directly. If a load is in flight it dispatched
    // with the previous payload — re-attach the latest once it installs.
    if (state.value is AdLoading) _reapplyPending = true;
  }

  @override
  void onLoaded() {
    super.onLoaded();
    if (!_reapplyPending) return;
    _reapplyPending = false;
    final handle = currentHandle;
    final ssv = _ssvOverride;
    if (handle == null || ssv == null) return;
    // The just-installed ad may carry the pre-update payload — re-attach the
    // latest override. A failure means it silently carries stale verification,
    // so drop it (a fresh load re-dispatches with the override).
    unawaited(
      attachSsv(handle, ssv).catchError((Object _) {
        if (isReady) discardCurrentAd();
      }),
    );
  }
}
