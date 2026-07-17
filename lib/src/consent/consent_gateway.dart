import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
  /// - [skipConsentPrimerIfAttDenied] — when the user is prompted for ATT and
  ///   denies it, skip the optional consent *primer* (default true). A
  ///   **required** GDPR form (EEA/UK/CH) is ALWAYS shown regardless: ATT
  ///   (Apple tracking) and GDPR (EU privacy) are independent regimes, so
  ///   denying tracking never satisfies — and never suppresses — a required
  ///   consent form. This flag is a UX optimization on the primer only; it
  ///   cannot override a required form.
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
    bool skipConsentPrimerIfAttDenied = true,
    Future<void> Function()? waitBeforePresenting,
  }) : _tagForUnderAgeOfConsent = tagForUnderAgeOfConsent,
       _infoUpdateTimeout = infoUpdateTimeout,
       _consentExplainer = consentExplainer,
       _attExplainer = attExplainer,
       _consentExplainerContent = consentExplainerContent,
       _attExplainerContent = attExplainerContent,
       _attPromptDelay = attPromptDelay,
       _skipConsentPrimerIfAttDenied = skipConsentPrimerIfAttDenied,
       _waitBeforePresenting = waitBeforePresenting ?? _waitForFirstFrame;

  /// Waits (bounded) for the app's first frame before presenting a primer.
  ///
  /// The consent flow starts in the background the moment `initialize()`
  /// runs (ADR-032) — on a fast device the ATT/consent primer can be reached
  /// BEFORE the navigator has mounted, and the presenter's own
  /// `navigatorKey.currentContext == null` guard then silently drops the
  /// primer on the one launch where it matters most (2026-07 audit). Bounded
  /// and best-effort: headless/test environments proceed immediately.
  static Future<void> _waitForFirstFrame() async {
    try {
      await WidgetsBinding.instance.waitUntilFirstFrameRasterized.timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      // No binding (plain Dart tests) or no frame within the bound — the
      // presenter's own context guard remains the fallback.
    }
  }

  final AdSdk _sdk;
  final bool? _tagForUnderAgeOfConsent;
  final Duration _infoUpdateTimeout;
  final ConsentExplainerPresenter? _consentExplainer;
  final AttExplainerPresenter? _attExplainer;
  final ConsentExplainerContent _consentExplainerContent;
  final AttExplainerContent _attExplainerContent;
  final Duration _attPromptDelay;
  final bool _skipConsentPrimerIfAttDenied;
  final Future<void> Function() _waitBeforePresenting;

  Future<bool>? _inFlight;
  final ValueNotifier<bool> _privacyOptionsRequired = ValueNotifier(false);
  AdFlowError? _lastError;
  bool _disposed = false;

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
    // denied, so we can optionally skip the consent PRIMER below.
    //
    // This is deliberately its own try/catch and NOT allowed to abort the
    // rest of the flow: ATT (Apple) and GDPR (EU) are independent regimes, so
    // an ATT failure must never suppress the required consent form. ADR-031
    // fixed the *policy* version of this (a DENIAL must not skip the form);
    // this is the *crash* version (an ATT platform throw must not skip it
    // either). Without it, a missing app_tracking_transparency channel or a
    // missing NSUserTrackingUsageDescription meant: no consent info update, no
    // GDPR form, no privacy-options entry point and zero ads for the session.
    var attDenied = false;
    try {
      attDenied = await _maybeRunAtt();
    } catch (e) {
      _lastError = asAdFlowError(e, AdFlowErrorKind.consent);
    }
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
      // Step 3a — the OPTIONAL consent primer. This soft screen is the only
      // thing an ATT denial may suppress (a UX optimization). It never gates
      // the form below.
      if (!(attDenied && _skipConsentPrimerIfAttDenied)) {
        // Prime only when a form will actually appear (v2 improvement over
        // v1's blanket flag: non-EEA users never see a pointless dialog).
        await _maybeShowConsentPrimer();
      }
      // Step 3b — the GDPR form itself. ALWAYS called: the plugin no-ops when
      // no form is required, and shows the REQUIRED form (EEA/UK/CH) otherwise.
      // This must never be gated on ATT — GDPR (EU) and ATT (Apple) are
      // independent regimes, so denying tracking neither satisfies nor
      // suppresses a required consent form. This line is the compliance
      // guarantee (ADR-031).
      await _sdk.loadAndShowConsentFormIfRequired();
      // Form dismissal can change both statuses.
      await _refreshPrivacyRequirement();
    } on TimeoutException {
      _lastError = AdFlowError(
        AdFlowErrorKind.timeout,
        'Consent info update timed out after '
        '${_infoUpdateTimeout.inSeconds}s.',
      );
    } catch (e) {
      // Any error kind, not just AdFlowError — the UMP channel can throw raw
      // PlatformExceptions, and one must not take the whole flow (and every
      // ad load behind it) down with it.
      _lastError = asAdFlowError(e, AdFlowErrorKind.consent);
    } finally {
      // ALWAYS re-read the privacy-options requirement, even when the flow
      // above failed. We still degrade to `canRequestAds()` below, so a
      // returning EEA user whose info update merely failed offline KEEPS
      // SERVING ADS from cached consent — and an app serving ads to an EEA
      // user must surface the "Manage consent" entry point (invariant 2).
      // Refreshing only on the success path meant a failed/timed-out update
      // left `privacyOptionsRequired` false while ads ran: a silent GDPR gap
      // on exactly the weak-network launches this package must survive. The
      // call reads cached UMP state and is itself best-effort (it swallows
      // its own errors), so it is safe here.
      await _refreshPrivacyRequirement();
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
    } catch (e) {
      _lastError = asAdFlowError(e, AdFlowErrorKind.consent);
      return false;
    }
    // Only iOS 14+ with an undetermined status can show the system prompt.
    if (status != AttStatus.notDetermined) return false;
    await _waitBeforePresenting();
    try {
      await attExplainer(_attExplainerContent);
    } catch (e) {
      _recordPresenterError(e);
    }
    await Future<void>.delayed(_attPromptDelay);
    try {
      final result = await _sdk.requestTrackingAuthorization();
      return result == AttStatus.denied;
    } catch (e) {
      _lastError = asAdFlowError(e, AdFlowErrorKind.consent);
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
    await _waitBeforePresenting();
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
    } catch (_) {
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
      // The consent flow is network-bound and runs in the BACKGROUND
      // (ADR-032), so the app can dispose the whole graph while we are still
      // awaiting the seam above. Writing a changed value into a disposed
      // ValueNotifier throws a FlutterError into the background zone, so
      // re-check after every await, not just at entry.
      if (_disposed) return;
      _privacyOptionsRequired.value =
          status == PrivacyOptionsRequirement.required;
    } catch (_) {
      // Keep the previous value; requirement status is best-effort. Catches
      // everything (not just AdFlowError) because this now runs in _run's
      // `finally` — a throw here would replace the real consent outcome.
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
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _privacyOptionsRequired.dispose();
  }
}
