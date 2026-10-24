# ad_flow

Easy AdMob integration for Flutter with policy-aware defaults — banner,
interstitial, rewarded, rewarded interstitial, native and app open ads, with
UMP consent, frequency capping, retry with backoff, and revenue callbacks
built in. (Defaults and guardrails encode AdMob's published policies;
final policy compliance always depends on your placements, content and
console setup.)

[![pub package](https://img.shields.io/pub/v/ad_flow.svg)](https://pub.dev/packages/ad_flow)
[![google_mobile_ads](https://img.shields.io/badge/google__mobile__ads-9.x-green.svg)](https://pub.dev/packages/google_mobile_ads)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Built on `google_mobile_ads ^9.2.0` (Android + iOS). Upgrading from an older
ad_flow? Read [MIGRATION](MIGRATION.md).

**What you get for free:**

- **Consent first, always.** No ad loads before the UMP gate opens
  (GDPR/EEA form, ATT coordination, privacy-options entry point).
- **Policy-aware defaults.** App open on warm returns by default (with opt-in
  `launchOnly` / `launchAndResume` trigger modes) and the 4-hour expiry;
  interstitials frequency-capped and action-paced; the rewarded
  interstitial intro/skip screen is mandatory by construction; banners
  reserve their height so layouts do not jump, and collapse to a zero
  footprint when ads are disabled (Remove-Ads).
- **Revenue-minded plumbing.** Google's large anchored adaptive banner by
  default; every full-screen format keeps one ad warm (load → show → reload
  on dismiss); failed loads retry with exponential backoff + jitter and
  re-arm after a cooldown; `onPaidEvent` reports impression-level revenue.
- **Testable.** Everything runs behind an `AdSdk` seam;
  `package:ad_flow/ad_flow_testing.dart` ships `FakeAdSdk` so you can unit
  test your integration without a device.

---

## Set up with AI (copy-paste)

Prefer to let your AI assistant (Claude Code, Cursor, Copilot, …) do the wiring? Copy the matching prompt below into your assistant **inside your project**. Each prompt tells it to read this package's real API first, then integrate or migrate following the recommended patterns — so it never guesses an API and never blocks your app's first frame.

### 🆕 New setup — add ad_flow (fresh, or replacing your existing ad code)

```
Set up the ad_flow Flutter package (AdMob) in my project. Do it idiomatically — do not guess the API.

1. FIRST read the real API: this package's README and its public API
   (package:ad_flow/ad_flow.dart, e.g. in the pub cache). Use only symbols that exist there.
2. Scan my project for existing ad code (google_mobile_ads usage, AdMob, banner/interstitial/
   rewarded/app-open, or another ads wrapper).
   • If you find any: show me what it is, then REPLACE it with ad_flow equivalents and remove the
     old implementation (and the direct google_mobile_ads dependency if nothing else uses it).
   • If none: do a clean fresh integration.
3. Add ad_flow: ^5.4.0 to pubspec and meet its min versions (Flutter >=3.38.1, iOS 13,
   Android minSdk 24 / compileSdk 36). Platform setup: Android APPLICATION_ID meta-data, iOS
   GADApplicationIdentifier + NSUserTrackingUsageDescription + SKAdNetworkItems. Remind me to
   publish & verify app-ads.txt.
4. Ask me which formats I want and for my ad unit IDs (or use AdFlowConfig.test() for now).
5. Follow the README best practices EXACTLY: non-blocking init (never gate the first frame / a
   splash on it), a navigatorKey on MaterialApp with the ready-made presenters
   (RewardedIntroScreen.presenter(navigatorKey) etc.), the widget-first ad widgets
   (AdFlowBanner(adFlow: ads, safeArea: true) for a bottom bar — they own their controllers),
   and consent-first.
6. Verify: flutter analyze is clean and the app builds; show me where each ad renders.

Ask me anything you need (formats, IDs, EEA/iOS) before writing code. Keep changes minimal and explained.
```

### 🔁 Migrate — upgrade an older ad_flow to the current release

```
Upgrade my project's ad_flow to the latest release. Be careful — older majors changed the API a lot.

1. FIRST read ad_flow's MIGRATION.md plus the current README and public API
   (package:ad_flow/ad_flow.dart). Use only symbols that exist there.
2. Bump ad_flow to ^5.4.0 and meet its min versions (Flutter >=3.38.1, Dart >=3.10, iOS 13,
   Android minSdk 24 / compileSdk 36; adopt the iOS UISceneDelegate lifecycle if I have a custom AppDelegate).
3. Find EVERY older ad_flow usage (legacy AdFlow.instance/initializeWithExplainer/EasyBannerAd, old
   managers/widgets, a broad google_mobile_ads re-export). List them, then migrate each per MIGRATION.md.
4. Apply the current best practices: non-blocking init (drop any FutureBuilder/await that gates the UI
   on init), the widget-first ad widgets (AdFlowBanner(adFlow: ads) — they own their controllers), the
   ready-made presenters (RewardedIntroScreen.presenter(navigatorKey) and friends) instead of
   hand-written presenter closures, AdFlowBanner(safeArea: true) instead of a SafeArea +
   adsEnabled builder around a bottom banner, and ValueListenable state.
5. Remove whatever is now dead; keep my ad unit IDs and behavior intact.
6. Verify: flutter analyze is clean and the app builds.

Show me the mapping before large edits, and flag any behavior change (e.g. EEA users now see the GDPR
consent form even if they denied ATT; native ads expire after ~55 min by default; anchored banners
are now Google's large format, so a bottom banner is taller).
```

> These prompts intentionally defer to the package's own README / MIGRATION for exact symbols, so they stay correct as the package evolves.

---

## 1. Install

```yaml
dependencies:
  ad_flow: ^5.4.0
```

Requirements (from `google_mobile_ads` 9.x): Flutter ≥ 3.38.1, Dart ≥ 3.10,
iOS 13+, Android `minSdk 24` / `compileSdk 36`.

## 2. Platform setup

### app-ads.txt — do not skip this

Since January 2025 AdMob **requires a verified `app-ads.txt`** for full ad
serving. Publish one at `https://your-developer-domain/app-ads.txt` with the
line AdMob gives you, and verify it in the AdMob console — otherwise your
apps silently under-serve.

### Android

`android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"/>
```

### iOS

`ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

`NSUserTrackingUsageDescription` is **required** if you pass `attExplainer`
(client-driven ATT): iOS terminates the app when the tracking prompt is
requested without it.

Also add **`SKAdNetworkItems`** to `Info.plist`. SKAdNetwork is how iOS attributes
installs to ads when the user has not granted tracking permission — which is most
users. Without these entries, ad networks cannot receive attribution for your app,
which depresses your iOS eCPM with no error and no signal anywhere:

```xml
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>  <!-- Google/AdMob -->
  </dict>
  <!-- plus one entry per mediation network you use -->
</array>
```

Copy the current, full list from Google's docs — it changes as networks are
added: <https://developers.google.com/admob/ios/quick-start#update_your_infoplist>.
If you use mediation, add each partner network's identifier too.

Recent Flutter templates are already scene-based; if you maintain a custom
`AppDelegate`, adopt the `UISceneDelegate` lifecycle (required by the v9
plugin).

The application ID **cannot** be set from Dart — `AdFlowConfig` carries ad
*unit* IDs only.

## 3. Quick start

**Step 1 — platform setup.** Do [§2](#2-platform-setup) first (app IDs +
`app-ads.txt`).

**Step 2 — initialize (non-blocking) and drop in a banner.** `initialize()`
returns immediately; consent, ATT and ad loading all run in the **background**.
Render your UI on the first frame — **never `await`-block it behind a splash**.

```dart
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolves on the next microtask (graph construction only) — it NEVER
  // waits on the network, so the first frame is instant.
  final ads = await AdFlow.initialize(
    AdFlowConfig.test(), // dev: Google sample ads. Swap for your production config.
    rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
  );
  runApp(MaterialApp(
    navigatorKey: navigatorKey, // the presenters show their screens on it
    home: Home(ads: ads),
  ));
}

class Home extends StatelessWidget {
  const Home({super.key, required this.ads});
  final AdFlow ads;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: const Center(child: Text('Hello')),
        // Clear of the home indicator, and gone entirely — inset included —
        // once ads are disabled (Remove-Ads).
        bottomNavigationBar: AdFlowBanner(adFlow: ads, safeArea: true),
      );
}
```

That is the whole integration. The widget creates and owns its controller,
reserves its height from the first frame and disposes everything on unmount.

Nothing loads before request configuration is applied **and** the consent gate
opens — this holds even for a first-frame banner/native. Do **not** wrap your
app in a `FutureBuilder<AdFlow>` splash gate (that was v1's hang). Need the
consent result? `await ads.whenReady` (`Future<bool>`) — optional, never gate
UI on it.

`rewardedIntroPresenter` is required because `AdFlowConfig.test()` includes
the rewarded interstitial, whose intro + skip screen must show first (AdMob
policy). Leave that slot out of your production config and you can leave the
presenter out too.

### Add consent + ATT priming (recommended for EEA / iOS)

Show your own soft primer before the UMP GDPR form and Apple's ATT prompt —
opt-in, additive, better opt-in rates. Two more presenters (details and copy
localization in [§5](#5-consent--privacy)):

```dart
await AdFlow.initialize(
  AdFlowConfig.test(),
  rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
  attExplainer: AttExplainerScreen.presenter(navigatorKey),
  consentExplainer: ConsentExplainerScreen.presenter(navigatorKey),
);
```

The [example](example/lib/main.dart) runs **both** modes behind one
`useExplainer` flag.

### Production config

Only configured slots ever load:

```dart
final ads = await AdFlow.initialize(
  AdFlowConfig(
    banner: const BannerConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/1', ios: 'ca-app-pub-…/2'),
    ),
    interstitial: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/3', ios: 'ca-app-pub-…/4'),
      cap: FrequencyCap(minGap: Duration(seconds: 30), maxPerHour: 6),
      minActionsBetween: 2,
    ),
    rewarded: const RewardedConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/5', ios: 'ca-app-pub-…/6'),
    ),
    appOpen: const AppOpenConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/7', ios: 'ca-app-pub-…/8'),
    ),
    globalFrequencyCap: const FrequencyCap(minGap: Duration(seconds: 15)),
    testDeviceIds: ['YOUR-HASHED-DEVICE-ID'],
  ),
);
```

Configure BOTH platforms' IDs for every slot you use on both platforms. A slot
missing the current platform's ID is simply **unconfigured there**: its
throwing getter (`ads.interstitial`) throws, and `ads.interstitialOrNull`
returns null — use the `…OrNull` getters in shared cross-platform code that
should degrade rather than crash. `initialize` also validates the config
(empty ID strings, negative durations, …) and fails fast with
`AdFlowError(invalidConfig)` instead of silently no-filling in production.

Set `testMode: true` (or use `AdFlowConfig.test()`) during development —
it swaps every **configured** slot to Google's sample IDs, picking the sample
unit that matches each banner's kind. Never ship it.

## 4. Formats

### Banner

```dart
Scaffold(
  bottomNavigationBar: AdFlowBanner(adFlow: ads, safeArea: true),
)
```

`AdFlowBanner(adFlow:)` creates and owns its controller, so the classic
footgun — minting a fresh controller inside `build()` and restarting
(blanking) the load on every `setState` — cannot happen. Pass
`config: BannerConfig(...)` for a per-placement override. Advanced:
`ads.banner()` mints a standalone `BannerAdController` you can pass via
`controller:` when you need to inspect its `state`/`response` elsewhere —
create it ONCE, as a field.

`safeArea: true` keeps the banner clear of the home indicator and notches —
use it for a bottom bar instead of wrapping the banner in your own `SafeArea`,
which would keep reserving its inset after Remove-Ads collapses the banner.
The ad is requested at the width left between the side insets.

Anchored adaptive by default (Google's revenue recommendation). Inline
adaptive, fixed sizes and collapsible banners are configured via
`BannerConfig(kind:, fixedSize:, collapsible:, maxInlineHeight:)`.
Client-side refresh (`minRefresh`) is **off by default**, because AdMob
already auto-refreshes banner ad units server-side — set the rate in the
AdMob console instead. When opted in, values under 30s are clamped.

**Placeholder height.** A loaded banner always uses the exact live SDK
dimensions. Before the ad loads, `AdFlowBanner` reserves:

- **fixed** — the slot's exact configured height (no shift when it loads);
- **anchored adaptive** — the documented **50dp floor** for the first banner
  of a width, then the exact height the SDK reports once the ad loads
  (Google's *large* anchored format: about 100–150dp on a phone in portrait).
  ad_flow remembers that height, so every later banner at the same width — the
  next screen, a reload — reserves it from its first frame and its ad lands
  without a layout shift;
- **inline adaptive** — **0**, because the real height is unknown until
  `onAdLoaded`.

Pass `placeholderHeight` to reserve a publisher-chosen height for a placement
whose size you know in advance (e.g. an inline banner). `placeholderHeight: 0`
opts into fully collapsed pre-load behaviour — no reservation until the ad
actually loads.

### Choosing a banner kind

| kind | slot height | best for |
| --- | --- | --- |
| `anchoredAdaptive` *(default)* | one height per width/device (about 100–150dp on a phone), reported by the SDK after load | pinned to the top/bottom of a screen, outside scrolling content |
| `inlineAdaptive` | decided per-creative by Google, known only after load; cap it with `maxInlineHeight` | inside a feed or any scrolling content |
| `fixed` | the exact IAB size you name | you need one guaranteed size |

Both adaptive kinds size their slot from the SDK's own post-load answer, so the
box always matches what was actually rendered. For a bottom-bar placement,
`anchoredAdaptive` is the right format; reach for
`BannerConfig(kind: BannerKind.inlineAdaptive, maxInlineHeight: …)` when the
banner lives in a list.

> **Large anchored banners (google_mobile_ads 9.2.0+).** The default kind is
> Google's *large* anchored adaptive format — its revenue recommendation for
> banners pinned to the top or bottom of the screen. Before plugin 9.2.0 the
> "large" flag was lost on the way to the platform, so these banners rendered
> at the classic ~60dp; ad_flow now requires 9.2.0, so they render at the real
> large size. If a screen cannot spare that much height, set
> `kind: BannerKind.fixed` (320×50) in that placement's `BannerConfig`.

### Filling the slot (`backgroundColor`)

An adaptive slot is anchored to its **width**. When AdMob fills it with a
creative narrower or shorter than the slot, the SDK centres that creative and
leaves the surround unpainted — so your app's surface shows through and the ad
can read as a rendering glitch. Google's guidance is to give the slot an opaque
background:

```dart
AdFlowBanner(
  adFlow: ads,
  safeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
)
```

It paints strictly **behind** the ad (never over it — occluding a creative is a
policy violation) and, like `placeholderHeight`, disappears entirely once ads
are disabled.

### Interstitial

```dart
// At natural break points (level end, screen change):
ads.interstitial.recordUserAction();
await ads.interstitial.show();
```

Preloaded at init and after every dismissal. `show()` is a no-op (returns
false) while consent is closed, a cap is active, another full-screen ad is
visible, or — once you start calling `recordUserAction()` — fewer than
`minActionsBetween` actions happened since the last interstitial.

### Rewarded

```dart
await ads.rewarded.show(onReward: (reward) {
  wallet.add(reward.amount); // fires at most once per ad
});
```

High-value rewards: set `RewardedConfig.ssv` for server-side verification —
and update it at runtime as your app learns more:

```dart
// After login, and again right before showing (e.g. which mission this is):
await ads.rewarded.setServerSideVerification(
  ServerSideVerification(userId: user.id, customData: 'mission-7'),
);
```

The update applies to the already-loaded ad AND every future load, and
**throws** if attaching fails — when you grant high-value rewards, you want to
know your verification payload did not make it. The ad is never ready or
showable until the latest payload has settled, so a `show()` right after
`setServerSideVerification` can never race ahead of it with the old value. A
load whose configured verification cannot attach counts as a failed load —
never a silently unverified ready ad.

#### Verifying rewards server-side (SSV)

`onReward` is a **client-side UX/completion signal, not cryptographic proof** —
it means the SDK reported the user finished the ad, nothing more. Likewise,
attaching `userId`/`customData` (whether via `RewardedConfig.ssv` or
`setServerSideVerification`) only hands the payload to the SDK; a successful
attach does **not** prove your backend ever received or verified a callback.

For any reward the user could exploit — currency, entitlements, unlocks — make
your **server** the authority. When Google calls your SSV endpoint, your backend
must:

1. **Verify the callback's `signature` and `key_id`** against Google's public
   verification keys — reject anything that doesn't validate.
2. **Validate the contents** match what you expect: the `user_id`, the ad unit,
   the reward `type`/`amount`, and your `custom_data`.
3. **Process `transaction_id` idempotently**, so a replayed or duplicated
   callback can never double-credit the user.

Then pick **one** fulfillment strategy and grant the reward from exactly one
place:

- **Grant on the client, reconcile after** — credit immediately in `onReward`
  for responsiveness, then revoke/adjust if your server-verified callback
  disagrees. Fine for low-value, low-abuse rewards.
- **Wait for the verified callback** — grant nothing on the client; your backend
  credits the account only after it validates Google's callback. Use this for
  server-authoritative or high-value economies.

Do **not** grant the same reward from both the client and the server — that
double-credits. One authority per reward. See Google's
[Server-Side Verification guide](https://developers.google.com/admob/flutter/ssv)
for the callback format, parameters and key rotation.

Preloaded ads also **expire** (Google documents ~1 hour): ad_flow timestamps
every load, proactively replaces a stale ad and never shows an expired one.
`maxAdAge` defaults to 55 minutes for the full-screen formats **and native
ads**, and 4 hours for app-open; set it `null` on a format to disable.

A rewarded ad is one the user **asked for**, so the global frequency cap never
blocks it — a user who taps "watch an ad for 100 coins" must never be silently
refused because an interstitial happened to fire moments earlier. Its
impression is still *recorded* globally, so an involuntary interstitial cannot
fire straight after one. Both rewarded formats are uncapped by default; set
`RewardedConfig.cap` / `RewardedInterstitialConfig.cap` if you want a per-format
limit.

### Rewarded interstitial

```dart
await ads.rewardedInterstitial.show(onReward: grantReward);
```

AdMob policy requires an intro screen with clear reward messaging and a
skip option before the ad plays. ad_flow enforces this by construction:
the `rewardedIntroPresenter` you pass to `initialize` runs first, and the
ad shows only if the user didn't skip. `RewardedIntroScreen.presenter`
is the ready-made one; customize copy via `RewardedInterstitialConfig.intro`,
or pass your own presenter for a custom screen (keep a skip option — it is
policy).

### Native

```dart
AdFlowNativeAd(adFlow: ads) // creates + owns its controller
// per-placement override: AdFlowNativeAd(adFlow: ads, config: NativeConfig(...))
```

Template rendering (`NativeConfig(templateKind: NativeTemplateKind.small | .medium)`)
needs no native code. For fully custom layouts register a platform
`NativeAdFactory` (see the [official guide](https://developers.google.com/admob/flutter/native/platforms))
and use `NativeConfig(factoryId: 'yourFactoryId')`. Setup details:
[doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md).

Native ads **expire** too (`NativeConfig.maxAdAge`, default 55 min): a
long-lived screen never renders stale inventory — the widget briefly shows its
placeholder while a fresh ad loads, then swaps it in.

`AdFlowNativeAd` collapses to a zero footprint while ads are disabled — but a
surface you wrap it in (a decorated `Card`, a titled section) still renders
its own padding and border around the now-empty child. Hide those parents too,
keyed on `ads.adsEnabled`:

```dart
ValueListenableBuilder(
  valueListenable: ads.adsEnabled,
  builder: (context, enabled, _) => !enabled
      ? const SizedBox.shrink()
      : Card(child: AdFlowNativeAd(adFlow: ads)),
)
```

### App open

App-open ads serve two legitimate moments — a genuine **warm return** and a
**cold launch** — chosen per config with `AppOpenConfig.triggerMode`:

| Mode | Warm return | Cold launch |
| --- | --- | --- |
| `resumeOnly` *(default)* | shows | — |
| `launchOnly` | — | shows |
| `launchAndResume` | shows | shows |

**Warm return** needs nothing to call: the `AppOpenAdManager` (started by
`initialize`) shows a preloaded ad when the app foregrounds — never over another
full-screen ad, never past the 4-hour expiry (stale ads are discarded and
proactively replaced), never behind a banner/native click. It shows on the
first genuine warm return of a session.

**Cold launch is explicit**, because a cold launch emits no foreground event to
hook. Call `showAtLaunchIfReady()` from your real loading screen, right before
entering main content, when `triggerMode` is `launchOnly` or `launchAndResume`:

```dart
// In your loading/startup screen, AFTER your startup work, BEFORE main content:
await ads.appOpen.showAtLaunchIfReady();
```

It shows an **already-ready** ad and **never waits** for the network, UMP, SDK
init, or a load — if nothing is warm yet it returns `false` immediately and you
proceed. It is **one-shot per process launch** (surviving a re-`initialize`), so
a `false` result can never turn into a surprise app-open after the user is
already in main content. Never busy-wait for an ad here — that would reintroduce
a splash hang; do your real startup work and take the ad only if it happens to
be ready. See `example/lib/main.dart`'s `StartupScreen`.

> **You cannot guarantee a cold-launch ad without delaying the user, and
> ad_flow deliberately refuses to.** At a true cold launch the ad is usually not
> ready yet (consent and the first load have not finished), so
> `showAtLaunchIfReady()` returns `false` and your app proceeds. Making it
> "always show" would mean blocking the user behind a spinner waiting for an
> ad — a poor experience and a policy risk. Warm returns are the reliable
> app-open moment; cold-launch is best-effort by design.

Pick a mode in config (`launchOnly` also retires its inventory after the single
launch, so it never keeps requesting an ad it can no longer show):

```dart
// resumeOnly — the default; show only on a genuine warm return.
appOpen: AppOpenConfig(adUnitId: PlatformAdUnitId(android: '…', ios: '…')),

