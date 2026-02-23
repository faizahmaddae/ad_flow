// ============================================================================
// AdFlow — Example Launcher
// ============================================================================
// Initializes AdFlow once, then lets you pick any focused example:
//
//   • All Ads      — Every ad type in one page
//   • Banner       — EasyBannerAd + manual BannerAdManager
//   • Interstitial — Preloaded, manual, cooldown, every-N-actions
//   • Rewarded     — Load/show, reactive button, reward tracking
//   • Native       — EasyNativeAd + manual NativeAdManager
//   • App Open     — Auto foreground, pause/resume, manual
//
// Run:  cd example && flutter run
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

import 'example_all_ads.dart';
import 'example_banner.dart';
import 'example_interstitial.dart';
import 'example_rewarded.dart';
import 'example_native.dart';
import 'example_app_open.dart';

// ============================================================================
// MEDIATION SETUP (Optional — uncomment when adapters support GMA ^7.0.0)
// ============================================================================
// import 'package:gma_mediation_unity/gma_mediation_unity.dart';
// import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';
// import 'package:gma_mediation_meta/gma_mediation_meta.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------
  // Register mediation adapters BEFORE initialization (if using any)
  // ------------------------------------------------------------------
  // final unity = GmaMediationUnity();
  // MediationHelper.registerUnityWithCallbacks(
  //   setGDPRConsent: unity.setGDPRConsent,
  //   setCCPAConsent: unity.setCCPAConsent,
  // );

  // final applovin = GmaMediationApplovin();
  // MediationHelper.registerApplovinWithCallbacks(
  //   setHasUserConsent: applovin.setHasUserConsent,
  //   setDoNotSell: applovin.setDoNotSell,
  // );

  // Meta Audience Network reads consent automatically from UMP/ATT:
  // MediationHelper.registerMetaAdapter();

  // ------------------------------------------------------------------
  // Global error handling — log every ad error to your analytics
  // ------------------------------------------------------------------
  AdFlow.instance.setErrorCallback((error) {
    debugPrint('[AdFlow Error] ${error.type.name}: ${error.message}');
  });

  runApp(const AdFlowExampleApp());
}

// ============================================================================
// APP
// ============================================================================
class AdFlowExampleApp extends StatelessWidget {
  const AdFlowExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdFlow Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LauncherPage(),
    );
  }
}

// ============================================================================
// LAUNCHER PAGE
// ============================================================================
class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key});

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  bool _adFlowInitialized = false;
  bool _canRequestAds = false;
  StreamSubscription<bool>? _initSub;

  @override
  void initState() {
    super.initState();

    _initSub = AdFlow.instance.initStream.listen((canRequestAds) {
      if (mounted) {
        setState(() {
          _adFlowInitialized = true;
          _canRequestAds = canRequestAds;
        });
      }
    });

    // Initialize after first frame (needs BuildContext for explainer dialog)
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAdFlow());
  }

  @override
  void dispose() {
    _initSub?.cancel();
    super.dispose();
  }

  void _initAdFlow() {
    AdFlow.instance.initializeWithExplainer(
      context: context,
      config: AdFlowConfig.testMode(),
      preloadInterstitial: true,
      preloadRewarded: true,
      preloadAppOpen: true,
      showAppOpenOnColdStart: true,
      enableAppOpenOnForeground: true,
      maxForegroundAdsPerSession: 2,
      onComplete: (canRequestAds) {
        debugPrint('AdFlow ready — canRequestAds: $canRequestAds');
      },
    );
  }

  void _navigate(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdFlow Examples'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: const [EasyPrivacySettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Init status
          Card(
            child: ListTile(
              leading: Icon(
                _adFlowInitialized
                    ? (_canRequestAds ? Icons.check_circle : Icons.info)
                    : Icons.hourglass_top,
                color: _adFlowInitialized
                    ? (_canRequestAds ? Colors.green : Colors.orange)
                    : Colors.grey,
              ),
              title: Text(
                _adFlowInitialized
                    ? (_canRequestAds
                          ? 'AdFlow Ready'
                          : 'Initialized (No Consent)')
                    : 'Initializing…',
              ),
              subtitle: Text(
                _adFlowInitialized
                    ? (_canRequestAds
                          ? 'Tap any example below'
                          : 'Consent denied — ads will not load. Tap any example to explore the UI.')
                    : 'Ads loading in the background',
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Examples
          _ExampleTile(
            icon: Icons.dashboard,
            title: 'All Ads (Complete Demo)',
            subtitle:
                'Every ad type, remove ads, error stream — all in one page',
            onTap: () => _navigate(const AllAdsPage()),
          ),
          _ExampleTile(
            icon: Icons.view_agenda,
            title: 'Banner Ads',
            subtitle:
                'EasyBannerAd, adaptive, collapsible, fixed-size, manual control',
            onTap: () => _navigate(const BannerExamplePage()),
          ),
          _ExampleTile(
            icon: Icons.fullscreen,
            title: 'Interstitial Ads',
            subtitle: 'Preloaded show, manual load, cooldown, every-N-actions',
            onTap: () => _navigate(const InterstitialExamplePage()),
          ),
          _ExampleTile(
            icon: Icons.play_circle_outline,
            title: 'Rewarded Ads',
            subtitle: 'Watch ad for coins, reactive button, status listeners',
            onTap: () => _navigate(const RewardedExamplePage()),
          ),
          _ExampleTile(
            icon: Icons.article,
            title: 'Native Ads',
            subtitle: 'EasyNativeAd widget + manual NativeAdManager',
            onTap: () => _navigate(const NativeExamplePage()),
          ),
          _ExampleTile(
            icon: Icons.open_in_new,
            title: 'App Open Ads',
            subtitle: 'Automatic foreground ads, pause/resume, manual control',
            onTap: () => _navigate(const AppOpenExamplePage()),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED
// ============================================================================
class _ExampleTile extends StatelessWidget {
  const _ExampleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
