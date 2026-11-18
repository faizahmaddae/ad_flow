import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:flutter/foundation.dart';
// Deprecated in Flutter 3.50 in favour of package:material_ui, which needs
// Flutter >= 3.47 and does not share Material types with apps on older
// Flutter; migrate once the package floor reaches 3.50.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

// ad_flow example — every ad format over Google's sample IDs, in BOTH of the
// two initialization modes:
//
//   • SIMPLE (useExplainer = false, the default and the recommended setup): the
//     minimal drop-in. UMP handles the whole consent flow, and — if you
//     configure the IDFA message in the AdMob console — the iOS ATT prompt
//     too, after the GDPR message. No client-side priming screens.
//
//   • WITH EXPLAINER (useExplainer = true): the same, PLUS opt-in priming
//     screens — your own consent primer before the UMP GDPR form (EEA) and
//     your own ATT primer before Apple's system prompt (client-driven ATT,
//     iOS). The order is fixed: the GDPR flow first, the tracking question
//     last (App Store Guideline 5.1.1(iv)).
//
// BOTH modes are NON-BLOCKING: AdFlow.initialize() builds the graph
// and returns immediately; consent, ATT and SDK init all run in the BACKGROUND.
// We render HomeScreen on the first frame and the consent / ATT / explainer
// screens appear OVER the already-visible app — never a splash gate.
//
// Flip the flag below to switch modes. (Non-const on purpose, so BOTH init
// helpers stay referenced and the example analyzes clean either way.)
bool useExplainer = false;

/// The app's navigator key. The ready-made presenters
/// (`RewardedIntroScreen.presenter(navigatorKey)` and friends) show their
/// screens on it — the package itself never holds a BuildContext.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NON-BLOCKING: initialize() returns on the next microtask — BEFORE consent /
  // ATT / SDK init, which run in the background. The `await` here only waits on
  // synchronous graph construction, never the network, so the first frame is
  // instant. NEVER gate your UI on this Future (that was v1's splash hang).
  final ads = await (useExplainer ? _initWithExplainer() : _initSimple());

  // Impression-level revenue (allowlisted AdMob accounts only). Assignable any
  // time — set it right after init so no paid event is missed. `slot` and
  // `adSourceName` carry the format and the winning mediation network, ready
  // for an analytics ad_impression event.
  ads.onPaidEvent = (event) => debugPrint(
    '[ad_flow] paid: ${event.slot}/${event.adUnitId} '
    '${event.valueMicros / 1e6} ${event.currencyCode} '
    '(${event.precision.name}'
    '${event.adSourceName == null ? '' : ', via ${event.adSourceName}'})',
  );

  // "Why aren't my ads showing?" — every refused load/show reports its reason
  // (consent pending, Remove-Ads, frequency cap, expiry…). Most reasons are
  // NORMAL; wire this to your logger during rollout.
  ads.onAdBlocked = (slot, reason) =>
      debugPrint('[ad_flow] $slot blocked: ${reason.name}');

  runApp(ExampleApp(ads: ads));
}

/// Every format, with Google's sample ad units standing in for your own.
///
/// Put your real `ca-app-pub-…/…` IDs here. Test ads need no switch: while
/// `testMode` is left out, debug builds serve Google's test ads automatically
/// and release builds serve the IDs below.
const _config = AdFlowConfig(
  banner: BannerConfig(adUnitId: TestAdUnitIds.banner),
  interstitial: InterstitialConfig(adUnitId: TestAdUnitIds.interstitial),
  rewarded: RewardedConfig(adUnitId: TestAdUnitIds.rewarded),
  rewardedInterstitial: RewardedInterstitialConfig(
    adUnitId: TestAdUnitIds.rewardedInterstitial,
  ),
  nativeAd: NativeConfig(
    adUnitId: TestAdUnitIds.native,
    templateKind: NativeTemplateKind.medium,
  ),
  appOpen: AppOpenConfig(adUnitId: TestAdUnitIds.appOpen),
);

