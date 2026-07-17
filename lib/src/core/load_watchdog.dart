import 'dart:async';

import 'ad_flow_error.dart';

/// Bounds one ad-load await with a watchdog (4.0 audit).
///
/// The `google_mobile_ads` plugin has NO load timeout of its own (verified
/// against the 9.0.0 source: no timer anywhere in its load paths, and a load
/// whose callback never arrives is never cleaned up). A dropped channel
/// callback, a hung SSV attach or a hung `getPlatformAdSize` therefore left
/// the awaiting controller pinned at `AdLoading` for the rest of the session.
///
/// On timeout this throws `AdFlowError(timeout)` — landing in the
/// controller's normal `AdFailed` + retry path — and arranges for the LATE
/// completion, if it ever arrives, to be disposed rather than leaked. The
/// late handle can never be installed or stomp a newer attempt: the only code
/// that installs handles is the load continuation, which already took the
/// timeout branch.
Future<T> watchAdLoad<T>({
  required Future<T> pending,
  required Duration? timeout,
  required Future<void> Function(T handle) disposeLate,
  required String slot,
}) async {
  if (timeout == null) return pending;
  try {
    return await pending.timeout(timeout);
  } on TimeoutException {
    unawaited(
      pending
          .then((handle) => disposeLate(handle))
          .catchError((Object _) {}), // a late FAILURE needs no cleanup
    );
    throw AdFlowError(
      AdFlowErrorKind.timeout,
      'The $slot load received no SDK callback within '
      '${timeout.inSeconds}s (watchdog, RetryConfig.loadTimeout).',
    );
  }
}
