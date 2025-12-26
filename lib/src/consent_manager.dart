// Copyright 2024 - AdMob Integration Package
// Consent Manager for GDPR, US Privacy, and iOS ATT compliance
// Simplified to match Google's official samples

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'consent_explainer_dialog.dart';

/// Callback signature for consent gathering completion
typedef ConsentCallback = void Function(FormError? error);

/// Manages user consent for personalized advertising.
///
/// This class handles:
/// - GDPR consent for EEA, UK, and Switzerland users
/// - US state privacy regulations (CCPA, etc.)
/// - iOS App Tracking Transparency (ATT)
///
/// Uses Google's User Messaging Platform (UMP) SDK which is
/// IAB certified for consent management.
///
/// Based on Google's official samples:
/// https://github.com/googleads/googleads-mobile-flutter/tree/main/samples
class ConsentManager {
  ConsentManager._();
  static final ConsentManager _instance = ConsentManager._();

  /// Singleton instance of ConsentManager
  static ConsentManager get instance => _instance;

  /// Delay before showing ATT prompt (recommended by Apple)
  static const Duration _kATTPromptDelay = Duration(milliseconds: 200);

  bool _isInitialized = false;
  bool _canRequestAds = false;
  bool _isPrivacyOptionsRequired = false;

  /// Whether consent has been initialized
  bool get isInitialized => _isInitialized;

  /// Whether ads can be requested based on consent status
  bool get canRequestAds => _canRequestAds;

  /// Gathers user consent if required.
  ///
  /// Flow (strictly sequential):
  /// 1. iOS only: Check ATT status, request if not determined
  /// 2. Request consent info update from UMP
  /// 3. UMP automatically shows form if required (GDPR regions)
  ///
  /// [onConsentGatheringComplete] is called when the process completes,
  /// with an optional [FormError] if something went wrong.
  ///
  /// Example:
  /// ```dart
  /// await ConsentManager.instance.gatherConsent(
  ///   onConsentGatheringComplete: (error) {
  ///     if (error != null) {
  ///       debugPrint('Consent error: ${error.message}');
  ///     }
  ///     // Proceed to load ads
  ///   },
  /// );
  /// ```
  Future<void> gatherConsent({
    required ConsentCallback onConsentGatheringComplete,
  }) async {
    debugPrint('ConsentManager: Starting consent gathering...');

    // Step 1: iOS ATT - request only if not determined
    if (Platform.isIOS) {
      await _requestIOSTrackingIfNeeded();
    }

    // Step 2: UMP consent flow (GDPR/US Privacy)
    _gatherUMPConsent(onConsentGatheringComplete);
  }

  /// Gathers consent WITH optional pre-consent explainer dialogs.
  ///
  /// For each consent type, the flow is:
  /// 1. Check if consent is needed
  /// 2. If needed, show explainer dialog
  /// 3. Then show system/Google consent prompt
  ///
  /// All popups are strictly sequential (awaited) to prevent stacking.
  ///
  /// [context] is required to show dialogs.
  /// [showExplainer] if false, skips explainers (same as gatherConsent).
  /// [consentTexts] custom texts for GDPR explainer.
  /// [attTexts] custom texts for iOS ATT explainer.
  Future<void> gatherConsentWithExplainer({
    required BuildContext context,
    required ConsentCallback onConsentGatheringComplete,
    bool showExplainer = true,
    ConsentExplainerTexts consentTexts = kDefaultConsentExplainerTexts,
    ATTExplainerTexts attTexts = kDefaultATTExplainerTexts,
  }) async {
    debugPrint('ConsentManager: Starting consent gathering with explainer...');

    // Step 1: iOS ATT flow (check → explainer → prompt) - sequential
    if (Platform.isIOS) {
      await _handleIOSATTWithExplainer(
        context: context,
        showExplainer: showExplainer,
        attTexts: attTexts,
      );
    }

    // Step 2: GDPR/US Privacy flow (check → explainer → form) - sequential
    // Check if context is still valid after iOS ATT flow
    if (!context.mounted) {
      debugPrint('ConsentManager: Context no longer mounted, aborting');
      return;
    }

    await _handleUMPConsentWithExplainer(
      context: context,
      showExplainer: showExplainer,
      consentTexts: consentTexts,
      onComplete: onConsentGatheringComplete,
    );
  }

  // ==========================================================================
  // iOS ATT Handling
  // ==========================================================================

  /// Requests iOS ATT permission only if not already determined.
  Future<void> _requestIOSTrackingIfNeeded() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      debugPrint('ConsentManager: ATT status: $status');

