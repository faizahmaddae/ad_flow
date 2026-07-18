import 'package:flutter/foundation.dart';

/// Runs an app-supplied callback with its failures ISOLATED (4.0 audit).
///
/// Every callback the package invokes on the app's behalf — `onPaidEvent`,
/// `onAdBlocked`, a reward grant — runs from deep inside a controller's state
/// machine or a plugin stream listener. An uncaught throw there used to
/// corrupt whichever transition invoked it (a `load()` pinned at `AdLoading`,
/// a paid event becoming an unhandled zone error) — an app bug in an
/// analytics hook must never take the ad layer down with it.
///
/// The throw is not swallowed: it is routed through `FlutterError.reportError`
/// (the framework's own callback-isolation idiom), so it still reaches the
/// console and any installed crash reporting.
void guardedCallback(void Function() callback, {required String debugName}) {
  try {
    callback();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'ad_flow',
        context: ErrorDescription(
          'while invoking the app-supplied $debugName callback (isolated; '
          'ad_flow state is unaffected)',
        ),
      ),
    );
  }
}
