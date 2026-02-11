// Copyright 2024 - AdMob Integration Package
// Fake ad objects for unit testing
//
// Uses Dart's Fake pattern: extends Fake implements SdkType.
// Fake provides noSuchMethod catch-all; only methods actually
// called by managers need explicit overrides.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ══════════════════════════════════════════════════════════════════════════
// INTERSTITIAL AD
// ══════════════════════════════════════════════════════════════════════════

class FakeInterstitialAd extends Fake implements InterstitialAd {
  FullScreenContentCallback<InterstitialAd>? _fscCallback;
  bool wasDisposed = false;
  bool wasShown = false;

  @override
  set fullScreenContentCallback(FullScreenContentCallback<InterstitialAd>? cb) =>
      _fscCallback = cb;

  @override
  FullScreenContentCallback<InterstitialAd>? get fullScreenContentCallback =>
      _fscCallback;

  @override
  Future<void> show() async {
    wasShown = true;
    _fscCallback?.onAdShowedFullScreenContent?.call(this);
  }

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  String get adUnitId => 'fake_interstitial_unit';

  @override
  ResponseInfo? get responseInfo => null;

  // Helper to simulate dismiss
  void simulateDismiss() {
    _fscCallback?.onAdDismissedFullScreenContent?.call(this);
  }

  // Helper to simulate show failure
  void simulateShowFailure(AdError error) {
    _fscCallback?.onAdFailedToShowFullScreenContent?.call(this, error);
  }

  // Helper to simulate impression
  void simulateImpression() {
    _fscCallback?.onAdImpression?.call(this);
  }

  // Helper to simulate click
  void simulateClick() {
    _fscCallback?.onAdClicked?.call(this);
  }

  // Helper to simulate will dismiss (iOS)
  void simulateWillDismiss() {
    _fscCallback?.onAdWillDismissFullScreenContent?.call(this);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// REWARDED AD
// ══════════════════════════════════════════════════════════════════════════

class FakeRewardedAd extends Fake implements RewardedAd {
  FullScreenContentCallback<RewardedAd>? _fscCallback;
  bool wasDisposed = false;
  bool wasShown = false;
  bool immersiveModeSet = false;
  OnUserEarnedRewardCallback? _lastRewardCallback;

  @override
  set fullScreenContentCallback(FullScreenContentCallback<RewardedAd>? cb) =>
      _fscCallback = cb;

  @override
  FullScreenContentCallback<RewardedAd>? get fullScreenContentCallback =>
      _fscCallback;

  @override
  Future<void> show(
      {required OnUserEarnedRewardCallback onUserEarnedReward}) async {
    wasShown = true;
    _lastRewardCallback = onUserEarnedReward;
    _fscCallback?.onAdShowedFullScreenContent?.call(this);
  }

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  Future<void> setImmersiveMode(bool immersiveMode) async {
    immersiveModeSet = immersiveMode;
  }

  @override
  String get adUnitId => 'fake_rewarded_unit';

  @override
  ResponseInfo? get responseInfo => null;

  @override
  Future<void> setServerSideOptions(ServerSideVerificationOptions options) async {
    // Store for testing if needed
  }

  // Helper to simulate reward earned
  void simulateReward({num amount = 10, String type = 'coins'}) {
    _lastRewardCallback?.call(this, FakeRewardItem(amount: amount, type: type));
  }

  // Helper to simulate dismiss
  void simulateDismiss() {
    _fscCallback?.onAdDismissedFullScreenContent?.call(this);
  }

  // Helper to simulate show failure
  void simulateShowFailure(AdError error) {
    _fscCallback?.onAdFailedToShowFullScreenContent?.call(this, error);
  }

  // Helper to simulate impression
  void simulateImpression() {
    _fscCallback?.onAdImpression?.call(this);
  }

  // Helper to simulate click
  void simulateClick() {
    _fscCallback?.onAdClicked?.call(this);
  }

  // Helper to simulate will dismiss (iOS)
  void simulateWillDismiss() {
    _fscCallback?.onAdWillDismissFullScreenContent?.call(this);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// APP OPEN AD
// ══════════════════════════════════════════════════════════════════════════

class FakeAppOpenAd extends Fake implements AppOpenAd {
  FullScreenContentCallback<AppOpenAd>? _fscCallback;
  bool wasDisposed = false;
  bool wasShown = false;

  @override
  set fullScreenContentCallback(FullScreenContentCallback<AppOpenAd>? cb) =>
      _fscCallback = cb;

  @override
  FullScreenContentCallback<AppOpenAd>? get fullScreenContentCallback =>
      _fscCallback;

  @override
  Future<void> show() async {
    wasShown = true;
    _fscCallback?.onAdShowedFullScreenContent?.call(this);
  }

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  String get adUnitId => 'fake_app_open_unit';

  @override
  ResponseInfo? get responseInfo => null;

  // Helper to simulate dismiss
  void simulateDismiss() {
    _fscCallback?.onAdDismissedFullScreenContent?.call(this);
  }

  // Helper to simulate show failure
  void simulateShowFailure(AdError error) {
    _fscCallback?.onAdFailedToShowFullScreenContent?.call(this, error);
  }

  // Helper to simulate impression
  void simulateImpression() {
    _fscCallback?.onAdImpression?.call(this);
  }

  // Helper to simulate click
  void simulateClick() {
    _fscCallback?.onAdClicked?.call(this);
  }

  // Helper to simulate will dismiss (iOS)
  void simulateWillDismiss() {
    _fscCallback?.onAdWillDismissFullScreenContent?.call(this);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// BANNER AD
// ══════════════════════════════════════════════════════════════════════════

class FakeBannerAd extends Fake implements BannerAd {
  bool wasDisposed = false;

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  String get adUnitId => 'fake_banner_unit';
}

// ══════════════════════════════════════════════════════════════════════════
// NATIVE AD
// ══════════════════════════════════════════════════════════════════════════

class FakeNativeAd extends Fake implements NativeAd {
  bool wasDisposed = false;

  @override
  Future<void> dispose() async {
    wasDisposed = true;
  }

  @override
  String get adUnitId => 'fake_native_unit';
}

// ══════════════════════════════════════════════════════════════════════════
// REWARD ITEM
// ══════════════════════════════════════════════════════════════════════════

class FakeRewardItem extends Fake implements RewardItem {
  @override
  final num amount;
  @override
  final String type;

  FakeRewardItem({this.amount = 10, this.type = 'coins'});
}

// ══════════════════════════════════════════════════════════════════════════
// INITIALIZATION STATUS
// ══════════════════════════════════════════════════════════════════════════

class FakeInitializationStatus extends Fake implements InitializationStatus {
  @override
  Map<String, AdapterStatus> get adapterStatuses => {};
}