// launchOnly — show only at cold launch (call showAtLaunchIfReady from your
// loading screen); never auto-show on a warm return.
appOpen: AppOpenConfig(
  adUnitId: PlatformAdUnitId(android: '…', ios: '…'),
  triggerMode: AppOpenTriggerMode.launchOnly,
),

// launchAndResume — cold launch (via showAtLaunchIfReady) AND warm returns.
appOpen: AppOpenConfig(
  adUnitId: PlatformAdUnitId(android: '…', ios: '…'),
  triggerMode: AppOpenTriggerMode.launchAndResume,
),
```

> **Policy note:** Google prohibits app-open ads in "Designed for Families"
> apps. If your app is in the Families program, leave the `appOpen` slot
> unconfigured.

An app-open ad is never shown when the user returns from a banner/native ad they
clicked. If a screen shows a large, *blocking* banner or native ad, tell ad_flow
so no app-open ad covers it:

```dart
ads.setBlockingViewAdVisible(true);   // in initState
ads.setBlockingViewAdVisible(false);  // in dispose
```

ad_flow cannot judge that for you — whether a banner is "blocking" depends on your
layout — so ad placement remains partly your responsibility.

## 5. Consent & privacy

UMP runs inside `initialize`. GDPR requires a persistent "Manage consent"
entry point when applicable:

```dart
PrivacyOptionsButton(consent: ads.consent) // renders nothing when not required
```

Consent failures never throw from `initialize` — the flow degrades to the
SDK's own `canRequestAds()` answer, surfaces the failure on
`ads.consent.lastError`, and is retried in the background (an offline launch
recovers once the network returns). After a consent change, an ad already
loaded under the old answer is dropped and reloaded under the new one (a
full-screen ad on screen is not interrupted).

### ATT (iOS App Tracking Transparency) — two modes

- **UMP-driven (default).** Pass no `attExplainer`. On iOS, UMP drives the
  ATT explainer and system prompt for you — configure the IDFA message in
  AdMob's *Privacy & messaging*. `ad_flow` makes no ATT calls itself.
- **Client-driven (opt-in).** Pass an `attExplainer` (below). Then
  `ad_flow` runs your own ATT primer → a short delay (200 ms, Apple's
  guidance) → Apple's system prompt, **before** the GDPR flow. In this mode
  do **not** also configure the UMP IDFA message in the AdMob console — that
  would double-prompt.

Either way, add `NSUserTrackingUsageDescription` to `Info.plist`.

### Consent & ATT explainers (priming)

Opt-in priming screens: your own localizable screen explaining what the next
system dialog will ask; the real UMP form / ATT prompt always follows. The
consent primer appears **only when a form will actually show** (non-EEA users
never see it). Everything is additive — pass nothing and behaviour is exactly
as before.

```dart
final navigatorKey = GlobalKey<NavigatorState>();
// ...MaterialApp(navigatorKey: navigatorKey, ...)

