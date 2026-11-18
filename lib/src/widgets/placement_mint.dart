import 'package:flutter/foundation.dart';

import '../core/ad_flow_error.dart';

/// Mints a widget-first placement's controller, or returns null when the slot
/// is not configured for this platform (ADR-085).
///
/// `AdFlow.banner()` / `AdFlow.native()` throw `AdFlowError(invalidConfig)`
/// when there is no slot config or it has no ad unit ID for the running
/// platform. `AdFlowBanner(adFlow:)` / `AdFlowNativeAd(adFlow:)` treat that
/// the way the nullable full-screen getters do — the slot does not exist on
/// this platform — and render nothing, instead of failing their build (a red
/// screen in debug, a grey box in release). A debug build prints why, once
/// per mount, so a forgotten ID is still easy to spot.
T? mintPlacement<T extends Object>(
  T Function() mint, {
  required String widgetName,
}) {
  try {
    return mint();
  } on AdFlowError catch (error) {
    if (error.kind != AdFlowErrorKind.invalidConfig) rethrow;
    if (kDebugMode) {
      debugPrint('ad_flow: $widgetName renders nothing — ${error.message}');
    }
    return null;
  }
}
