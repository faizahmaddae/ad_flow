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

export 'src/seam/fake_ad_sdk.dart';