final ads = await AdFlow.initialize(
  myConfig,
  // iOS: your ATT primer → 200 ms → Apple's system prompt, before GDPR.
  attExplainer: AttExplainerScreen.presenter(navigatorKey),
  // Shown before the GDPR form (EEA only).
  consentExplainer: ConsentExplainerScreen.presenter(navigatorKey),
  // Optional: localize / customize the copy.
  // attExplainerContent: const AttExplainerContent(title: 'Autoriser le suivi ?'),
);
```

The ready-made presenters show their screen on the navigator of
`navigatorKey`, read when the screen is due — the package never holds a
`BuildContext` — and skip the primer (the real prompt still follows) if no
navigator is mounted. For custom UI, pass your own presenter:
`(content) async { /* resolve a context, show your screen */ }`.
`skipConsentPrimerIfAttDenied` (default true) skips the optional consent
*primer* when the user just denied ATT. It never suppresses the GDPR form
itself: a required consent form (EEA/UK/CH) is always shown, because ATT
(Apple) and GDPR (EU) are independent regimes — denying tracking does not
satisfy GDPR consent.

Testing EEA behavior:

```dart
await AdFlow.initialize(config, consentDebug: const ConsentDebugOptions(
  geography: ConsentDebugGeography.eea,
  testIdentifiers: ['YOUR-HASHED-DEVICE-ID'],
));
```

## 6. Remove-Ads, kill switch, revenue, inspector

```dart
ads.disableAds();   // user bought Remove-Ads: live/warm ads are DROPPED,
                    // mounted AdFlowBanner/AdFlowNativeAd COLLAPSE to a zero
                    // footprint, and every future load/show is blocked