/// SIMPLE mode — the minimal drop-in. UMP drives the whole consent flow (and
/// iOS ATT if you set the console IDFA message); no client-side priming.
///
/// `rewardedIntroPresenter` is still required because this config includes the
/// rewarded-interstitial format, whose intro + skip screen must always show
/// first (AdMob policy). Drop the `rewardedInterstitial` slot and you can drop
/// the presenter too.
Future<AdFlow> _initSimple() {
  return AdFlow.initialize(
    _config,
    rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
  );
}

/// WITH-EXPLAINER mode — everything in [_initSimple], PLUS opt-in priming
/// screens, shown on the navigatorKey by the ready-made presenters.
///
/// - `consentExplainer` shows your consent primer before the UMP GDPR form, and
///   only when a form will actually appear (EEA users only — non-EEA users
///   never see it).
/// - `attExplainer` shows your ATT primer, then (after a 200 ms delay) Apple's
///   system tracking prompt — client-driven ATT (iOS; a no-op elsewhere),
///   always AFTER the GDPR flow, and not at all for a user who just refused it.
///   In this mode do NOT also configure the UMP IDFA message in the AdMob
///   console.
Future<AdFlow> _initWithExplainer() {
  return AdFlow.initialize(
    _config,
    rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
    attExplainer: AttExplainerScreen.presenter(navigatorKey),
    consentExplainer: ConsentExplainerScreen.presenter(navigatorKey),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.ads, super.key});

  final AdFlow ads;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ad_flow example',
      navigatorKey: navigatorKey,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // Rendered IMMEDIATELY — no FutureBuilder<AdFlow> gate. Consent, ATT and
      // the explainer screens push over this via navigatorKey as they resolve.
      // StartupScreen is a real loading screen: it does its startup work, takes
      // the one-shot cold-launch app-open opportunity, then reveals HomeScreen.
      home: StartupScreen(ads: ads),
    );
  }
}

/// A real loading/startup screen — the correct place to take the one-shot
/// cold-launch app-open opportunity.
///
/// It renders its own UI immediately (never a blank/blocked first frame), does
/// the app's genuine startup work, then — right before entering main content —
/// calls [AppOpenAdManager.showAtLaunch]. That call waits a few seconds at most
/// for the app-open ad to load (never on a first launch, before consent), shows
/// it, and completes when the user closes it; then we enter the app.
class StartupScreen extends StatefulWidget {
  const StartupScreen({required this.ads, super.key});

