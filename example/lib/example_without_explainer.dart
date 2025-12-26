// ============================================================
// EXAMPLE 2: Initialization WITHOUT Explainer Dialog
// ============================================================
// This example initializes AdFlow directly without showing
// an explainer dialog. The system consent popups (GDPR, ATT)
// will appear directly.
//
// Use this approach when:
// - You have your own onboarding flow
// - You want minimal interruption
// - You're not in GDPR regions
//
// Features demonstrated:
// - Banner ads (adaptive)
// - App Open ads (cold start)
// - Interstitial ads (with preload and cooldown)
// - Reactive UI updates
// ============================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AdFlow BEFORE runApp (no context needed)
  await AdFlow.instance.initialize(
    // Use test mode during development
    // In production, use AdFlowConfig with your real ad unit IDs:
    //
    // config: AdFlowConfig(
    //   androidBannerAdUnitId: 'ca-app-pub-xxx/xxx',
    //   iosBannerAdUnitId: 'ca-app-pub-xxx/xxx',
    //   androidInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
    //   iosInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
    //   androidAppOpenAdUnitId: 'ca-app-pub-xxx/xxx',
    //   iosAppOpenAdUnitId: 'ca-app-pub-xxx/xxx',
    // ),
    config: AdFlowConfig.testMode(),

    // Preload interstitial ad immediately after init
    preloadInterstitial: true,

    // Preload and show app open ad on cold start
    preloadAppOpen: true,
    showAppOpenOnColdStart: true,

    // Enable app open ads when app comes to foreground
    enableAppOpenOnForeground: true,
    maxForegroundAdsPerSession: 2, // Limit foreground ads per session
    // Callback when initialization completes
    onComplete: (canRequestAds) {
      debugPrint('AdFlow initialized. Can request ads: $canRequestAds');
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdFlow Example (Without Explainer)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// HOME PAGE - Main App with Ads
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _interstitialClickCount = 0;

  @override
  void initState() {
    super.initState();
    // Listen to interstitial status changes for reactive UI
    AdFlow.instance.interstitial.addStatusListener(
      _onInterstitialStatusChanged,
    );
  }

  @override
  void dispose() {
    AdFlow.instance.interstitial.removeStatusListener(
      _onInterstitialStatusChanged,
    );
    super.dispose();
  }

  void _onInterstitialStatusChanged() {
    // Rebuild UI when interstitial status changes
    if (mounted) setState(() {});
  }

  Future<void> _showInterstitial() async {
    _interstitialClickCount++;

    // Show interstitial (respects cooldown automatically)
    final shown = await AdFlow.instance.interstitial.showAd(
      onAdDismissed: () {
        debugPrint('Interstitial dismissed');
        // Reload for next time
        AdFlow.instance.interstitial.loadAd();
      },
      onAdFailedToShow: () {
        debugPrint('Interstitial failed to show');
        // Reload on failure
        AdFlow.instance.interstitial.loadAd();
      },
    );

    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AdFlow.instance.interstitial.isLoaded
                ? 'Cooldown active - wait before showing again'
                : 'Interstitial not ready yet',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final interstitial = AdFlow.instance.interstitial;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AdFlow Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Privacy settings button (auto-hides if not required)
          const EasyPrivacySettingsButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ad Status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _StatusRow(
                    label: 'Interstitial',
                    isLoaded: interstitial.isLoaded,
                    isLoading: interstitial.isLoading,
                  ),
                  _StatusRow(
                    label: 'Can Show',
                    isLoaded: interstitial.canShowAd,
                    isLoading: false,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Interstitial Button
          ElevatedButton.icon(
            onPressed: _showInterstitial,
            icon: const Icon(Icons.fullscreen),
            label: Text(
              'Show Interstitial (Clicked: $_interstitialClickCount)',
            ),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),

          const SizedBox(height: 8),

          // Manual reload button
          OutlinedButton.icon(
            onPressed: interstitial.isLoading
                ? null
                : () => AdFlow.instance.interstitial.loadAd(),
            icon: const Icon(Icons.refresh),
            label: Text(
              interstitial.isLoading ? 'Loading...' : 'Reload Interstitial',
            ),
          ),

          const SizedBox(height: 24),

          // Info Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How This Example Works',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Direct initialization (no explainer)\n'
                    '• App Open ad shown on cold start\n'
                    '• Interstitial preloaded and ready\n'
                    '• Banner ad at bottom of screen\n'
                    '• 30-second cooldown between interstitials',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Banner Ad at bottom
      bottomNavigationBar: const SafeArea(child: EasyBannerAd()),
    );
  }
}

// ============================================================
// Helper Widget - Status Row
// ============================================================
class _StatusRow extends StatelessWidget {
  final String label;
  final bool isLoaded;
  final bool isLoading;

  const _StatusRow({
    required this.label,
    required this.isLoaded,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Row(
            children: [
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  isLoaded ? Icons.check_circle : Icons.cancel,
                  color: isLoaded ? Colors.green : Colors.red,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Text(
                isLoading
                    ? 'Loading'
                    : isLoaded
                    ? 'Ready'
                    : 'Not Ready',
                style: TextStyle(
                  color: isLoading
                      ? Colors.orange
                      : isLoaded
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
