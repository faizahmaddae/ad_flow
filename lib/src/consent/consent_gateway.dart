import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ad_flow_error.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';

/// Gathers user consent and answers the one question that gates every ad
/// load: may ads be requested?
///
/// Implementations wrap the UMP flow exactly once (v1 trap: don't fight the
/// callback API) — callers just `await` [ensureCanRequestAds].
abstract interface class ConsentGateway {
  /// Runs the consent flow (info update → consent form if required) and
  /// resolves to whether ads may be requested.
  ///
  /// Call once per app launch, before any ad load. Concurrent calls join
  /// the in-flight run — the flow never executes twice at once, which also
  /// guards against double-triggered preloads.
  Future<bool> ensureCanRequestAds({ConsentDebugOptions? debug});

  /// Whether the app must surface a persistent "Manage consent" control
  /// (GDPR: EEA + UK + Switzerland). Valid after [ensureCanRequestAds].
  bool get isPrivacyOptionsRequired;

  /// Reactive view of [isPrivacyOptionsRequired].
  ///
  /// A widget rendered before the first [ensureCanRequestAds] resolves (or
  /// live across a later re-check) must still end up showing the entry
  /// point once the requirement becomes true — a plain bool getter read
  /// once at build time cannot do that (invariant 2). Subscribe to this
  /// instead of polling [isPrivacyOptionsRequired].
  ValueListenable<bool> get privacyOptionsRequired;

  /// Shows the privacy-options form. Throws an [AdFlowError] (kind
  /// `consent`) if the form fails.
  Future<void> showPrivacyOptions();

  /// The error swallowed by the most recent [ensureCanRequestAds] run, if
  /// any. The flow degrades to a `canRequestAds()` check instead of
  /// throwing (a user who consented previously should still get ads when
  /// the network drops) — but the failure is surfaced here, never silently
  /// discarded.
  AdFlowError? get lastError;

  /// Resets UMP consent state. Testing only — never call in production.
  Future<void> reset();

  /// Releases the [privacyOptionsRequired] notifier.
  void dispose();
}

/// The production [ConsentGateway]: orchestrates the seam's UMP primitives.
class UmpConsentGateway implements ConsentGateway {
  /// Creates a gateway over the given [AdSdk].
  ///
  /// [tagForUnderAgeOfConsent] is forwarded to every consent info update.
  /// [infoUpdateTimeout] bounds the network-bound info-update step only —
  /// the consent form itself has no timeout, because the user may
  /// legitimately keep it open for minutes.
  UmpConsentGateway(
    this._sdk, {
    bool? tagForUnderAgeOfConsent,
    Duration infoUpdateTimeout = const Duration(seconds: 30),
  }) : _tagForUnderAgeOfConsent = tagForUnderAgeOfConsent,
       _infoUpdateTimeout = infoUpdateTimeout;

  final AdSdk _sdk;
  final bool? _tagForUnderAgeOfConsent;
  final Duration _infoUpdateTimeout;

  Future<bool>? _inFlight;
  final ValueNotifier<bool> _privacyOptionsRequired = ValueNotifier(false);
  AdFlowError? _lastError;

  @override
  bool get isPrivacyOptionsRequired => _privacyOptionsRequired.value;

  @override
  ValueListenable<bool> get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  AdFlowError? get lastError => _lastError;

  @override
  Future<bool> ensureCanRequestAds({ConsentDebugOptions? debug}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final run = _run(debug).whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<bool> _run(ConsentDebugOptions? debug) async {
    _lastError = null;
    try {
      await _sdk
          .requestConsentInfoUpdate(
            tagForUnderAgeOfConsent: _tagForUnderAgeOfConsent,
            debug: debug,
          )
          .timeout(_infoUpdateTimeout);
      await _refreshPrivacyRequirement();
      // The plugin no-ops internally when no form is required, so this is
      // safe to call unconditionally (mirrors Google's sample flow).
      await _sdk.loadAndShowConsentFormIfRequired();
      // Form dismissal can change both statuses.
      await _refreshPrivacyRequirement();
    } on TimeoutException {
      _lastError = AdFlowError(
        AdFlowErrorKind.timeout,
        'Consent info update timed out after '
        '${_infoUpdateTimeout.inSeconds}s.',
      );
    } on AdFlowError catch (e) {
      _lastError = e;
    }
    // Degrade to the SDK's own answer: consent obtained on a previous
    // launch (or not required at all) keeps serving ads through transient
    // consent-flow failures.
    return _sdk.canRequestAds();
  }

  Future<void> _refreshPrivacyRequirement() async {
    try {
      final status = await _sdk.getPrivacyOptionsRequirementStatus();
      _privacyOptionsRequired.value =
          status == PrivacyOptionsRequirement.required;
    } on AdFlowError {
      // Keep the previous value; requirement status is best-effort.
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    await _sdk.showPrivacyOptionsForm();
    await _refreshPrivacyRequirement();
  }

  @override
  Future<void> reset() => _sdk.resetConsent();

  @override
  void dispose() => _privacyOptionsRequired.dispose();
}
