import 'ad_flow_error.dart';

/// The lifecycle state of an ad slot, exposed by every controller as a
/// `ValueListenable<AdLoadState>`.
///
/// State machine: `AdIdle → AdLoading → AdLoaded → AdShowing → (dispose /
/// reload → AdLoading)`, with `AdFailed` reachable from `AdLoading` and
/// `AdShowing`.
sealed class AdLoadState {
  const AdLoadState();
}

/// No ad is loaded and no load is in flight.
class AdIdle extends AdLoadState {
  /// Const instance.
  const AdIdle();
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