ads.enableAds();    // re-warms inventory at once; the widgets render again
ads.adsEnabled;     // ValueListenable<bool> — hide ad surfaces reactively
ads.canRequestAds;  // ValueListenable<bool> — the LIVE consent answer:
                    // follows a late consent grant AND a withdrawal, unlike
                    // the one-shot whenReady snapshot

ads.onPaidEvent = (e) => analytics.logAdImpression(
  value: e.valueMicros / 1e6,
  currency: e.currencyCode,
  adFormat: e.slot,          // 'banner', 'interstitial', …
  adSource: e.adSourceName,  // winning mediation network, when known
);

ads.interstitial.response;   // AdResponseSummary? — which network filled the
                             // warm ad (mediation diagnostics)

await ads.openAdInspector(); // debug overlay on a test device
```

### Emergency kill switch

`disableAds()` is also your remote kill switch: gate it on a remote flag so
you can stop serving ads fleet-wide without an app update (an AdMob policy
review, a broken mediation adapter, a bad creative):

```dart
// e.g. Firebase Remote Config, at startup and on config refresh:
if (remoteConfig.getBool('ads_kill_switch')) {
  ads.disableAds();
} else {
  ads.enableAds();
}
```

### "Why aren't my ads showing?"

A refused **load** is a first-class state: the slot reports
`AdBlocked(reason)` instead of an ambiguous idle, so
`ValueListenableBuilder` UIs can react to it directly. Refused **shows**
(a frequency cap, user-action pacing) never change the load state — they
report through the callback channel:

```dart
ads.onAdBlocked = (slot, reason) =>
    log.info('ad_flow: $slot blocked — ${reason.name}');

