// Copyright 2024 - AdMob Integration Package
// Mediation Helper for forwarding consent to third-party ad networks

import 'package:flutter/foundation.dart';

/// Callback type for forwarding consent to a mediation network.
///
/// [gdprConsent] - `true` if user has GDPR consent for personalized ads.
/// [ccpaOptOut] - `true` if user opted out of data sale (CCPA "Do Not Sell").
typedef MediationConsentForwarder =
    Future<void> Function({
      required bool gdprConsent,
      required bool ccpaOptOut,
    });

/// Configuration for mediation consent settings.
///
/// Pass this to [MediationHelper.forwardConsent] to specify
/// what consent values to forward to mediation networks.
class MediationConsentConfig {
  /// Whether user has given GDPR consent for personalized ads.
  final bool hasGdprConsent;

  /// Whether user has opted out of data sale (CCPA/US Privacy).
  /// `true` means user opted OUT ("Do Not Sell My Personal Information").
  final bool ccpaOptOut;

  /// Whether to enable verbose logging.
  final bool enableLogging;

  const MediationConsentConfig({
    required this.hasGdprConsent,
    this.ccpaOptOut = false,
    this.enableLogging = true,
  });

  /// Creates a config assuming user gave full consent.
  factory MediationConsentConfig.fullConsent({bool enableLogging = true}) {
    return MediationConsentConfig(
      hasGdprConsent: true,
      ccpaOptOut: false,
      enableLogging: enableLogging,
    );
  }

  /// Creates a config assuming user denied consent.
  factory MediationConsentConfig.noConsent({bool enableLogging = true}) {
    return MediationConsentConfig(
      hasGdprConsent: false,
      ccpaOptOut: true,
      enableLogging: enableLogging,
    );
  }
}

/// Result of forwarding consent to a mediation network.
class MediationForwardResult {
  /// Name of the mediation network.
  final String networkName;

  /// Whether consent was successfully forwarded.
  final bool success;

  /// Error message if forwarding failed.
  final String? error;

  const MediationForwardResult({
    required this.networkName,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    if (success) return '$networkName: ✓ consent forwarded';
    return '$networkName: ✗ failed - $error';
  }
}

/// Summary of all mediation consent forwarding operations.
class MediationForwardSummary {
  /// Results for each registered network.
  final List<MediationForwardResult> results;

  /// Timestamp when forwarding was performed.
  final DateTime timestamp;

  const MediationForwardSummary({
    required this.results,
    required this.timestamp,
  });

  /// Networks that had consent successfully forwarded.
  List<MediationForwardResult> get successful =>
      results.where((r) => r.success).toList();

  /// Networks that failed.
  List<MediationForwardResult> get failed =>
      results.where((r) => !r.success).toList();

  /// Whether all networks had consent forwarded successfully.
  bool get allSuccessful => failed.isEmpty;

  /// Whether any networks are registered.
  bool get hasNetworks => results.isNotEmpty;

  @override
  String toString() {
    if (results.isEmpty) {
      return 'MediationForwardSummary: No networks registered';
    }
    final buffer = StringBuffer('MediationForwardSummary:\n');
    for (final result in results) {
      buffer.writeln('  - $result');
    }
    return buffer.toString();
  }
}

/// Helper for forwarding consent to mediation ad networks.
///
/// This class allows you to register mediation adapters and forward
/// consent to all of them at once. It works with any mediation network
/// by using a callback-based registration system.
///
/// **Important:** Call [forwardConsent] BEFORE initializing the Mobile Ads SDK
/// to ensure consent is properly propagated to all networks.
///
/// ## Quick Start
///
/// ### Step 1: Add mediation dependencies to pubspec.yaml
/// ```yaml
/// dependencies:
///   gma_mediation_unity: ^1.6.2      # Optional
///   gma_mediation_applovin: ^2.5.1   # Optional
/// ```
///
/// ### Step 2: Register adapters (in main.dart, before AdFlow.initialize)
/// ```dart
/// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
/// import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // Register Unity Ads
///   MediationHelper.registerAdapter(
///     name: 'Unity Ads',
///     forwarder: ({required gdprConsent, required ccpaOptOut}) async {
///       GmaMediationUnity.setGDPRConsent(gdprConsent);
///       GmaMediationUnity.setCCPAConsent(!ccpaOptOut);
///     },
///   );
///
///   // Register AppLovin
///   MediationHelper.registerAdapter(
///     name: 'AppLovin',
///     forwarder: ({required gdprConsent, required ccpaOptOut}) async {
///       GmaMediationApplovin.setHasUserConsent(gdprConsent);
///       GmaMediationApplovin.setDoNotSell(ccpaOptOut);
///     },
///   );
///
///   // Initialize ad_flow (consent forwarding happens automatically)
///   await AdFlow.instance.initialize(...);
/// }
/// ```
///
/// ## Supported Networks
///
/// Any network with a `gma_mediation_*` package can be registered:
/// - Unity Ads: `gma_mediation_unity`
/// - AppLovin: `gma_mediation_applovin`
/// - Meta: `gma_mediation_meta` (auto-reads from SharedPreferences)
/// - And many more...
class MediationHelper {
  MediationHelper._();

  /// Registered adapters: name -> forwarder callback
  static final Map<String, MediationConsentForwarder> _adapters = {};

  /// Whether any adapters are registered.
  static bool get hasAdapters => _adapters.isNotEmpty;

  /// Names of all registered adapters.
  static List<String> get registeredAdapters => _adapters.keys.toList();

