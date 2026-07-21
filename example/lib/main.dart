import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ad_flow example — every ad format over Google's sample IDs, in BOTH of the
// two initialization modes:
//
//   • SIMPLE (useExplainer = false): the minimal drop-in. UMP handles the whole
//     consent flow, and — if you configure the IDFA message in the AdMob
//     console — the iOS ATT prompt too. No client-side priming screens.
//
//   • WITH EXPLAINER (useExplainer = true): the same, PLUS opt-in priming
//     screens — your own ATT primer before Apple's system prompt (client-driven
//     ATT, iOS) and your own consent primer before the UMP GDPR form (EEA).
//     Recommended for EEA audiences and iOS: a soft explainer lifts opt-in rates.
//
// BOTH modes are NON-BLOCKING (ADR-032): AdFlow.initialize() builds the graph
// and returns immediately; consent, ATT and SDK init all run in the BACKGROUND.
// We render HomeScreen on the first frame and the consent / ATT / explainer
// screens appear OVER the already-visible app — never a splash gate.
//
// Flip the flag below to switch modes. (Non-const on purpose, so BOTH init
// helpers stay referenced and the example analyzes clean either way.)
bool useExplainer = true;

/// Global navigator key so the consent/ATT/rewarded-intro presenters can push
/// screens from outside the widget tree (the package never holds a
/// BuildContext).
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
  // `adSourceName` (3.0.0) carry the format and the winning mediation network,
  // ready for an analytics ad_impression event.
  ads.onPaidEvent = (event) => debugPrint(
    '[ad_flow] paid: ${event.slot}/${event.adUnitId} '
    '${event.valueMicros / 1e6} ${event.currencyCode} '
    '(${event.precision.name}'
    '${event.adSourceName == null ? '' : ', via ${event.adSourceName}'})',
  );

  // "Why aren't my ads showing?" — every refused load/show reports its reason
  // (consent pending, Remove-Ads, frequency cap, expiry…). Most reasons are
  // NORMAL; wire this to your logger during rollout (2.1.0, ADR-045).
  ads.onAdBlocked = (slot, reason) =>
      debugPrint('[ad_flow] $slot blocked: ${reason.name}');

  runApp(ExampleApp(ads: ads));
}

/// SIMPLE mode's app-open config is `resumeOnly` (the default). This example
/// opts into `launchAndResume` so it can also demonstrate the cold-launch
/// opportunity below. Both helpers request it via `AdFlowConfig.test`.
const _appOpenTriggerMode = AppOpenTriggerMode.launchAndResume;

/// SIMPLE mode — the minimal drop-in. UMP drives the whole consent flow (and
/// iOS ATT if you set the console IDFA message); no client-side priming.
///
/// `rewardedIntroPresenter` is still required because this config includes the
/// rewarded-interstitial format, whose intro + skip screen must always show
/// first (AdMob policy). Drop the `rewardedInterstitial` slot and you can drop
/// the presenter too.
Future<AdFlow> _initSimple() {
  return AdFlow.initialize(
    // Google sample ads everywhere. Replace with your production config:
    //   AdFlowConfig(banner: BannerConfig(adUnitId: PlatformAdUnitId(...)), ...)
    AdFlowConfig.test(appOpenTriggerMode: _appOpenTriggerMode),
    rewardedIntroPresenter: (content) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      return RewardedIntroScreen.show(context, content);
    },
  );
}

