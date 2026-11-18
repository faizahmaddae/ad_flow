import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/ad_flow_error.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import 'explainer_content.dart';
import 'tcf_consent.dart';

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
  /// priming ("explainer") flow. All are optional and additive.
  ///
  /// **Order (ADR-082): the GDPR flow always comes first, Apple's tracking
  /// question last.** App Review rejects an app whose user answers the
  /// tracking prompt and is then shown a consent form asking them to agree to
  /// tracking (Guideline 5.1.1(iv)) — and that is what the pre-5.5.0 order
  /// (ATT first) produced. GDPR-then-ATT is also UMP's own order when the IDFA
  /// message is configured in the AdMob console.
  ///
  /// - [consentExplainer] — presents the app's consent primer before the UMP
  ///   GDPR form, but **only when a form will actually appear** (non-EEA
  ///   users never see it).
  /// - [attExplainer] — presents the app's ATT primer before Apple's system
  ///   tracking prompt (client-driven ATT, iOS): primer → [attPromptDelay] →
  ///   system prompt, run once this run's GDPR flow has settled. It is skipped
  ///   when the user has just refused GDPR purpose 1 (device storage/access) —
  ///   read from the TCF record UMP stores, via [readTcfConsent] — and it waits
  ///   for a later run when this run's GDPR flow failed (offline), so a
  ///   tracking question can never precede the consent form. When null, no ATT
  ///   call is made at all (UMP-driven / console-configured ATT, recommended).
  /// - [consentExplainerContent] / [attExplainerContent] — the copy passed to
  ///   the respective presenters (localize by overriding).
  /// - [attPromptDelay] — brief pause between the ATT primer and the system
  ///   prompt (Apple's guidance; default 200 ms).
  /// - [readTcfConsent] — reads the device's TCF record; defaults to
  ///   [readDeviceTcfConsent]. Injectable for tests.
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
    TcfConsentReader readTcfConsent = readDeviceTcfConsent,
    Future<void> Function()? waitBeforePresenting,
  }) : _tagForUnderAgeOfConsent = tagForUnderAgeOfConsent,
       _infoUpdateTimeout = infoUpdateTimeout,
       _consentExplainer = consentExplainer,
       _attExplainer = attExplainer,
       _consentExplainerContent = consentExplainerContent,
       _attExplainerContent = attExplainerContent,
       _attPromptDelay = attPromptDelay,
       _readTcfConsent = readTcfConsent,
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
  final TcfConsentReader _readTcfConsent;
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
    // Step 1 — the GDPR flow, ALWAYS before any tracking question (ADR-082).
    //
    // The pre-5.5.0 order ran client-driven ATT first, and App Review rejected
    // two of the maintainer's apps for it under Guideline 5.1.1(iv) (2026-07,
    // 2026-10): a user who chose "Ask App Not to Track" was then shown a
    // consent form asking them to agree to tracking. GDPR-then-ATT is also
    // UMP's own order when the IDFA message is configured in the console.
    var gdprSettled = false;
    try {
      // The consent info update (every launch; canRequestAds() and the
      // privacy-options status depend on it).
      await _sdk
          .requestConsentInfoUpdate(
            tagForUnderAgeOfConsent: _tagForUnderAgeOfConsent,
            debug: debug,
          )
          .timeout(_infoUpdateTimeout);
      await _refreshPrivacyRequirement();
      // The OPTIONAL consent primer — only when a form will actually appear
      // (non-EEA users never see a pointless dialog). It never gates the form.
      await _maybeShowConsentPrimer();
      // The GDPR form itself. ALWAYS called: the plugin no-ops when no form is
      // required, and shows the REQUIRED form (EEA/UK/CH) otherwise. Nothing
      // may suppress it — ATT (Apple) and GDPR (EU) are independent regimes.
      // This line is the compliance guarantee (ADR-031).
      await _sdk.loadAndShowConsentFormIfRequired();
      // Form dismissal can change both statuses.
      await _refreshPrivacyRequirement();
      gdprSettled = true;
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
    // Step 2 — client-driven ATT (opt-in; iOS only in practice), LAST.
    //
    // Only after THIS run's GDPR flow settled. A failed flow (offline, a form
    // error) leaves the user's GDPR answer unknown, and a tracking prompt now
    // could precede the consent form a later run shows — the rejected order
    // again. The facade's retry re-runs the whole flow when the network
    // returns, and the question is asked then.
    //
    // Contained, like every step: an ATT platform throw (no
    // app_tracking_transparency channel, no NSUserTrackingUsageDescription)
    // never changes the consent answer below.
    if (gdprSettled) {
      try {
        await _maybeRunAtt();
      } catch (e) {
        _lastError ??= asAdFlowError(e, AdFlowErrorKind.consent);
      }
    }
    // Degrade to the SDK's own answer: consent obtained on a previous
    // launch (or not required at all) keeps serving ads through transient
    // consent-flow failures.
    //
    // Contained: the plugin's canRequestAds() force-unwraps its channel
    // result, so it CAN throw — and this read sits outside the try above.
    // ensureCanRequestAds's documented contract is "never throws"; a throw
    // here used to reject the whole run, reaching every joiner
    // (AdFlow._settleConsent → the gate → every load) as a raw error
    // (4.0 audit).
    try {
      return await _sdk.canRequestAds();
    } catch (e) {
      _lastError ??= asAdFlowError(e, AdFlowErrorKind.consent);
      return false;
    }
  }

  /// Runs the client-driven ATT flow when [_attExplainer] is set, the status
  /// is [AttStatus.notDetermined] and the user did not just refuse GDPR
  /// purpose 1: the app's primer, Apple's recommended [_attPromptDelay], then
  /// the system prompt. Called only after the GDPR flow settled (ADR-082).
  ///
  /// A throwing presenter is caught and recorded on [lastError]; the real
  /// system prompt still fires — a broken primer must never block ATT.
  Future<void> _maybeRunAtt() async {
    final attExplainer = _attExplainer;
    if (attExplainer == null) return; // opt-in: no client ATT at all
    final AttStatus status;
    try {
      status = await _sdk.getTrackingAuthorizationStatus();
    } catch (e) {
      _lastError ??= asAdFlowError(e, AdFlowErrorKind.consent);
      return;
    }
    // Only iOS 14+ with an undetermined status can show the system prompt.
    // (UMP's own IDFA message, when configured in the console, has already
    // asked inside the form step above — then the status is decided and the
    // app's primer is skipped here: never a double prompt.)
    if (status != AttStatus.notDetermined) return;
    // A user who has just refused device storage/access (TCF purpose 1) under
    // GDPR is not asked for tracking: that would be asking for it twice. UMP's
    // own IDFA flow skips them the same way.
    if (await _refusedDeviceAccess()) return;
    await _waitBeforePresenting();
    try {
      await attExplainer(_attExplainerContent);
    } catch (e) {
      _recordPresenterError(e);
    }
    await Future<void>.delayed(_attPromptDelay);
    try {
      await _sdk.requestTrackingAuthorization();
    } catch (e) {
      _lastError ??= asAdFlowError(e, AdFlowErrorKind.consent);
    }
  }

  /// Whether the device's TCF record says the user refused GDPR purpose 1.
  ///
  /// An unreadable record reads as "no record": the question is then asked,
  /// as for a user outside the EEA (where UMP writes no record at all).
  Future<bool> _refusedDeviceAccess() async {
    try {
      return (await _readTcfConsent())?.refusedDeviceAccess ?? false;
    } catch (_) {
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

  /// Records a broken presenter, keeping an earlier error of this run (the
  /// first failure is the one worth reporting).
  void _recordPresenterError(Object error) {
    _lastError ??= error is AdFlowError
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
