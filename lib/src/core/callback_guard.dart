import 'dart:async';

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
///
/// Both a SYNCHRONOUS throw and an ASYNCHRONOUS rejection are contained
/// (4.1 audit). The parameter is typed `void Function()`, but Dart's
/// return-type covariance to `void` means an `async` closure — exactly what
/// the `onConsentChanged` docs invite (`() async { await forward(); }`) — is
/// assignable to it and returns a `Future` at runtime. A `try/catch` alone
/// only catches the synchronous part; the returned `Future`'s later rejection
/// used to escape as an unhandled zone error. Invoking through the untyped
/// `Function` recovers that runtime return value so a `Future` result can be
/// guarded too.
void guardedCallback(void Function() callback, {required String debugName}) {
  void report(Object error, StackTrace? stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack ?? StackTrace.current,
        library: 'ad_flow',
        context: ErrorDescription(
          'while invoking the app-supplied $debugName callback (isolated; '
          'ad_flow state is unaffected)',
        ),
      ),
    );
  }

  try {
    // Calling through `Function` (rather than the void-typed parameter)
    // yields the closure's real runtime return value — a `Future` for an
    // async callback — so its rejection can be contained too.
    final Object? result = (callback as Function)();
    if (result is Future) {
      result.catchError((Object error, StackTrace stack) => report(error, stack));
    }
  } catch (error, stack) {
    report(error, stack);
  }
}

/// Fire-and-forget a cleanup [future] (a handle `dispose()`, a subscription
/// `cancel()`) whose rejection must never become an unhandled zone error
/// (4.1 audit).
///
/// The seam's own handles contain their channel-dispose failures, but a
/// disposal/cancel is reached from many teardown paths, and an injected or
/// future [AdSdk] implementation can reject freely. `unawaited(x.dispose())`
/// would then surface a rejection with nothing listening; this routes it to
/// `FlutterError.reportError` instead, so teardown always completes cleanly.
void safeUnawaited(Future<void>? future, {String debugName = 'cleanup'}) {
  if (future == null) return;
  future.catchError((Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'ad_flow',
        context: ErrorDescription('while disposing/cancelling ($debugName)'),
      ),
    );
  });
}
