import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ad_flow_error.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'explainer_content.dart';

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
  ///
  /// The remaining parameters are the **opt-in** pre-consent / pre-ATT
  /// priming ("explainer") flow. All are optional and additive:
  ///
  /// - [attExplainer] — presents the app's ATT primer before Apple's system
  ///   tracking prompt (client-driven ATT, iOS). When non-null the flow runs
  ///   ATT *first* (primer → [attPromptDelay] → system prompt), then GDPR.
  ///   When null, no ATT call is made at all — behaviour is exactly as
  ///   before (UMP-driven / console-configured).
  /// - [consentExplainer] — presents the app's consent primer before the UMP
  ///   GDPR form, but **only when a form will actually appear** (non-EEA
  ///   users never see it).
  /// - [consentExplainerContent] / [attExplainerContent] — the copy passed to
  ///   the respective presenters (localize by overriding).
  /// - [attPromptDelay] — brief pause between the ATT primer and the system
  ///   prompt (Apple's guidance; default 200 ms).
  /// - [skipGdprConsentIfAttDenied] — when the user is prompted for ATT and
  ///   denies it, skip showing the GDPR form (default true, matching v1).
  ///   The consent info update still runs; only the form is skipped.
  UmpConsentGateway(
    this._sdk, {
    bool? tagForUnderAgeOfConsent,
    Duration infoUpdateTimeout = const Duration(seconds: 30),
    ConsentExplainerPresenter? consentExplainer,
    AttExplainerPresenter? attExplainer,
    ConsentExplainerContent consentExplainerContent =
        const ConsentExplainerContent(),
    AttExplainerContent attExplainerContent = const AttExplainerContent(),
    Duration attPromptDelay = const Duration(milliseconds: 200),
    bool skipGdprConsentIfAttDenied = true,
  }) : _tagForUnderAgeOfConsent = tagForUnderAgeOfConsent,
       _infoUpdateTimeout = infoUpdateTimeout,
       _consentExplainer = consentExplainer,
       _attExplainer = attExplainer,
       _consentExplainerContent = consentExplainerContent,
       _attExplainerContent = attExplainerContent,
       _attPromptDelay = attPromptDelay,
       _skipGdprConsentIfAttDenied = skipGdprConsentIfAttDenied;

  final AdSdk _sdk;
  final bool? _tagForUnderAgeOfConsent;
  final Duration _infoUpdateTimeout;
  final ConsentExplainerPresenter? _consentExplainer;
  final AttExplainerPresenter? _attExplainer;
  final ConsentExplainerContent _consentExplainerContent;
  final AttExplainerContent _attExplainerContent;
  final Duration _attPromptDelay;
  final bool _skipGdprConsentIfAttDenied;

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
    // Step 1 — client-driven ATT (opt-in; iOS only in practice). Runs before
    // GDPR, matching v1. Returns whether the user was just prompted and
    // denied, so we can optionally skip the GDPR form below.
    final attDenied = await _maybeRunAtt();
    try {
      // Step 2 — consent info update (unchanged; still runs even when ATT was
      // denied, because canRequestAds()/privacy status depend on it).
      await _sdk
          .requestConsentInfoUpdate(
            tagForUnderAgeOfConsent: _tagForUnderAgeOfConsent,
            debug: debug,
          )
          .timeout(_infoUpdateTimeout);
      await _refreshPrivacyRequirement();
      // Step 3 — GDPR consent form, unless ATT-denial suppressed it.
      if (!(attDenied && _skipGdprConsentIfAttDenied)) {
        // Prime only when a form will actually appear (v2 improvement over
        // v1's blanket flag: non-EEA users never see a pointless dialog).
        await _maybeShowConsentPrimer();
        // The plugin no-ops internally when no form is required, so this is
        // safe to call unconditionally (mirrors Google's sample flow).
        await _sdk.loadAndShowConsentFormIfRequired();
        // Form dismissal can change both statuses.
        await _refreshPrivacyRequirement();
      }
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

  /// Runs the client-driven ATT flow when [_attExplainer] is set and the
  /// status is [AttStatus.notDetermined]: the app's primer, Apple's
  /// recommended [_attPromptDelay], then the system prompt. Returns whether
  /// the resulting status is [AttStatus.denied] (only meaningful for a fresh
  /// prompt — a previously-decided or unsupported status returns false and
  /// never skips GDPR).
  ///
  /// A throwing presenter is caught and recorded on [lastError]; the real
  /// system prompt still fires — a broken primer must never block ATT.
  Future<bool> _maybeRunAtt() async {
    final attExplainer = _attExplainer;
    if (attExplainer == null) return false; // opt-in: no ATT at all
    final AttStatus status;
    try {
      status = await _sdk.getTrackingAuthorizationStatus();
    } on AdFlowError catch (e) {
      _lastError = e;
      return false;
    }
    // Only iOS 14+ with an undetermined status can show the system prompt.
    if (status != AttStatus.notDetermined) return false;
    try {
      await attExplainer(_attExplainerContent);
    } catch (e) {
      _recordPresenterError(e);
    }
    await Future<void>.delayed(_attPromptDelay);
    try {
      final result = await _sdk.requestTrackingAuthorization();
      return result == AttStatus.denied;
    } on AdFlowError catch (e) {
      _lastError = e;
      return false;
    }
  }

  /// Presents the consent primer when [_consentExplainer] is set and a GDPR
  /// form will actually appear. A throwing presenter is caught and recorded;
  /// the real form still follows.
  Future<void> _maybeShowConsentPrimer() async {
    final consentExplainer = _consentExplainer;
    if (consentExplainer == null) return;
    if (!await _willConsentFormShow()) return;
    try {
      await consentExplainer(_consentExplainerContent);
    } catch (e) {
      _recordPresenterError(e);
    }
  }

  /// Whether `loadAndShowConsentFormIfRequired` will actually display a form:
  /// consent is required *and* a form is available. Best-effort — if the
  /// status can't be read, returns false (skip the primer, not the form).
  Future<bool> _willConsentFormShow() async {
    try {
      final status = await _sdk.getConsentStatus();
      if (status != AdConsentStatus.required) return false;
      return await _sdk.isConsentFormAvailable();
    } on AdFlowError {
      return false;
    }
  }

  void _recordPresenterError(Object error) {
    _lastError = error is AdFlowError
        ? error
        : AdFlowError(
            AdFlowErrorKind.consent,
            'Explainer presenter threw: $error',
          );
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
