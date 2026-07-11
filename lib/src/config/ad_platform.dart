import 'package:flutter/foundation.dart';

import '../core/ad_flow_error.dart';

/// The mobile platform ads are served on. Injectable so tests and the
/// facade never read global platform state directly.
enum AdPlatform {
  /// Android.
  android,

  /// iOS.
  ios,
}

/// Resolves the current [AdPlatform] from [defaultTargetPlatform].
///
/// Tests can steer this with [debugDefaultTargetPlatformOverride].
AdPlatform currentAdPlatform() => adPlatformOf(defaultTargetPlatform);

/// Maps a [TargetPlatform] to an [AdPlatform].
///
/// Throws an [AdFlowError] (kind `invalidConfig`) for unsupported platforms —
/// ad_flow is Android + iOS only.
AdPlatform adPlatformOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => AdPlatform.android,
  TargetPlatform.iOS => AdPlatform.ios,
  _ => throw AdFlowError(
    AdFlowErrorKind.invalidConfig,
    'ad_flow supports Android and iOS only; running on $platform.',
  ),
};
