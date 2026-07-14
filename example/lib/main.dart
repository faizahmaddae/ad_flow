import 'package:ad_flow/ad_flow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Global navigator key so the rewarded-interstitial intro screen can be
/// pushed from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  // Initialize WITHOUT blocking the first frame: runApp draws immediately,
  // the consent flow (and any UMP form) runs behind this Future.
  late final Future<AdFlow> _ads =
      AdFlow.initialize(
        // Google sample ads everywhere. Replace with your production config:
        //   AdFlowConfig(banner: BannerConfig(adUnitId: PlatformAdUnitId(...)))
        AdFlowConfig.test(),
        rewardedIntroPresenter: (content) async {
          final context = navigatorKey.currentContext;
          if (context == null || !context.mounted) return false;
          return RewardedIntroScreen.show(context, content);
        },
        // Opt-in priming screens (the v2 equivalent of v1's
        // initializeWithExplainer). Each presenter checks the navigatorKey's
        // context itself, so the package never holds a BuildContext. On iOS
        // the ATT primer runs before Apple's system prompt (client-driven
        // ATT); the consent primer runs before the UMP GDPR form (EEA only).
        // In this client-driven ATT mode, do NOT also configure the UMP IDFA
        // message in the AdMob console — it would double-prompt.
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
      ).then((ads) {
        ads.onPaidEvent = (event) => debugPrint(
          '[ad_flow] paid: ${event.adUnitId} '
          '${event.valueMicros / 1e6} ${event.currencyCode} '
          '(${event.precision.name})',
        );
        return ads;
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ad_flow example',
      navigatorKey: navigatorKey,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: FutureBuilder<AdFlow>(
        future: _ads,
        builder: (context, snapshot) {
          final ads = snapshot.data;
          if (ads == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return HomeScreen(ads: ads);
        },
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
                'Background the app, then return — it shows on the warm '
                'start (never on cold launch).',
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
        child: AdFlowBanner(controller: _bannerController, ownsController: true),
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
