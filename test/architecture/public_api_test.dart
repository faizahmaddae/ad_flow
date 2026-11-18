import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the public surface of `package:ad_flow/ad_flow.dart` (6.0, ADR-084).
///
/// 5.x exported 105 types, internals included, so every internal fix risked a
/// major release (2.0 → 5.0 in six days). 6.0 exports only what app code
/// uses; the seam's handles/events/load specs, the full-screen engine and the
/// policy collaborators live in `ad_flow_testing.dart`. This test makes any
/// change to the main library's surface deliberate: adding or removing a
/// public name fails here until [expected] is updated — and an addition
/// should only land when app code needs it (otherwise export it from
/// `ad_flow_testing.dart`). A removal is a breaking change.
///
/// A plain parse of the barrel rather than an analyzer plugin: exports with
/// `show`/`hide` are resolved against each exported file's top-level
/// declarations.
void main() {
  test('ad_flow.dart exports exactly the pinned public API', () {
    expect(
      _exportedNames('lib/ad_flow.dart'),
      expected,
      reason:
          'The public API of package:ad_flow/ad_flow.dart changed. If that '
          'is intended, update `expected` in this test, CHANGELOG.md and — '
          'for a removal or rename — MIGRATION.md. Internals belong in '
          'ad_flow_testing.dart.',
    );
  });

  test('the internals stay out of the main library', () {
    final main = _exportedNames('lib/ad_flow.dart');
    for (final internal in const [
      'AdGate',
      'BannerHandle',
      'BannerHeightMemory',
      'BannerLoadSpec',
      'FakeAdSdk',
      'FullScreenAdControllerBase',
      'FullScreenAdCoordinator',
      'InMemoryKeyValueStore',
      'InterstitialHandle',
      'RetryPolicy',
      'SharedPrefsKeyValueStore',
      'StoredFrequencyCapPolicy',
      'requestConfigFrom',
      'resolveAdUnitId',
    ]) {
      expect(main, isNot(contains(internal)), reason: internal);
    }
  });
}

/// Every public top-level name a barrel exports.
Set<String> _exportedNames(String barrelPath) {
  final barrel = File(barrelPath).readAsStringSync();
  final export = RegExp(
    r"""^export\s+'([^']+)'(?:\s+(show|hide)\s+([^;]+))?;""",
    multiLine: true,
  );
  final names = <String>{};
  for (final match in export.allMatches(barrel)) {
    final file = File('lib/${match.group(1)}');
    final declared = _topLevelNames(file.readAsStringSync());
    final mode = match.group(2);
    final listed =
        match
            .group(3)
            ?.split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet() ??
        const <String>{};
    names.addAll(switch (mode) {
      'show' => declared.intersection(listed),
      'hide' => declared.difference(listed),
      _ => declared,
    });
  }
  return names;
}

/// Public top-level declarations (types, functions, variables) of a library.
Set<String> _topLevelNames(String source) {
  final type = RegExp(
    r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
    r'(?:class|enum|typedef|mixin|extension\s+type)\s+([A-Za-z]\w*)',
    multiLine: true,
  );
  // A top-level function or variable starts at column 0 with a return or
  // variable type (or const/final), never with a keyword handled above.
  final member = RegExp(
    r'^(?!(?:import|export|part|library|abstract|final\s+class|sealed|base|'
    r'interface|mixin|class|enum|typedef|extension)\b)'
    r'(?:const\s+|final\s+)?[A-Za-z_][\w<>?, ]*?\s+([a-zA-Z]\w*)\s*(?:\(|=|;)',
    multiLine: true,
  );
  return {
    for (final match in type.allMatches(source)) match.group(1)!,
    for (final match in member.allMatches(source)) match.group(1)!,
  }.where((name) => !name.startsWith('_')).toSet();
}

/// The pinned public API of `package:ad_flow/ad_flow.dart`: 68 types and
/// 4 helper functions (6.0.0).
const expected = <String>{
  'AdBlockReason',
  'AdBlocked',
  'AdConsentStatus',
  'AdController',
  'AdFailed',
  'AdFlow',
  'AdFlowBanner',
  'AdFlowConfig',
  'AdFlowError',
  'AdFlowErrorKind',
  'AdFlowNativeAd',
  'AdIdle',
  'AdInspectorResult',
  'AdLoadState',
  'AdLoaded',
  'AdLoading',
  'AdPaidEvent',
  'AdPlatform',
  'AdRequestOptions',
  'AdResponseSummary',
  'AdRevenuePrecision',
  'AdSdk',
  'AdShowResult',
  'AdShowing',
  'AnchoredBannerSize',
  'AppOpenAdController',
  'AppOpenAdManager',
  'AppOpenConfig',
  'AttExplainerContent',
  'AttExplainerPresenter',
  'AttExplainerScreen',
  'AttStatus',
  'BannerAdController',
  'BannerConfig',
  'BannerKind',
  'CollapsiblePlacement',
  'ConsentDebugGeography',
  'ConsentDebugOptions',
  'ConsentGateway',
  'FixedBannerSize',
  'FrequencyCap',
  'FullScreenAdController',
  'InterstitialAdController',
  'InterstitialConfig',
  'KeyValueStore',
  'MaxContentRating',
  'MediationNetworkExtras',
  'NativeAdController',
  'NativeConfig',
  'NativeTemplateKind',
  'OnUserEarnedReward',
  'PlatformAdUnitId',
  'PrivacyOptionsButton',
  'PrivacyOptionsRequirement',
  'RetryConfig',
  'RewardEarned',
  'RewardIntroContent',
  'RewardedAdController',
  'RewardedConfig',
  'RewardedInterstitialAdController',
  'RewardedInterstitialConfig',
  'RewardedIntroPresenter',
  'RewardedIntroScreen',
  'ServerSideVerification',
  'TcfConsent',
  'TcfConsentReader',
  'TestAdUnitIds',
  'UmpConsentGateway',
  'adPlatformOf',
  'asAdFlowError',
  'currentAdPlatform',
  'readDeviceTcfConsent',
};