  final AdFlow ads;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_startup());
  }

  Future<void> _startup() async {
    // Your genuine startup work goes here (restore state, remote config, warm
    // caches…). This example has none, so it only waits for the first frame to
    // paint — a real thing you'd do before an app-open ad, and NOT an
    // artificial delay. Do not busy-wait for an ad here.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    // Immediately before entering main content: take the cold-launch
    // opportunity. Waits up to 3 s for the ad, shows it and completes when it
    // closes — or at once when there is none. One-shot per process launch.
    await widget.ads.appOpen?.showAtLaunch();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(ads: widget.ads)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlutterLogo(size: 72),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading…'),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.ads, super.key});

  final AdFlow ads;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _coins = 0;

  AdFlow get ads => widget.ads;

  void _grantReward(RewardEarned reward) {
    setState(() => _coins += reward.amount.toInt());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Earned ${reward.amount} ${reward.type}!')),
    );
  }

  /// `show()` completes when the ad has CLOSED (or at once when nothing was
  /// shown) — this is where a game would start its next level.
  void _report(String format, AdShowResult result) {
    if (!mounted) return;
    final text = result.shown
        ? '$format closed — back in the app'
        : result.blockReason != null
        ? '$format not shown: ${result.blockReason!.name}'
        : '$format failed: ${result.error?.message}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    // A slot is null when it is not configured for this platform; this
    // example configures all of them, but `?.` / null checks are the habit.
    final interstitial = ads.interstitial;
    final rewarded = ads.rewarded;
    final rewardedInterstitial = ads.rewardedInterstitial;
    final appOpen = ads.appOpen;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ad_flow example'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('coins: $_coins'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (interstitial != null)
            _StateTile(
              title: 'Interstitial',
              subtitle: 'Natural breaks only; caps + action pacing apply.',
              state: interstitial.state,
              onPressed: () async {
                // Tell the pacer a natural break happened, then try to show.
                // `interstitial.canShow` answers "would it show now?" first,
                // if your game wants to decide whether to pause for it.
                interstitial.recordUserAction();
                _report('Interstitial', await interstitial.show());
              },
              buttonLabel: 'Show interstitial',
            ),
          if (rewarded != null)
            _StateTile(
              title: 'Rewarded',
              subtitle: 'User-initiated; grants coins via onReward.',
              state: rewarded.state,
              onPressed: () async => _report(
                'Rewarded ad',
                await rewarded.show(onReward: _grantReward),
              ),
              buttonLabel: 'Watch ad, earn coins',
            ),
          if (rewardedInterstitial != null)
            _StateTile(
              title: 'Rewarded interstitial',
              subtitle: 'Always shows the intro + skip screen first (policy).',
              state: rewardedInterstitial.state,
              onPressed: () async => _report(
                'Rewarded interstitial',
                await rewardedInterstitial.show(onReward: _grantReward),
              ),
              buttonLabel: 'Show rewarded interstitial',
            ),
          if (appOpen != null)
            _StateTile(
              title: 'App open',
              subtitle:
                  'Shows on a warm return, and at cold launch from the '
                  'startup screen (waits up to 3 s for the ad).',
              state: appOpen.controller.state,
            ),
          // Remove-Ads hides the WHOLE decorated Card — title, padding and
          // border — not just the ad inside it: AdFlowNativeAd collapses to
          // zero, but a parent decoration around it would stay visible (an
          // empty bordered card). The leading spacer is inside the conditional
          // so it disappears with the card.
          ValueListenableBuilder(
            valueListenable: ads.adsEnabled,
            builder: (context, enabled, _) => !enabled
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              const Text('Native (medium template)'),
                              const SizedBox(height: 8),
                              // The widget creates AND owns its controller, so
                              // a setState here can never restart (and blank)
                              // the ad.
                              AdFlowNativeAd(adFlow: ads),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: ads.adsEnabled,
            builder: (context, enabled, _) => SwitchListTile(
              title: const Text('Ads enabled (Remove-Ads toggle)'),
              value: enabled,
              onChanged: (v) => v ? ads.enableAds() : ads.disableAds(),
            ),
          ),
          PrivacyOptionsButton(consent: ads.consent),
          TextButton(
            onPressed: ads.openAdInspector,
            child: const Text('Open Ad Inspector'),
          ),
        ],
      ),
      // Reserved height from the first frame, then sized to exactly what the
      // SDK rendered; the widget owns its controller.
      //
      // `safeArea: true` keeps the banner clear of the home indicator, and the
      // inset collapses WITH the banner when ads are disabled — a SafeArea of
      // our own around it would leave an empty strip behind after Remove-Ads.
      //
      // `backgroundColor` is the anchored-adaptive companion: the slot is
      // anchored to its WIDTH, so a creative narrower or shorter than the slot
      // is centred by the SDK and the surround is left unpainted. An opaque
      // colour (Google's own guidance) keeps that reading as a frame rather
      // than a hole. It paints strictly BEHIND the ad.
      bottomNavigationBar: AdFlowBanner(
        adFlow: ads,
        safeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({
    required this.title,
    required this.subtitle,
    required this.state,
    this.onPressed,
    this.buttonLabel,
  });

  final String title;
  final String subtitle;
  final ValueListenable<AdLoadState> state;
  final VoidCallback? onPressed;
  final String? buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            ValueListenableBuilder(
              valueListenable: state,
              builder: (context, s, _) => Text(
                'state: ${switch (s) {
                  AdIdle() => 'idle',
                  AdLoading() => 'loading…',
                  AdLoaded() => 'ready',
                  AdShowing() => 'showing',
                  // A refused load is a state of its own — consent pending,
                  // Remove-Ads on, cap active… — not a bare 'idle'.
                  AdBlocked(:final reason) => 'blocked (${reason.name})',
                  AdFailed(:final error) => 'failed (${error.message})',
                }}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            if (buttonLabel != null)
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
