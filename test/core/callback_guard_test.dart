import 'package:ad_flow/src/core/callback_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// `guardedCallback` isolates app-supplied callbacks. 4.0 contained SYNC
/// throws; 4.1 must also contain an ASYNC callback's later rejection — the
/// package's own docs invite `onConsentChanged = () async { await ... }`,
/// and `void Function()` accepts an async closure (return-type covariance to
/// void), so a rejecting Future escaped as an unhandled zone error.
void main() {
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previousOnError;

  setUp(() {
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });
  tearDown(() => FlutterError.onError = previousOnError);

  test('a synchronous throw is reported, not rethrown', () {
    guardedCallback(() => throw StateError('sync bug'), debugName: 'x');
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
  });

  test('an ASYNC callback rejection is contained (was an unhandled zone '
      'error)', () async {
    // An async closure assigned to `void Function()` — exactly what the
    // onConsentChanged docs show.
    // ignore: prefer_function_declarations_over_variables
    final void Function() asyncThrows = () async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('async bug');
    };

    // In a Dart test, an unhandled async error inside a Future the test
    // awaits/flushes fails the test. If guardedCallback did not attach a
    // catchError to the returned Future, this would surface as an unhandled
    // error rather than a reported one.
    guardedCallback(asyncThrows, debugName: 'onConsentChanged');
    await pumpEventQueue();

    expect(
      reported,
      hasLength(1),
      reason: 'the async rejection must be routed to FlutterError.reportError',
    );
    expect(reported.single.exception, isA<StateError>());
  });

  test('a normally-completing async callback reports nothing', () async {
    // ignore: prefer_function_declarations_over_variables
    final void Function() ok = () async {
      await Future<void>.delayed(Duration.zero);
    };
    guardedCallback(ok, debugName: 'x');
    await pumpEventQueue();
    expect(reported, isEmpty);
  });

  group('safeUnawaited', () {
    test('a rejecting cleanup Future is reported, never an unhandled zone '
        'error', () async {
      safeUnawaited(
        Future<void>.error(StateError('dispose blew up')),
        debugName: 'handle',
      );
      await pumpEventQueue();
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
    });

    test('null and a clean Future report nothing', () async {
      safeUnawaited(null);
      safeUnawaited(Future<void>.value());
      await pumpEventQueue();
      expect(reported, isEmpty);
    });
  });
}
