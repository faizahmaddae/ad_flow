/// Easy AdMob integration for Flutter.
///
/// ad_flow wraps `google_mobile_ads` into a policy-compliant,
/// revenue-optimized, testable ad layer: banner, interstitial, rewarded,
/// rewarded interstitial, native and app open ads, plus UMP consent
/// management.
///
/// This barrel exports the public API only. Internals live under `src/`.
library;

export 'src/config/ad_flow_config.dart';
export 'src/config/ad_platform.dart';
export 'src/consent/consent_gateway.dart';
export 'src/core/ad_flow_error.dart';
export 'src/core/ad_load_state.dart';
export 'src/policy/ad_gate.dart';
export 'src/policy/frequency_cap_policy.dart';
export 'src/policy/full_screen_ad_coordinator.dart';
export 'src/policy/key_value_store.dart';
export 'src/policy/retry_policy.dart';
export 'src/seam/ad_sdk.dart';
export 'src/seam/ad_sdk_types.dart';
