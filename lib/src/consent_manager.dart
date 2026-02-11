// Copyright 2024 - AdMob Integration Package
// Consent Manager for GDPR, US Privacy, and iOS ATT compliance
// Simplified to match Google's official samples

import 'dart:async';
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';
import 'ad_error_handler.dart';
import 'ad_sdk.dart';
import 'consent_explainer_dialog.dart';
import 'ad_flow_logger.dart';

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
  TrackingStatus? _lastAttStatus;

  /// Whether consent has been initialized
  bool get isInitialized => _isInitialized;

  /// Whether ads can be requested based on consent status
  bool get canRequestAds => _canRequestAds;

  /// The last known iOS ATT status (null on non-iOS or if not yet checked)
  TrackingStatus? get lastAttStatus => _lastAttStatus;

  /// Whether ATT was denied (user selected "Ask App Not to Track")
  bool get isAttDenied =>
      _lastAttStatus == TrackingStatus.denied ||
      _lastAttStatus == TrackingStatus.restricted;

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
  ///       adFlowLog('Consent error: ${error.message}');
  ///     }
  ///     // Proceed to load ads
  ///   },
  /// );
  /// ```
  Future<void> gatherConsent({
    required ConsentCallback onConsentGatheringComplete,
  }) async {
    adFlowLog('ConsentManager: Starting consent gathering...');

    // Step 1: iOS ATT - request only if not determined
    if (AdFlowPlatform.isIOS) {
      _lastAttStatus = await _requestIOSTrackingIfNeeded();

      // Check if we should skip GDPR consent after ATT denial
      if (_shouldSkipGdprConsent()) {
        adFlowLog(
          'ConsentManager: Skipping GDPR consent (ATT denied, skipGdprConsentIfAttDenied=true)',
        );
        await _updateCanRequestAds();
        _isInitialized = true;
        onConsentGatheringComplete(null);
        return;
      }
    }

    // Step 2: UMP consent flow (GDPR/US Privacy)
    await _gatherUMPConsent(onConsentGatheringComplete);
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
    adFlowLog('ConsentManager: Starting consent gathering with explainer...');

    // Step 1: iOS ATT flow (check → explainer → prompt) - sequential
    if (AdFlowPlatform.isIOS) {
      _lastAttStatus = await _handleIOSATTWithExplainer(
        context: context,
        showExplainer: showExplainer,
        attTexts: attTexts,
      );

      // Check if we should skip GDPR consent after ATT denial
      if (_shouldSkipGdprConsent()) {
        adFlowLog(
          'ConsentManager: Skipping GDPR consent (ATT denied, skipGdprConsentIfAttDenied=true)',
        );
        await _updateCanRequestAds();
        _isInitialized = true;
        onConsentGatheringComplete(null);
        return;
      }
    }

    // Step 2: GDPR/US Privacy flow (check → explainer → form) - sequential
    // Check if context is still valid after iOS ATT flow
    if (!context.mounted) {
      adFlowLog(
        'ConsentManager: Context no longer mounted, completing with error',
      );
      // P0 FIX: Always call the callback, even when context is unmounted
      await _updateCanRequestAds();
      _isInitialized = true;
      onConsentGatheringComplete(
        FormError(errorCode: -1, message: 'Context unmounted during consent'),
      );
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

  /// Checks if GDPR consent should be skipped based on ATT status and config.
  bool _shouldSkipGdprConsent() {
    if (!AdFlowPlatform.isIOS) return false;
    if (!AdFlowConfig.current.skipGdprConsentIfAttDenied) return false;
    return isAttDenied;
  }

  /// Requests iOS ATT permission only if not already determined.
  /// Returns the final ATT status.
  Future<TrackingStatus> _requestIOSTrackingIfNeeded() async {
    try {
      var status = await AdSdk.instance.getTrackingAuthorizationStatus();
      adFlowLog('ConsentManager: ATT status: $status');

      if (status == TrackingStatus.notDetermined) {
        // Small delay recommended by Apple before showing ATT prompt
        await Future.delayed(_kATTPromptDelay);
        status = await AdSdk.instance.requestTrackingAuthorization();
        adFlowLog('ConsentManager: ATT result: $status');
      }
      return status;
    } catch (e) {
      adFlowLog('ConsentManager: ATT error: $e');
      return TrackingStatus.notSupported;
    }
  }

  /// Handles iOS ATT with optional explainer dialog.
  /// Sequential: check needed → show explainer → show system prompt
  /// Returns the final ATT status.
  Future<TrackingStatus> _handleIOSATTWithExplainer({
    required BuildContext context,
    required bool showExplainer,
    required ATTExplainerTexts attTexts,
  }) async {
    try {
      // Step 1: Check if ATT is needed
      var status = await AdSdk.instance.getTrackingAuthorizationStatus();
      adFlowLog('ConsentManager: ATT status: $status');

      if (status != TrackingStatus.notDetermined) {
        adFlowLog('ConsentManager: ATT already determined, skipping');
        return status;
      }

      // Step 2: Show explainer if enabled and context is valid
      if (showExplainer && context.mounted) {
        adFlowLog('ConsentManager: Showing ATT explainer...');
        await ATTExplainerDialog.show(context, texts: attTexts);
      }

      // Step 3: Show system ATT prompt
      await Future.delayed(_kATTPromptDelay);
      status = await AdSdk.instance.requestTrackingAuthorization();
      adFlowLog('ConsentManager: ATT result: $status');
      return status;
    } catch (e) {
      adFlowLog('ConsentManager: ATT error: $e');
      return TrackingStatus.notSupported;
    }
  }

  // ==========================================================================
  // UMP Consent Handling (GDPR/US Privacy)
  // ==========================================================================

  /// Core UMP consent flow, shared by both simple and explainer paths.
  ///
  /// [onBeforeForm] is called after the consent info update succeeds
  /// but before the consent form is shown. The explainer path uses this to check
  /// if the form is needed and show an explainer dialog first.
  /// [onComplete] is the final consent callback.
  ///
  /// Returns a Future that completes when the entire flow finishes.
  Future<void> _executeUMPConsentFlow({
    required ConsentCallback onComplete,
    Future<void> Function()? onBeforeForm,
  }) async {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: AdFlowConfig.current.tagForUnderAgeOfConsent,
      consentDebugSettings: _buildDebugSettings(),
    );

    final completer = Completer<void>();

    Future<void> completeWithForm() async {
      // Run pre-form hook (e.g. show explainer) if provided
      if (onBeforeForm != null) {
        await onBeforeForm();
      }

      // loadAndShowConsentFormIfRequired handles the "if required" logic
      AdSdk.instance.loadAndShowConsentFormIfRequired((FormError? error) async {
        try {
          await _updateCanRequestAds();
          _isInitialized = true;
          onComplete(error);
        } catch (e) {
          adFlowLog('ConsentManager: Error in consent form callback: $e');
          _isInitialized = true;
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      });
    }

    Future<void> completeWithError(FormError error) async {
      try {
        adFlowLog('ConsentManager: Consent update failed: ${error.message}');
        AdFlowErrorHandler.instance.reportConsentError(error);
        await _updateCanRequestAds();
        _isInitialized = true;
        onComplete(error);
      } catch (e) {
        adFlowLog('ConsentManager: Error in consent error callback: $e');
        _isInitialized = true;
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }

    // Request consent info update, then load/show form if required
    AdSdk.instance.requestConsentInfoUpdate(
      params,
      () async {
        await completeWithForm();
      },
      (FormError error) async {
        await completeWithError(error);
      },
    );

    return completer.future;
  }

  /// Standard UMP consent flow.
  Future<void> _gatherUMPConsent(ConsentCallback onComplete) {
    return _executeUMPConsentFlow(onComplete: onComplete);
  }

  /// UMP consent flow with optional explainer dialog.
  /// Sequential: check needed → show explainer → request update → show form
  Future<void> _handleUMPConsentWithExplainer({
    required BuildContext context,
    required bool showExplainer,
    required ConsentExplainerTexts consentTexts,
    required ConsentCallback onComplete,
  }) {
    return _executeUMPConsentFlow(
      onComplete: onComplete,
      onBeforeForm: () async {
        // Check if consent form will be shown
        final formStatus = await AdSdk.instance.isConsentFormAvailable();
        final consentStatus = await AdSdk.instance.getConsentStatus();
        final needsForm =
            formStatus &&
            (consentStatus == ConsentStatus.required ||
                consentStatus == ConsentStatus.unknown);

        // Show explainer ONLY if form will be shown
        if (needsForm && showExplainer && context.mounted) {
          adFlowLog('ConsentManager: Showing GDPR explainer...');
          await ConsentExplainerDialog.show(context, texts: consentTexts);
        }
      },
    );
  }

  // ==========================================================================
  // Public API
  // ==========================================================================

  /// Gets the current iOS ATT status.
  Future<TrackingStatus> getIOSTrackingStatus() async {
    if (!AdFlowPlatform.isIOS) {
      return TrackingStatus.notSupported;
    }
    return await AdSdk.instance.getTrackingAuthorizationStatus();
  }

  /// Gets the IAB TCF v2.0 consent string from SharedPreferences.
  ///
  /// The UMP SDK stores the TC string under the standard
  /// `IABTCF_TCString` key per the IAB specification. This is useful for:
  /// - Sending consent info to your analytics backend
  /// - Passing to third-party SDKs that don't auto-read it
  /// - Auditing consent for compliance purposes
  ///
  /// Returns `null` if no TC string has been stored (e.g. non-GDPR region
  /// or consent not yet gathered).
  ///
  /// See: https://github.com/InteractiveAdvertisingBureau/GDPR-Transparency-and-Consent-Framework
  Future<String?> getTCFConsentString() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('IABTCF_TCString');
  }

  /// Gets the IAB US Privacy string (CCPA) from SharedPreferences.
  ///
  /// Stored under the standard `IABUSPrivacy_String` key.
  /// Format: `1YNN` (version, notice, opt-out, LSPA).
  ///
  /// Returns `null` if no US Privacy string has been stored.
  Future<String?> getUSPrivacyString() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('IABUSPrivacy_String');
  }

  /// Updates internal state for whether ads can be requested.
  Future<void> _updateCanRequestAds() async {
    _canRequestAds = await AdSdk.instance.canRequestAds();
    final status = await AdSdk.instance.getPrivacyOptionsRequirementStatus();
    _isPrivacyOptionsRequired =
        status == PrivacyOptionsRequirementStatus.required;
    adFlowLog('ConsentManager: Can request ads: $_canRequestAds');
    adFlowLog(
      'ConsentManager: Privacy options required: $_isPrivacyOptionsRequired',
    );
  }

  /// Checks if privacy options form is required (async).
  Future<bool> isPrivacyOptionsRequiredAsync() async {
    final status = await AdSdk.instance.getPrivacyOptionsRequirementStatus();
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
    AdSdk.instance.showPrivacyOptionsForm((FormError? formError) async {
      if (formError != null) {
        adFlowLog('ConsentManager: Privacy form error: ${formError.message}');
      }
      await _updateCanRequestAds();
      onComplete(formError);
    });
  }

  /// Resets consent information for testing purposes.
  ///
  /// WARNING: Only use during development/testing.
  @visibleForTesting
  void resetConsent() {
    adFlowLog('ConsentManager: Resetting consent');
    AdSdk.instance.resetConsentInfo();
    _isInitialized = false;
    _canRequestAds = false;
    _isPrivacyOptionsRequired = false;
    _lastAttStatus = null;
  }

  /// Gets the current consent status.
  Future<ConsentStatus> getConsentStatus() async {
    return await AdSdk.instance.getConsentStatus();
  }

  /// Refreshes consent status and shows the consent form if needed.
  ///
  /// Call this periodically for long-running sessions to handle TCF consent
  /// expiration or changed regulatory status. This is safe to call multiple
  /// times — it only shows the consent form if the UMP SDK determines it is
  /// required (e.g., after a TCF string expires or in a new GDPR region).
  ///
  /// Unlike [gatherConsent], this does **not** re-trigger the iOS ATT prompt
  /// (ATT status is permanent per install) and does not show explainer dialogs.
  ///
  /// Returns `true` if ads can be requested after the refresh.
  ///
  /// Example:
  /// ```dart
  /// // Periodically re-check consent (e.g., every 24 hours)
  /// final canRequest = await ConsentManager.instance.refreshConsentIfNeeded();
  /// if (!canRequest) {
  ///   // Consent was revoked or expired — stop loading ads
  /// }
  /// ```
  Future<bool> refreshConsentIfNeeded() async {
    adFlowLog('ConsentManager: Refreshing consent status...');

    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: AdFlowConfig.current.tagForUnderAgeOfConsent,
      consentDebugSettings: _buildDebugSettings(),
    );

    final completer = Completer<bool>();

    AdSdk.instance.requestConsentInfoUpdate(
      params,
      () async {
        // Consent info updated — show form if required
        AdSdk.instance.loadAndShowConsentFormIfRequired((
          FormError? error,
        ) async {
          try {
            if (error != null) {
              adFlowLog(
                'ConsentManager: Consent refresh form error: ${error.message}',
              );
              AdFlowErrorHandler.instance.reportConsentError(error);
            }
            await _updateCanRequestAds();
            adFlowLog(
              'ConsentManager: Consent refresh complete. Can request ads: $_canRequestAds',
            );
          } catch (e) {
            adFlowLog('ConsentManager: Error in consent refresh callback: $e');
          } finally {
            if (!completer.isCompleted) completer.complete(_canRequestAds);
          }
        });
      },
      (FormError error) async {
        try {
          adFlowLog(
            'ConsentManager: Consent refresh update failed: ${error.message}',
          );
          AdFlowErrorHandler.instance.reportConsentError(error);
          await _updateCanRequestAds();
        } catch (e) {
          adFlowLog('ConsentManager: Error in consent refresh error path: $e');
        } finally {
          if (!completer.isCompleted) completer.complete(_canRequestAds);
        }
      },
    );

    return completer.future;
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

    adFlowLog('ConsentManager: Using debug settings');
    return ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
      testIdentifiers: AdFlowConfig.current.testDeviceIds,
    );
  }
}
