import 'ad_block_reason.dart';
import 'ad_flow_error.dart';

/// The lifecycle state of an ad slot, exposed by every controller as a
/// `ValueListenable<AdLoadState>`.
///
/// State machine: `AdIdle → AdLoading → AdLoaded → AdShowing → (dispose /
/// reload → AdLoading)`, with `AdFailed` reachable from `AdLoading` and
/// `AdShowing`, and `AdBlocked` reachable whenever a load is REFUSED (or a
/// live ad is dropped) by policy rather than failed by the SDK: consent not
/// granted yet, Remove-Ads on, the warm ad expired. A blocked slot re-checks
/// its gate on a backoff and moves on to `AdLoading` once permitted.
sealed class AdLoadState {
  const AdLoadState();
}

/// No ad is loaded and no load is in flight.
class AdIdle extends AdLoadState {
  /// Const instance.
  const AdIdle();
}

/// The slot is not PERMITTED to load right now — and here is why (3.0).
///
/// This is what used to be reported as [AdIdle] plus a side-channel
/// `lastBlockReason` (ADR-045 kept `AdLoadState` closed in 2.x because adding
/// a case breaks exhaustive switches). Making it a real state removes the
/// ambiguity that made "why aren't my ads showing?" unanswerable from
/// [AdLoadState] alone: consent still pending, Remove-Ads on, and "nothing
/// requested yet" are now three different values.
///
/// Most reasons are NORMAL operation (a frequency cap doing its job, consent
/// not yet settled on a fresh install) — this is not an error state. The
/// controller keeps re-checking its gate on a backoff; when the gate opens
/// the slot moves to [AdLoading] on its own.
class AdBlocked extends AdLoadState {
  /// Blocked for [reason].
  const AdBlocked(this.reason);

  /// Why the slot may not load/serve right now.
  final AdBlockReason reason;

  @override
  bool operator ==(Object other) =>
      other is AdBlocked && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// A load request is in flight (including retry waits).
class AdLoading extends AdLoadState {
  /// Const instance.
  const AdLoading();
}

/// An ad is loaded and ready to show.
class AdLoaded extends AdLoadState {
  /// Const instance.
  const AdLoaded();
}

/// A full-screen ad is currently on screen.
class AdShowing extends AdLoadState {
  /// Const instance.
  const AdShowing();
}

/// The last load or show attempt failed.
class AdFailed extends AdLoadState {
  /// Wraps the [error] that caused the failure.
  const AdFailed(this.error);

  /// Why the ad failed.
  final AdFlowError error;

  @override
  bool operator ==(Object other) => other is AdFailed && other.error == error;

  @override
  int get hashCode => error.hashCode;
}