ads.interstitial.lastBlockReason; // AdBlockReason? — per-slot snapshot
```

`AdBlockReason` is one of `adsDisabled` (Remove-Ads on), `consentNotGranted`
(the user declined, or consent hasn't succeeded yet — e.g. offline),
`frequencyCapped`, `otherAdShowing`, `notReady` (nothing warm yet),
`userActionPacing`, `expired` (a stale ad past its `maxAdAge`), `introSkipped`
(the user skipped the rewarded intro), `requestConfigNotApplied` (request
configuration not applied yet under a fail-closed policy — see below),
`internalError` (a collaborator/gate fault — blocks new loads on a backoff but
never drops a live ad), and `consentNotForwarded` (you supplied
`forwardConsent` and it has not succeeded yet — see
[Mediation](#9-mediation)).

Most reasons are **normal** — a cap doing its job, a user declining an ad. This
is a diagnostic channel, not an error channel. Wire it to your logger during a
rollout and you can see, per app, exactly why a slot is quiet.

### Reliability defaults worth knowing

- **Request configuration fails closed when it matters**
  (`AdFlowConfig.requestConfigPolicy`, default `auto`): if
  `updateRequestConfiguration` fails and your config carries policy-critical
  fields (COPPA/under-age tags, content rating, test devices), loads block
  (`AdBlocked(requestConfigNotApplied)`) and recover when the retried apply
  succeeds, instead of silently sending untagged requests.
- **Every load has a watchdog** (`RetryConfig.loadTimeout`, default 60s): a
  lost SDK load callback fails the attempt into the normal retry path instead
  of pinning the slot forever.
- **Nothing busy-loops.** Retries back off exponentially with jitter; a closed
  gate is re-checked at most once a second and a failing load re-arms at most
  once a second, whatever `RetryConfig` says.

## 7. Testing your integration

```dart
import 'package:ad_flow/ad_flow_testing.dart';