/// WITH-EXPLAINER mode — everything in [_initSimple], PLUS opt-in priming
/// screens. Each presenter resolves the navigatorKey's context itself, so the
/// package never holds a BuildContext.
///
/// - `attExplainer` shows your ATT primer, then (after a 200 ms delay) Apple's
///   system tracking prompt — client-driven ATT (iOS; a no-op elsewhere). In
///   this mode do NOT also configure the UMP IDFA message in the AdMob console,
///   or the user sees two prompts.
/// - `consentExplainer` shows your consent primer before the UMP GDPR form, and
///   only when a form will actually appear (EEA users only — non-EEA users
///   never see it).
Future<AdFlow> _initWithExplainer() {
  return AdFlow.initialize(
    AdFlowConfig.test(appOpenTriggerMode: _appOpenTriggerMode),
    rewardedIntroPresenter: (content) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      return RewardedIntroScreen.show(context, content);
    },
    attExplainer: (content) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await AttExplainerScreen.show(context, content);
    },
    consentExplainer: (content) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await ConsentExplainerScreen.show(context, content);
    },
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
/// cold-launch app-open opportunity (5.1).
///
/// It renders its own UI immediately (never a blank/blocked first frame), does
/// the app's genuine startup work, then — right before entering main content —
/// calls [AppOpenAdManager.showAtLaunchIfReady]. That call NEVER waits for a
/// load: if an ad is not already warm at this instant (the usual case at a true
/// cold launch, since consent + the first load have not finished yet) it
/// returns false immediately and we proceed. So this screen exists to do work,
/// not to wait for an ad.
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
    // opportunity. Shows an already-ready ad (and awaits its dismissal); if
    // none is ready it returns false at once. One-shot per process launch.
    await widget.ads.appOpenOrNull?.showAtLaunchIfReady();
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

  @override
  Widget build(BuildContext context) {
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
          _StateTile(
            title: 'Interstitial',
            subtitle: 'Natural breaks only; caps + action pacing apply.',
            state: ads.interstitial.state,
            onPressed: () {
              // Tell the pacer a natural break happened, then try to show.
              ads.interstitial.recordUserAction();
              ads.interstitial.show();
            },
            buttonLabel: 'Show interstitial',
          ),
          _StateTile(
            title: 'Rewarded',
            subtitle: 'User-initiated; grants coins via onReward.',
            state: ads.rewarded.state,
            onPressed: () => ads.rewarded.show(onReward: _grantReward),
            buttonLabel: 'Watch ad, earn coins',
          ),
          _StateTile(
            title: 'Rewarded interstitial',
            subtitle: 'Always shows the intro + skip screen first (policy).',
            state: ads.rewardedInterstitial.state,
            onPressed: () =>
                ads.rewardedInterstitial.show(onReward: _grantReward),
            buttonLabel: 'Show rewarded interstitial',
          ),
          _StateTile(
            title: 'App open',
            subtitle:
                'launchAndResume: shows on the first warm return, and at cold '
                'launch via the startup screen when an ad is already ready.',
            state: ads.appOpenController.state,
          ),
          // Remove-Ads hides the WHOLE decorated Card — title, padding and
          // border — not just the ad inside it. A parent decoration wrapped
          // around a child that collapses to zero stays visible otherwise (an
          // empty bordered card), which is exactly the residual-surface bug
          // this release fixes. The leading spacer is inside the conditional so
          // it disappears with the card.
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
                              // Widget-first (3.0): the widget creates AND owns
                              // its controller internally, so the classic
                              // footgun — minting a fresh controller inside
                              // build(), restarting the load (and blanking the
                              // ad) on every setState — cannot happen.
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
      // Reserved height from the first frame — no layout shift. Widget-first
      // (3.0): AdFlowBanner creates and owns its controller.
      //
      // Remove-Ads must remove the COMPLETE bottom ad surface. Returning
      // SizedBox.shrink() BEFORE constructing SafeArea is the point: if the
      // banner merely collapsed to zero height INSIDE a retained SafeArea, the
      // safe-area inset would still reserve a strip of empty space at the
      // bottom. The parent surface has to go too.
      bottomNavigationBar: ValueListenableBuilder(
        valueListenable: ads.adsEnabled,
        builder: (context, enabled, _) => !enabled
            ? const SizedBox.shrink()
            : SafeArea(child: AdFlowBanner(adFlow: ads)),
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
                  // 3.0: a refused load is a first-class state — consent
                  // pending, Remove-Ads on, cap active… no more guessing
                  // from a bare 'idle'.
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
