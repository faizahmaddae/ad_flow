/// Easy AdMob integration for Flutter.
///
/// ad_flow wraps `google_mobile_ads` into a testable, revenue-minded ad
/// layer with policy-aware defaults: banner, interstitial, rewarded,
/// rewarded interstitial, native and app open ads, plus UMP consent
/// management.
///
/// This barrel exports the public API only. Internals live under `src/`.
library;

export 'src/config/ad_flow_config.dart';
export 'src/config/ad_platform.dart';
export 'src/consent/consent_gateway.dart';
export 'src/consent/explainer_content.dart';
export 'src/controllers/app_open_ad_controller.dart';
export 'src/controllers/banner_ad_controller.dart';
export 'src/controllers/full_screen_ad_controller_base.dart';
export 'src/controllers/interstitial_ad_controller.dart';
export 'src/controllers/native_ad_controller.dart';
export 'src/controllers/rewarded_ad_controller.dart';
export 'src/controllers/rewarded_interstitial_ad_controller.dart';
export 'src/core/ad_block_reason.dart';
export 'src/core/ad_controller.dart';
export 'src/core/ad_flow_error.dart';
export 'src/core/ad_load_state.dart';
export 'src/facade/ad_flow.dart';
export 'src/lifecycle/app_open_ad_manager.dart';
export 'src/policy/ad_gate.dart';
export 'src/policy/frequency_cap_policy.dart';
export 'src/policy/full_screen_ad_coordinator.dart';
export 'src/policy/key_value_store.dart';
export 'src/policy/retry_policy.dart';
export 'src/seam/ad_sdk.dart';
export 'src/seam/ad_sdk_types.dart';
export 'src/widgets/ad_flow_banner.dart';
export 'src/widgets/ad_flow_native_ad.dart';
export 'src/widgets/att_explainer_screen.dart';
export 'src/widgets/consent_explainer_screen.dart';
export 'src/widgets/privacy_options_button.dart';
export 'src/widgets/rewarded_intro_screen.dart';
