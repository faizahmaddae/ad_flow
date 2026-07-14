# Spec — bring back `initializeWithExplainer` in v2 (better)

Restores the v1 pre-consent / pre-ATT **priming ("explainer") screens** that Faiz uses in every app, redesigned for the v2 architecture. v1 coupled the package to `BuildContext` (`AdFlow.instance.initializeWithExplainer(context: …)`); v2 uses the **presenter pattern** already established by `rewardedIntroPresenter` — decoupled, testable, no `BuildContext` inside the package.

## Decisions (agreed with the maintainer)
- **Client-driven ATT (like v1):** re-add ATT behind the `AdSdk` seam (iOS). The flow is: your localizable ATT explainer → 200 ms delay (Apple recommendation) → the system ATT prompt — **before** the GDPR consent flow. Do NOT also configure the UMP IDFA message in the AdMob console in this mode (avoids a double prompt); document that.
- **Opt-in & additive:** everything is optional. No presenter passed → behaviour is exactly today's (UMP-driven). This is not a breaking change.
- **Show the consent primer only when a consent form will actually appear** (v2 improvement over v1's `showExplainer` bool) — non-EEA users never see a pointless dialog.
- **Presenter pattern, not `BuildContext`:** the package calls a `Future` callback; the app supplies the UI (via its `navigatorKey`), exactly like `rewardedIntroPresenter`.

## Existing v2 patterns to mirror (verified in the code)
- `typedef RewardedIntroPresenter = Future<bool> Function(RewardIntroContent content);` (in `rewarded_interstitial_ad_controller.dart`).
- `RewardedIntroScreen` — a `StatelessWidget` + `static Future<bool> show(BuildContext, RewardIntroContent)` that pushes a fullscreen-dialog route. **Copy this shape for the two explainer screens.**
- `AdFlow.initialize(config, {rewardedIntroPresenter, consentDebug, sdk, store, platform})` → builds `UmpConsentGateway(_sdk, …)`. Presenters flow from `initialize` into the gateway.
- `UmpConsentGateway._run()` order today: `requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired`. The explainer logic slots into this method.
- Seam UMP methods exist (`requestConsentInfoUpdate`, `canRequestAds`, `loadAndShowConsentFormIfRequired`, `getPrivacyOptionsRequirementStatus`, `showPrivacyOptionsForm`, `resetConsent`). **No ATT methods — those are new.**

---

## 1. New public API (all optional)

### Content classes (localizable, immutable `const`) — port v1's texts
`lib/src/consent/explainer_content.dart`
```dart
class ConsentExplainerContent {
  const ConsentExplainerContent({
    this.title = 'Your privacy matters',
    this.description = 'This app is free because it shows ads. To keep it free and '
        'show you more relevant ads, we\'d like your consent on the next screen.',
    this.bullets = const [
      'Ads that match your interests',
      'Your data stays secure',
      'Helps keep the app free',
    ],
    this.settingsHint = 'You can change this anytime in Settings.',
    this.continueLabel = 'Continue',
    this.skipLabel = "I'll decide on the next screen",
  });
  final String title, description, settingsHint, continueLabel, skipLabel;
  final List<String> bullets;
  // copyWith
}

class AttExplainerContent {
  const AttExplainerContent({
    this.title = 'Allow tracking?',
    this.description = 'On the next screen Apple will ask if you allow tracking. '
        'Allowing it helps us show ads that are more relevant to you.',
    this.footnote = "Your choice won't affect the number of ads you see.",
    this.continueLabel = 'Got it',
  });
  final String title, description, footnote, continueLabel;
  // copyWith
}
```

### Presenter typedefs (mirror `RewardedIntroPresenter`)
```dart
typedef ConsentExplainerPresenter = Future<void> Function(ConsentExplainerContent content);
typedef AttExplainerPresenter     = Future<void> Function(AttExplainerContent content);
```
Both are pure primers: the real UMP form / system ATT prompt always follows, so the return is `void` (either button just dismisses the primer). The app decides context-validity inside the callback (e.g. `if (navigatorKey.currentContext == null) return;`), so the package never holds a `BuildContext`.

### Ready-made screens (copy `RewardedIntroScreen`)
`lib/src/widgets/consent_explainer_screen.dart` → `ConsentExplainerScreen` + `static Future<void> show(BuildContext, ConsentExplainerContent)`.
`lib/src/widgets/att_explainer_screen.dart` → `AttExplainerScreen` + `static Future<void> show(BuildContext, AttExplainerContent)`.
Both: fullscreen-dialog route, themed, `SafeArea`, a primary `continueLabel` button (pops), and for consent a secondary `skipLabel` button (also pops). Export both from the barrel.

## 2. Seam additions (ATT — iOS)
`ad_sdk_types.dart`:
```dart
enum AttStatus { notDetermined, restricted, denied, authorized, notSupported }
```
`AdSdk` (interface) + `GmaAdSdk` + `FakeAdSdk`:
```dart
Future<AttStatus> getTrackingAuthorizationStatus();   // Android/others → notSupported
Future<AttStatus> requestTrackingAuthorization();      // iOS system prompt; else no-op
```
- `GmaAdSdk`: implement via the **`app_tracking_transparency`** package (re-add it to `pubspec.yaml`; the README note "dependency removed" must be updated). iOS only; non-iOS returns `notSupported`.
- `FakeAdSdk`: a settable `attStatus`, a `requestTrackingAuthorization` that records the call count and returns a configurable result — so the gateway is fully testable with no device.
- Also add `Future<bool> isConsentFormAvailable()` (or `getConsentStatus()`) to the seam **if not already present**, so the gateway can show the consent primer *only* when a form will appear.

## 3. ConsentGateway flow (the orchestration)
Extend `UmpConsentGateway` constructor with optional injected `consentExplainer`, `attExplainer`, `consentExplainerContent` (default `const ConsentExplainerContent()`), `attExplainerContent` (default `const AttExplainerContent()`), `attPromptDelay = const Duration(milliseconds: 200)`, and `skipGdprConsentIfAttDenied` (default **true**, matching v1). New `_run` order (ATT first, then GDPR — like v1):

```
1. iOS ATT (only if getTrackingAuthorizationStatus() == notDetermined AND attExplainer != null):
     await attExplainer(attExplainerContent);      // your primer
     await Future.delayed(attPromptDelay);          // 200ms, Apple guidance
     final att = await requestTrackingAuthorization();
     if (att == denied && skipGdprConsentIfAttDenied) { /* skip step 3 form */ }
2. await requestConsentInfoUpdate(...).timeout(...)        // unchanged
   await _refreshPrivacyRequirement();
3. GDPR consent form:
     if (consentExplainer != null AND a form will show   // isConsentFormAvailable()/status required
         AND not skipped-by-ATT-denial):
        await consentExplainer(consentExplainerContent);  // your primer
     await loadAndShowConsentFormIfRequired();
   await _refreshPrivacyRequirement();
4. return canRequestAds();   // same degrade-on-error semantics as today
```
Keep every existing guard: the `_infoUpdateTimeout`, the try/`on AdFlowError`/`on TimeoutException` degrade-to-`canRequestAds()`, the in-flight join, and `lastError`. If a presenter throws, catch it, record `lastError`, and continue to the real prompt (a broken primer must never block consent).

## 4. Facade wiring
Add to `AdFlow.initialize` (and the private ctor) optional params: `consentExplainer`, `attExplainer`, `consentExplainerContent`, `attExplainerContent`, `skipGdprConsentIfAttDenied`. Pass them into the `UmpConsentGateway(...)` construction. No change to `_start`'s parallel `Future.wait` — the explainer simply extends the consent future while init/`updateRequestConfiguration` run alongside.

**Consumer usage (the v2 equivalent of `initializeWithExplainer`):**
```dart
final ads = await AdFlow.initialize(
  myConfig,
  attExplainer: (c) => AttExplainerScreen.show(navigatorKey.currentContext!, c),
  consentExplainer: (c) => ConsentExplainerScreen.show(navigatorKey.currentContext!, c),
  // optional: attExplainerContent: AttExplainerContent(title: 'Autoriser le suivi ?', ...),
);
```

## 5. Tests (FakeAdSdk + fake presenters — no device)
- ATT explainer runs **before** `requestTrackingAuthorization`, and only when status is `notDetermined` (not when already authorized/denied).
- `attPromptDelay` respected (fakeAsync).
- `skipGdprConsentIfAttDenied`: ATT denied → consent form NOT shown; ATT authorized → form shown.
- Consent explainer runs **before** `loadAndShowConsentFormIfRequired`, and **only when a form will appear** (skipped for non-EEA / no-form).
- No presenter provided → today's exact behaviour (no explainer, no ATT call); regression-guard the default path.
- A presenter that throws → `lastError` set, real prompt still proceeds.
- Android → `getTrackingAuthorizationStatus()` == `notSupported`, ATT step skipped.
- Widget tests for both screens (buttons pop, content renders) — mirror the existing `RewardedIntroScreen` test.

## 6. Docs
- README: a new "Consent & ATT explainers (priming)" subsection with the usage above; update the ATT note (client-driven mode — do **not** also set the UMP IDFA console message).
- MIGRATION.md: map v1 `initializeWithExplainer(context:, consentTexts:, attTexts:)` → v2 `initialize(consentExplainer:, attExplainer:, consentExplainerContent:, attExplainerContent:)`; note the presenter pattern replaces the `BuildContext` param.
- DECISIONS.md: an ADR for "client-driven ATT + presenter-based explainers"; append the trap "explainer presenter must be context-safe; package never holds BuildContext" to the skill.

## 7. Build order (small green slices)
1. Content classes + the two ready-made screens (+ widget tests, barrel export).
2. Seam ATT: `AttStatus` + the two methods on `AdSdk`/`GmaAdSdk`/`FakeAdSdk` (+ `isConsentFormAvailable` if missing); re-add `app_tracking_transparency`.
3. `UmpConsentGateway` explainer/ATT flow (+ the tests in §5) — the correctness core.
4. Facade params + wiring (+ an end-to-end FakeAdSdk test).
5. Example: add the two presenters to `AdFlow.initialize` (wired via the existing `navigatorKey`).
6. Docs (README/MIGRATION/DECISIONS/skill trap). Final `flutter analyze` + `flutter test` + on-device check (force EEA + a fresh iOS install to see ATT).