  /// Registers a mediation adapter for consent forwarding.
  ///
  /// [name] - Display name for the network (used in logs/results).
  /// [forwarder] - Callback that forwards consent to the network SDK.
  ///
  /// Example for Unity Ads:
  /// ```dart
  /// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
  ///
  /// MediationHelper.registerAdapter(
  ///   name: 'Unity Ads',
  ///   forwarder: ({required gdprConsent, required ccpaOptOut}) async {
  ///     GmaMediationUnity.setGDPRConsent(gdprConsent);
  ///     GmaMediationUnity.setCCPAConsent(!ccpaOptOut); // Note: inverted
  ///   },
  /// );
  /// ```
  ///
  /// Example for AppLovin:
  /// ```dart
  /// import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';
  ///
  /// MediationHelper.registerAdapter(
  ///   name: 'AppLovin',
  ///   forwarder: ({required gdprConsent, required ccpaOptOut}) async {
  ///     GmaMediationApplovin.setHasUserConsent(gdprConsent);
  ///     GmaMediationApplovin.setDoNotSell(ccpaOptOut);
  ///   },
  /// );
  /// ```
  static void registerAdapter({
    required String name,
    required MediationConsentForwarder forwarder,
  }) {
    _adapters[name] = forwarder;
    debugPrint('MediationHelper: Registered adapter "$name"');
  }

  /// Unregisters a mediation adapter.
  static void unregisterAdapter(String name) {
    _adapters.remove(name);
    debugPrint('MediationHelper: Unregistered adapter "$name"');
  }

  /// Unregisters all adapters.
  static void unregisterAll() {
    _adapters.clear();
    debugPrint('MediationHelper: Unregistered all adapters');
  }

  /// Forwards consent settings to all registered mediation networks.
  ///
  /// **Call this BEFORE [MobileAds.instance.initialize()].**
  ///
  /// Returns a [MediationForwardSummary] with results for each network.
  ///
  /// Example:
  /// ```dart
  /// final summary = await MediationHelper.forwardConsent(
  ///   MediationConsentConfig(
  ///     hasGdprConsent: true,
  ///     ccpaOptOut: false,
  ///   ),
  /// );
  /// print('Forwarded to ${summary.successful.length} networks');
  /// ```
  static Future<MediationForwardSummary> forwardConsent(
    MediationConsentConfig config,
  ) async {
    if (_adapters.isEmpty) {
      if (config.enableLogging) {
        debugPrint('MediationHelper: No adapters registered, skipping');
      }
      return MediationForwardSummary(results: [], timestamp: DateTime.now());
    }

    if (config.enableLogging) {
      debugPrint(
        'MediationHelper: Forwarding consent to ${_adapters.length} networks...',
      );
      debugPrint('  GDPR consent: ${config.hasGdprConsent}');
      debugPrint('  CCPA opt-out: ${config.ccpaOptOut}');
    }

    final results = <MediationForwardResult>[];

    for (final entry in _adapters.entries) {
      final name = entry.key;
      final forwarder = entry.value;

      try {
        await forwarder(
          gdprConsent: config.hasGdprConsent,
          ccpaOptOut: config.ccpaOptOut,
        );
        results.add(MediationForwardResult(networkName: name, success: true));
      } catch (e) {
        results.add(
          MediationForwardResult(
            networkName: name,
            success: false,
            error: e.toString(),
          ),
        );
      }
    }

    final summary = MediationForwardSummary(
      results: results,
      timestamp: DateTime.now(),
    );

    if (config.enableLogging) {
      debugPrint(summary.toString());
    }

    return summary;
  }

  /// Convenience method to register Unity Ads adapter.
  ///
  /// **Requires:** `gma_mediation_unity` package in pubspec.yaml
  ///
  /// Usage:
  /// ```dart
  /// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
  ///
  /// final unity = GmaMediationUnity();
  /// MediationHelper.registerUnityWithCallbacks(
  ///   setGDPRConsent: unity.setGDPRConsent,
  ///   setCCPAConsent: unity.setCCPAConsent,
  /// );
  /// ```
  ///
  /// This is equivalent to:
  /// ```dart
  /// MediationHelper.registerAdapter(
  ///   name: 'Unity Ads',
  ///   forwarder: ({required gdprConsent, required ccpaOptOut}) async {
  ///     await unity.setGDPRConsent(gdprConsent);
  ///     await unity.setCCPAConsent(!ccpaOptOut);
  ///   },
  /// );
  /// ```
  static void registerUnityWithCallbacks({
    required Future<void> Function(bool) setGDPRConsent,
    required Future<void> Function(bool) setCCPAConsent,
  }) {
    registerAdapter(
      name: 'Unity Ads',
      forwarder: ({required gdprConsent, required ccpaOptOut}) async {
        await setGDPRConsent(gdprConsent);
        await setCCPAConsent(
          !ccpaOptOut,
        ); // CCPA: true = consent given (inverted)
      },
    );
  }

  /// Convenience method to register AppLovin adapter.
  ///
  /// **Requires:** `gma_mediation_applovin` package in pubspec.yaml
  ///
  /// Usage:
  /// ```dart
  /// import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';
  ///
  /// final applovin = GmaMediationApplovin();
  /// MediationHelper.registerApplovinWithCallbacks(
  ///   setHasUserConsent: applovin.setHasUserConsent,
  ///   setDoNotSell: applovin.setDoNotSell,
  /// );
  /// ```
  static void registerApplovinWithCallbacks({
    required Future<void> Function(bool) setHasUserConsent,
    required Future<void> Function(bool) setDoNotSell,
  }) {
    registerAdapter(
      name: 'AppLovin',
      forwarder: ({required gdprConsent, required ccpaOptOut}) async {
        await setHasUserConsent(gdprConsent);
        await setDoNotSell(ccpaOptOut);
      },
    );
  }

  /// Resets all state (useful for testing).
  @visibleForTesting
  static void reset() {
    _adapters.clear();
  }
}
