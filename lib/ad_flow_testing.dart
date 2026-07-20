/// Test doubles for apps that unit-test their ad integration.
///
/// Import in test files only:
/// ```dart
/// import 'package:ad_flow/ad_flow_testing.dart';
///
/// final sdk = FakeAdSdk()..canRequestAdsResult = true;
/// final ads = await AdFlow.initialize(config, sdk: sdk, ...);
/// ```
library;

import 'src/lifecycle/launch_latch.dart';

export 'src/seam/fake_ad_sdk.dart';

/// Resets the process-global one-shot App Open cold-launch latch used by
/// `AppOpenAdManager.showAtLaunchIfReady` — call in test `setUp` so tests do
/// not leak the consumed latch into each other. Test-only; NOT part of the
/// production API (`package:ad_flow/ad_flow.dart` never exposes it).
void resetAppOpenLaunchOpportunity() => LaunchLatch.reset();
