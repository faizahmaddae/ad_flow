// Copyright 2024 - AdMob Integration Package
// Centralized error handling for ad operations

import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Types of ad operations that can produce errors.
///
/// Used to categorize errors from different ad operations,
/// enabling targeted error handling and analytics.
enum AdErrorType {
  /// Error during consent gathering
  consent,

  /// Error loading a banner ad
  bannerLoad,

  /// Error loading an interstitial ad
  interstitialLoad,

  /// Error showing an interstitial ad
  interstitialShow,

  /// Error loading an app open ad
  appOpenLoad,

  /// Error showing an app open ad
  appOpenShow,

  /// Error loading a rewarded ad
  rewardedLoad,

  /// Error showing a rewarded ad
  rewardedShow,

  /// Error loading a native ad
  nativeLoad,

  /// Error initializing the Mobile Ads SDK
  sdkInitialization,

  /// General/unknown error
  unknown,
}

/// Represents an error that occurred during an ad operation.
///
/// Use this class to handle errors from any ad type in a unified way:
/// ```dart
/// AdFlow.instance.errorStream.listen((error) {
///   analytics.logEvent('ad_error', {
///     'type': error.type.name,
///     'code': error.code,
///     'message': error.message,
///   });
/// });
/// ```
class AdFlowError {
  /// The type of ad operation that failed
  final AdErrorType type;

  /// Error code from the Google Mobile Ads SDK, or -1 for custom errors.
  final int code;

  /// Human-readable error message.
  final String message;

  /// The ad unit ID that was being used (if applicable)
  final String? adUnitId;

  /// The original error object (if available)
  final Object? originalError;

  /// When the error occurred
  final DateTime timestamp;

  AdFlowError({
    required this.type,
    required this.code,
    required this.message,
    this.adUnitId,
    this.originalError,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create from a Google Mobile Ads LoadAdError
  factory AdFlowError.fromLoadAdError(
    LoadAdError error, {
    required AdErrorType type,
    String? adUnitId,
  }) {
    return AdFlowError(
      type: type,
      code: error.code,
      message: error.message,
      adUnitId: adUnitId,
      originalError: error,
    );
  }

  /// Create from a Google Mobile Ads FormError (consent)
  factory AdFlowError.fromFormError(
    FormError error, {
    AdErrorType type = AdErrorType.consent,
  }) {
    return AdFlowError(
      type: type,
      code: error.errorCode,
      message: error.message,
      originalError: error,
    );
  }

  /// Create from a generic exception
  factory AdFlowError.fromException(
    Object error, {
    required AdErrorType type,
    String? adUnitId,
  }) {
    return AdFlowError(
      type: type,
      code: -1,
      message: error.toString(),
      adUnitId: adUnitId,
      originalError: error,
    );
  }

  @override
  String toString() {
    return 'AdFlowError(type: ${type.name}, code: $code, message: $message'
        '${adUnitId != null ? ', adUnitId: $adUnitId' : ''})';
  }
}

/// Callback type for ad errors
typedef AdFlowErrorCallback = void Function(AdFlowError error);

/// Manages centralized error handling for all ad operations.
///
/// This class provides both a stream and callback-based approach for
/// handling errors from any ad type.
///
/// ## Stream-based (reactive):
/// ```dart
/// AdFlowErrorHandler.instance.errorStream.listen((error) {
///   print('Ad error: ${error.type} - ${error.message}');
/// });
/// ```
///
/// ## Callback-based:
/// ```dart
/// AdFlowErrorHandler.instance.setErrorCallback((error) {
///   analytics.logError('ad_error', error.message);
/// });
/// ```
class AdFlowErrorHandler {
  AdFlowErrorHandler._();
  static final AdFlowErrorHandler _instance = AdFlowErrorHandler._();

  /// Singleton instance
  static AdFlowErrorHandler get instance => _instance;

  /// StreamController for error events
  final StreamController<AdFlowError> _errorController =
      StreamController<AdFlowError>.broadcast();

  /// Optional callback for errors
  AdFlowErrorCallback? _errorCallback;

  /// Stream of all ad errors
  ///
  /// Subscribe to receive all ad-related errors:
  /// ```dart
  /// AdFlowErrorHandler.instance.errorStream.listen((error) {
  ///   // Handle error
  /// });
  /// ```
  Stream<AdFlowError> get errorStream => _errorController.stream;

  /// Sets a callback to be invoked on every error.
  ///
  /// This is an alternative to using the stream.
  /// ```dart
  /// AdFlowErrorHandler.instance.setErrorCallback((error) {
  ///   logToAnalytics(error);
  /// });
  /// ```
  void setErrorCallback(AdFlowErrorCallback? callback) {
    _errorCallback = callback;
  }

  /// Reports an error to both the stream and callback.
  ///
  /// Called internally by ad managers. Can also be called directly:
  /// ```dart
  /// AdFlowErrorHandler.instance.reportError(AdFlowError(
  ///   type: AdErrorType.unknown,
  ///   code: 999,
  ///   message: 'Custom error',
  /// ));
  /// ```
  void reportError(AdFlowError error) {
    // Add to stream
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }

    // Call callback if set
    _errorCallback?.call(error);
  }

  /// Reports a LoadAdError with the appropriate type.
  void reportLoadError(
    LoadAdError error, {
    required AdErrorType type,
    String? adUnitId,
  }) {
    reportError(
      AdFlowError.fromLoadAdError(error, type: type, adUnitId: adUnitId),
    );
  }

  /// Reports a consent FormError.
  void reportConsentError(FormError error) {
    reportError(AdFlowError.fromFormError(error));
  }

  /// Reports a generic exception.
  void reportException(
    Object error, {
    required AdErrorType type,
    String? adUnitId,
  }) {
    reportError(
      AdFlowError.fromException(error, type: type, adUnitId: adUnitId),
    );
  }

  /// Clears the error callback.
  void clearErrorCallback() {
    _errorCallback = null;
  }

  /// Disposes of resources.
  void dispose() {
    _errorController.close();
    _errorCallback = null;
  }

  /// Resets for testing purposes.
  void reset() {
    _errorCallback = null;
    // Note: We don't close the controller, just clear callback
  }
}
