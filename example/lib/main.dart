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
  // `adSourceName` (2.2.0) carry the format and the winning mediation network,
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
    AdFlowConfig.test(),
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
    AdFlowConfig.test(),
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
      home: HomeScreen(ads: ads),
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

  // Create one controller per placement ONCE — never inside build(). Each
  // ads.banner()/ads.native() call mints a fresh controller and starts a
  // new ad load, so building them in build() would restart the load (and
  // blank the ad) on every setState — e.g. every time the coin count
  // changes. `ownsController: true` lets the hosting widget dispose these
  // when HomeScreen unmounts.
  late final _bannerController = ads.banner();
  late final _nativeController = ads.native();

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
                'Background the app, then return ONCE — it shows on that first '
                'warm return (never on a cold launch).',
            state: ads.appOpenController.state,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  const Text('Native (medium template)'),
                  const SizedBox(height: 8),
                  AdFlowNativeAd(
                    controller: _nativeController,
                    ownsController: true,
                  ),
                ],
              ),
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
      // Reserved height from the first frame — no layout shift.
      bottomNavigationBar: SafeArea(
        child: AdFlowBanner(
          controller: _bannerController,
          ownsController: true,
        ),
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