final sdk = FakeAdSdk()..canRequestAdsResult = true;
final ads = await AdFlow.initialize(
  config,
  sdk: sdk,
  store: InMemoryKeyValueStore(),
  platform: AdPlatform.android,
);

// initialize() is NON-BLOCKING: it returns before consent resolves, so at this
// point nothing has preloaded yet. In a test, wait for the background startup
// (and then for the preload itself) before asserting on loaded ads — otherwise
// `sdk.interstitials` is still empty.
await ads.whenReady;
await pumpEventQueue(); // flutter_test; or `await Future<void>.delayed(...)`

await ads.interstitial.show();
sdk.interstitials.single.simulateDismissed(); // drive SDK behavior
```

`FakeAdSdk` also models the failure modes worth testing: `consentUpdateError`
(an offline launch), `onConsentInfoUpdate` (the network coming back),
`alwaysLoadError` / `nextLoadError` (no-fill), `loadHold` and `initializeHold`
(a hung network), and `enforceConsentGate = true`, which throws if anything
requests an ad before consent allows it.

## 8. Next-Gen SDK (experimental, Android-only)

The v9 plugin can swap its native Android dependency to Google's Next-Gen
GMA SDK at build time — same Dart API, no code changes:

```sh
flutter build apk --dart-define=USE_NEXT_GEN_SDK=true
```

iOS ignores the flag. It is experimental in Flutter; keep it off in
production until Google declares Flutter support GA.

## 9. Mediation

Add the official `gma_mediation_*` adapter packages (current releases all
support `google_mobile_ads` 9.x), select the partners in AdMob's *Privacy &
messaging*, and — on iOS — add the partners' `SKAdNetworkItems` to
`Info.plist`. Ads then flow with no ad_flow changes.

**Consent forwarding is NOT automatic for every network** (Google's own
partner pages say so explicitly). UMP collects consent and writes the IAB
TCF/AC/GPP strings; TCF-reading SDKs (e.g. AppLovin 12+) pick them up, but
networks like Unity (MetaData calls) or Meta (Limited Data Use) need their
own APIs called — some *before* their SDK initializes. ad_flow gives you
the hooks: the **`forwardConsent`** barrier on `initialize` (runs before
`MobileAds.initialize()`, fail-closed by default: a failed forward keeps the
SDK uninitialized and loads blocked as `AdBlocked(consentNotForwarded)` until
it succeeds), `AdFlow.onConsentChanged` (a fire-and-forget hook), and per-slot
`AdRequestOptions.mediationExtras`. The full per-network guide is
[doc/MEDIATION_SETUP.md](doc/MEDIATION_SETUP.md) — read it before shipping
mediation.

## 10. Policy compliance checklist

- [ ] `app-ads.txt` published and verified (required since Jan 2025)
- [ ] Production ad unit IDs only in `AdFlowConfig`; `testMode` off
- [ ] Never click your own live ads; use test ads / registered test devices
- [ ] Interstitials only at natural breaks (`recordUserAction` pacing on)
- [ ] Banners not flush against tappable controls
- [ ] App open not combined with a banner on the same surface
- [ ] Privacy-options button reachable (e.g. in settings)
- [ ] Rewarded interstitial intro copy states the reward clearly
- [ ] iOS: `NSUserTrackingUsageDescription` in `Info.plist` (required whenever
      you pass `attExplainer` — iOS terminates the app on the ATT prompt
      without it)
- [ ] iOS: `SKAdNetworkItems` in `Info.plist` (see §2 — missing entries cost
      real iOS revenue silently)
- [ ] iOS ATT — pick exactly ONE, never both:
  - **client-driven** (you pass `attExplainer`): do **not** configure the IDFA
    message in the AdMob console, or the user is prompted twice;
  - **UMP-driven** (no `attExplainer`): configure the IDFA message in the AdMob
    console and let UMP show it.

## License

MIT — see [LICENSE](LICENSE).
