import 'dart:async';

import 'package:ad_flow/src/core/ad_show_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Starts [show] and resolves once its DISPATCH decision is known: true when
/// the ad was handed to the SDK (or already shown and closed), false when the
/// show was refused or failed.
///
/// Since 6.0 `show()` completes only when the ad CLOSES. Most engine tests
/// check the dispatch decision and simulate the close themselves afterwards;
/// this keeps them reading the way they did, without awaiting a close that
/// only the test itself can produce.
Future<bool> dispatch(Future<AdShowResult> show) async {
  AdShowResult? result;
  unawaited(show.then((r) => result = r));
  await pumpEventQueue();
  return result?.shown ?? true;
}