      if (status == TrackingStatus.notDetermined) {
        // Small delay recommended by Apple before showing ATT prompt
        await Future.delayed(_kATTPromptDelay);
        final result =
            await AppTrackingTransparency.requestTrackingAuthorization();
        debugPrint('ConsentManager: ATT result: $result');
      }
    } catch (e) {
      debugPrint('ConsentManager: ATT error: $e');
    }
  }

  /// Handles iOS ATT with optional explainer dialog.
  /// Sequential: check needed → show explainer → show system prompt
  Future<void> _handleIOSATTWithExplainer({
    required BuildContext context,
    required bool showExplainer,
    required ATTExplainerTexts attTexts,
  }) async {
    try {
      // Step 1: Check if ATT is needed
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      debugPrint('ConsentManager: ATT status: $status');

      if (status != TrackingStatus.notDetermined) {
        debugPrint('ConsentManager: ATT already determined, skipping');
        return;
      }

      // Step 2: Show explainer if enabled and context is valid
      if (showExplainer && context.mounted) {
        debugPrint('ConsentManager: Showing ATT explainer...');
        await ATTExplainerDialog.show(context, texts: attTexts);
      }

      // Step 3: Show system ATT prompt
      await Future.delayed(_kATTPromptDelay);
      final result =
          await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('ConsentManager: ATT result: $result');
    } catch (e) {
      debugPrint('ConsentManager: ATT error: $e');
    }
  }

  // ==========================================================================
  // UMP Consent Handling (GDPR/US Privacy)
  // ==========================================================================

  /// Standard UMP consent flow (matches Google's sample).
  void _gatherUMPConsent(ConsentCallback onComplete) {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: AdFlowConfig.current.tagForUnderAgeOfConsent,
      consentDebugSettings: _buildDebugSettings(),
    );

    // Request consent info update, then load/show form if required
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        // loadAndShowConsentFormIfRequired handles the "if required" logic
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) async {
          await _updateCanRequestAds();
          _isInitialized = true;
          onComplete(error);
        });
      },
      (FormError error) async {
        debugPrint('ConsentManager: Consent update failed: ${error.message}');
        AdFlowErrorHandler.instance.reportConsentError(error);
        await _updateCanRequestAds();
        _isInitialized = true;
        onComplete(error);
      },
    );
  }

  /// UMP consent flow with optional explainer dialog.
  /// Sequential: check needed → show explainer → request update → show form
  Future<void> _handleUMPConsentWithExplainer({
    required BuildContext context,
    required bool showExplainer,
    required ConsentExplainerTexts consentTexts,
    required ConsentCallback onComplete,
  }) async {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: AdFlowConfig.current.tagForUnderAgeOfConsent,
      consentDebugSettings: _buildDebugSettings(),
    );

    // Use Completer for the callback-based API
    final completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        // Step 1: Check if consent form will be shown
        final formStatus = await ConsentInformation.instance
            .isConsentFormAvailable();
        final consentStatus = await ConsentInformation.instance
            .getConsentStatus();
        final needsForm =
            formStatus &&
            (consentStatus == ConsentStatus.required ||
                consentStatus == ConsentStatus.unknown);

        // Step 2: Show explainer ONLY if form will be shown
        if (needsForm && showExplainer && context.mounted) {
          debugPrint('ConsentManager: Showing GDPR explainer...');
          await ConsentExplainerDialog.show(context, texts: consentTexts);
        }

        // Step 3: Show consent form if required
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) async {
          await _updateCanRequestAds();
          _isInitialized = true;
          onComplete(error);
          if (!completer.isCompleted) completer.complete();
        });
      },
      (FormError error) async {
        debugPrint('ConsentManager: Consent update failed: ${error.message}');
        AdFlowErrorHandler.instance.reportConsentError(error);
        await _updateCanRequestAds();
        _isInitialized = true;
        onComplete(error);
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  // ==========================================================================
  // Public API
  // ==========================================================================

  /// Gets the current iOS ATT status.
  Future<TrackingStatus> getIOSTrackingStatus() async {
    if (!Platform.isIOS) {
      return TrackingStatus.notSupported;
    }
    return await AppTrackingTransparency.trackingAuthorizationStatus;
  }

  /// Updates internal state for whether ads can be requested.
  Future<void> _updateCanRequestAds() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    _isPrivacyOptionsRequired =
        status == PrivacyOptionsRequirementStatus.required;
    debugPrint('ConsentManager: Can request ads: $_canRequestAds');
    debugPrint(
      'ConsentManager: Privacy options required: $_isPrivacyOptionsRequired',
    );
  }

  /// Checks if privacy options form is required (async).
  Future<bool> isPrivacyOptionsRequiredAsync() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  /// Checks if privacy options form is required (cached value).
  bool isPrivacyOptionsRequired() {
    return _isPrivacyOptionsRequired;
  }

  /// Shows the privacy options form for users to update consent.
  ///
  /// Call this from a "Privacy Settings" button in your app.
  void showPrivacyOptionsForm({required ConsentCallback onComplete}) {
    ConsentForm.showPrivacyOptionsForm((FormError? formError) async {
      if (formError != null) {
        debugPrint('ConsentManager: Privacy form error: ${formError.message}');
      }
      await _updateCanRequestAds();
      onComplete(formError);
    });
  }

  /// Resets consent information for testing purposes.
  ///
  /// WARNING: Only use during development/testing.
  void resetConsent() {
    debugPrint('ConsentManager: Resetting consent');
    ConsentInformation.instance.reset();
    _isInitialized = false;
    _canRequestAds = false;
    _isPrivacyOptionsRequired = false;
  }

  /// Gets the current consent status.
  Future<ConsentStatus> getConsentStatus() async {
    return await ConsentInformation.instance.getConsentStatus();
  }

  /// Gets a human-readable consent status description.
  Future<String> getConsentStatusDescription() async {
    final status = await getConsentStatus();
    switch (status) {
      case ConsentStatus.unknown:
        return 'Consent status is unknown';
      case ConsentStatus.notRequired:
        return 'Consent not required (non-GDPR region)';
      case ConsentStatus.required:
        return 'Consent required but not yet obtained';
      case ConsentStatus.obtained:
        return 'Consent has been obtained';
    }
  }

  /// Builds debug settings for consent testing.
  ConsentDebugSettings? _buildDebugSettings() {
    if (!AdFlowConfig.current.enableConsentDebug || kReleaseMode) {
      return null;
    }

    debugPrint('ConsentManager: Using debug settings');
    return ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
      testIdentifiers: AdFlowConfig.current.testDeviceIds,
    );
  }
}
