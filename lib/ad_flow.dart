/// AdMob for Flutter with policy-aware defaults.
///
/// ad_flow wraps `google_mobile_ads` into one ad layer: banner, interstitial,
/// rewarded, rewarded interstitial, native and app open ads, Google's UMP
/// consent flow, and optional iOS App Tracking Transparency.
///
/// ```dart
/// final ads = await AdFlow.initialize(
///   const AdFlowConfig(
///     banner: BannerConfig(
///       adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…', ios: 'ca-app-pub-…'),
///     ),
///     interstitial: InterstitialConfig(
///       adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…', ios: 'ca-app-pub-…'),
///     ),
///   ),
/// );
///
/// // A banner placement: one widget that reserves its height.
/// Scaffold(bottomNavigationBar: AdFlowBanner(adFlow: ads, safeArea: true));
///
/// // A full-screen ad at a natural break: completes when the ad closes.
/// final result = await ads.interstitial?.show();
/// ```
///
/// [AdFlow.initialize] returns at once; consent, SDK start-up and the first
/// loads run in the background, and no ad is requested before consent allows
/// it. Debug builds serve Google's test ads automatically
/// ([AdFlowConfig.testMode]). Test doubles are in
/// `package:ad_flow/ad_flow_testing.dart`.
library;

export 'src/config/ad_flow_config.dart'
    hide
        resolveAdUnitId,
        requestConfigFrom,
        validateBannerConfig,
        validateNativeConfig;
export 'src/config/ad_platform.dart';
export 'src/consent/consent_gateway.dart';
export 'src/consent/explainer_content.dart';
export 'src/consent/tcf_consent.dart'
    show TcfConsent, TcfConsentReader, readDeviceTcfConsent;
export 'src/controllers/app_open_ad_controller.dart';
export 'src/controllers/banner_ad_controller.dart' hide BannerHeightMemory;
export 'src/controllers/interstitial_ad_controller.dart';
export 'src/controllers/native_ad_controller.dart';
export 'src/controllers/rewarded_ad_controller.dart';
export 'src/controllers/rewarded_interstitial_ad_controller.dart';
export 'src/core/ad_block_reason.dart';
export 'src/core/ad_controller.dart';
export 'src/core/ad_flow_error.dart';
export 'src/core/ad_load_state.dart';
export 'src/core/ad_show_result.dart';
export 'src/facade/ad_flow.dart';
export 'src/lifecycle/app_open_ad_manager.dart';
export 'src/policy/key_value_store.dart' show KeyValueStore;
// The seam's interface only, as the `sdk:` injection type. Its handles,
// events and load specs are implementation detail (they track the plugin) and
// are exported from ad_flow_testing.dart for test doubles.
export 'src/seam/ad_sdk.dart' show AdSdk;
export 'src/seam/ad_sdk_types.dart'
    show
        AdConsentStatus,
        AdInspectorResult,
        AdPaidEvent,
        AdRequestOptions,
        AdResponseSummary,
        AdRevenuePrecision,
        AnchoredBannerSize,
        AttStatus,
        CollapsiblePlacement,
        ConsentDebugGeography,
        ConsentDebugOptions,
        FixedBannerSize,
        MaxContentRating,
        MediationNetworkExtras,
        NativeTemplateKind,
        OnUserEarnedReward,
        PrivacyOptionsRequirement,
        RewardEarned,
        ServerSideVerification;
export 'src/widgets/ad_flow_banner.dart';
export 'src/widgets/ad_flow_native_ad.dart';
export 'src/widgets/att_explainer_screen.dart';
export 'src/widgets/privacy_options_button.dart';
export 'src/widgets/rewarded_intro_screen.dart';
