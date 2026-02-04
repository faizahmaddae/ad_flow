// ============================================================
// EXAMPLE: Non-Blocking Initialization (Best UX)
// ============================================================
// This example demonstrates the RECOMMENDED approach for fast
// app startup. Instead of blocking on AdFlow initialization,
// we start the app immediately and let ads load reactively.
//
// Benefits:
// - App starts instantly (no waiting for slow networks)
// - Widgets automatically show ads when ready
// - Better user experience, especially on slow connections
//
// Features demonstrated:
// - Non-blocking initialization (fire-and-forget)
// - Reactive EasyBannerAd (auto-loads when AdFlow ready)
// - waitForInit() for custom ad loading
// - initStream for monitoring initialization
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Run app IMMEDIATELY - no blocking!
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdFlow Non-Blocking Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // Go straight to home - no splash screen needed!
      home: const HomePage(),
    );
  }
}

// ============================================================
// HOME PAGE - Initialize AdFlow without blocking UI
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _adFlowReady = false;
  String _statusText = 'Initializing ads...';
  StreamSubscription<bool>? _initSubscription;

  @override
  void initState() {
    super.initState();

    // Listen to initialization completion
    _initSubscription = AdFlow.instance.initStream.listen((_) {
      if (mounted) {
        setState(() {
          _adFlowReady = true;
          _statusText = 'Ads ready!';
        });
      }
    });

    // Start initialization AFTER first frame (needs context)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNonBlockingInit();
    });
  }

  @override
  void dispose() {
    _initSubscription?.cancel();
    super.dispose();
  }

  /// Non-blocking initialization - fire and forget!
  void _startNonBlockingInit() {
    // ============================================================
    // AUTOMATIC PRELOADING (via initialize parameters)
    // ============================================================
    // Ads are preloaded automatically after consent completes.
    // This is the recommended approach - no manual loading needed!

    AdFlow.instance.initializeWithExplainer(
      context: context,
      config: AdFlowConfig.testMode(),

      // 🔹 preloadInterstitial: Loads interstitial in background after init
      // Ready to show immediately when needed (e.g., level complete)
      preloadInterstitial: true,

      // 🔹 preloadRewarded: Loads rewarded ad in background after init
      // Ready for "Watch ad for reward" button
      preloadRewarded: true,

      // 🔹 preloadAppOpen: Loads app open ad in background after init
      // Used with enableAppOpenOnForeground for auto-show on resume
      preloadAppOpen: true,

      // 🔹 showAppOpenOnColdStart: Shows app open ad on first launch
      // Waits briefly (coldStartAdTimeout) for ad to load, then shows
      showAppOpenOnColdStart: true,

      // 🔹 enableAppOpenOnForeground: Auto-shows app open when app resumes
      // Combined with preloadAppOpen for seamless foreground ads
      enableAppOpenOnForeground: true,

      // 🔹 maxForegroundAdsPerSession: Limits foreground ads (0 = unlimited)
      maxForegroundAdsPerSession: 2,

      onComplete: (canRequestAds) {
        debugPrint('AdFlow init complete! canRequestAds: $canRequestAds');
        // At this point, all preloaded ads are ready (if canRequestAds is true)
      },
    );

    // ============================================================
    // ALTERNATIVE: Initialize without explainer dialog
    // ============================================================
    // AdFlow.instance.initialize(
    //   config: AdFlowConfig.testMode(),
    //   preloadInterstitial: true,
    //   preloadRewarded: true,
    //   preloadAppOpen: true,
    //   onComplete: (canRequestAds) {
    //     debugPrint('AdFlow init complete! canRequestAds: $canRequestAds');
    //   },
    // );
  }

  // ============================================================
  // MANUAL PRELOADING (call loadAd() directly)
  // ============================================================
  // Use this when you need more control over when ads load,
  // or want to load ads at specific points in your app.

  /// Manually preload all ad types after initialization
  Future<void> _manualPreloadAllAds() async {
    // First, wait for AdFlow to be ready
    final isReady = await AdFlow.instance.waitForInit();
    if (!isReady) {
      debugPrint('Cannot preload - ads not available');
      return;
    }

    // 🔹 Manual Interstitial preload
    // Load without showing - ready for later use
    await AdFlow.instance.interstitial.loadAd(
      onAdLoaded: (_) => debugPrint('Interstitial preloaded!'),
      onAdFailedToLoad: (error) =>
          debugPrint('Interstitial failed: ${error.message}'),
    );

    // 🔹 Manual Rewarded preload
    // Load without showing - ready for "Watch ad" button
    await AdFlow.instance.rewarded.loadAd(
      onAdLoaded: (_) => debugPrint('Rewarded preloaded!'),
      onAdFailedToLoad: (error) =>
          debugPrint('Rewarded failed: ${error.message}'),
    );

    // 🔹 Manual App Open preload
    // Load without showing - ready for foreground events
    await AdFlow.instance.appOpen.loadAd(
      onAdLoaded: (_) => debugPrint('App Open preloaded!'),
      onAdFailedToLoad: (error) =>
          debugPrint('App Open failed: ${error.message}'),
    );
  }

  /// Preload a single ad type on-demand
  Future<void> _preloadInterstitialOnly() async {
    final isReady = await AdFlow.instance.waitForInit();
    if (!isReady) return;

    // Check if already loaded to avoid duplicate requests
    if (AdFlow.instance.interstitial.isLoaded) {
      debugPrint('Interstitial already loaded');
      return;
    }

    await AdFlow.instance.interstitial.loadAd();
  }

  /// Use preloadAds() for smart preloading based on config
  Future<void> _smartPreload() async {
    final isReady = await AdFlow.instance.waitForInit();
    if (!isReady) return;

    // preloadAds() only loads ad types that have production IDs configured
    // Safe to call even if you only use some ad types
    await AdFlow.instance.preloadAds();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Non-Blocking Init Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          _buildStatusCard(),
          const SizedBox(height: 16),

          // Banner ad - loads automatically when AdFlow ready!
          _buildBannerSection(),
          const SizedBox(height: 16),

          // Interstitial controls
          _buildInterstitialSection(),
          const SizedBox(height: 16),

          // Custom loading example
          _buildCustomLoadingExample(),
          const SizedBox(height: 16),

          // Manual preloading example
          _buildManualPreloadSection(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _adFlowReady ? Icons.check_circle : Icons.hourglass_empty,
              color: _adFlowReady ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _adFlowReady
                        ? 'Ads will load and show normally'
                        : 'App is usable while ads initialize',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reactive Banner Ad',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'EasyBannerAd automatically waits for AdFlow to initialize, '
              'then loads the ad. No extra code needed!',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // This widget is REACTIVE - it subscribes to initStream
            // and auto-loads when AdFlow is ready
            const EasyBannerAd(),
          ],
        ),
      ),
    );
  }

  Widget _buildInterstitialSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interstitial Ad',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'For fullscreen ads, use waitForInit() to ensure AdFlow '
              'is ready before showing.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showInterstitial,
                icon: const Icon(Icons.fullscreen),
                label: const Text('Show Interstitial'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomLoadingExample() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Custom Ad Loading',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use waitForInit() when you need to perform custom '
              'ad operations after initialization.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadCustomAd,
                icon: const Icon(Icons.download),
                label: const Text('Load Rewarded Ad'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualPreloadSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Preloading',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Alternatively, load ads manually with full control over timing and callbacks.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _preloadInterstitialOnly,
                  icon: const Icon(Icons.rectangle_outlined, size: 18),
                  label: const Text('Preload Interstitial'),
                ),
                OutlinedButton.icon(
                  onPressed: _manualPreloadAllAds,
                  icon: const Icon(Icons.download_for_offline, size: 18),
                  label: const Text('Preload All'),
                ),
                OutlinedButton.icon(
                  onPressed: _smartPreload,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Smart Preload'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInterstitial() async {
    // Wait for AdFlow to be ready (returns immediately if already ready)
    final isReady = await AdFlow.instance.waitForInit();

    if (!isReady) {
      _showSnackBar('Ads not available (consent not granted)');
      return;
    }

    // Check if interstitial is loaded
    if (AdFlow.instance.interstitial.isLoaded) {
      await AdFlow.instance.interstitial.showAd();
    } else {
      _showSnackBar('Interstitial not loaded yet, loading now...');
      await AdFlow.instance.interstitial.loadAd();
    }
  }

  Future<void> _loadCustomAd() async {
    // Wait for AdFlow to be ready
    final isReady = await AdFlow.instance.waitForInit();

    if (!isReady) {
      _showSnackBar('Ads not available');
      return;
    }

    // Check if already loaded
    if (AdFlow.instance.rewarded.isLoaded) {
      _showSnackBar('Rewarded ad ready! Showing...');
      await _showRewardedAd();
      return;
    }

    _showSnackBar('Loading rewarded ad...');

    // Manual load with callbacks
    await AdFlow.instance.rewarded.loadAd(
      onAdLoaded: (_) {
        _showSnackBar('Rewarded ad loaded!');
        // Optionally show immediately after load
        // _showRewardedAd();
      },
      onAdFailedToLoad: (error) => _showSnackBar('Failed: ${error.message}'),
    );
  }

  Future<void> _showRewardedAd() async {
    if (!AdFlow.instance.rewarded.isLoaded) {
      _showSnackBar('No rewarded ad loaded');
      return;
    }

    await AdFlow.instance.rewarded.showAd(
      onUserEarnedReward: (reward) {
        // 🎁 Grant the reward to user!
        _showSnackBar('Earned ${reward.amount} ${reward.type}!');
      },
      onAdDismissed: () {
        debugPrint('Rewarded ad dismissed');
        // Ad auto-reloads after dismiss
      },
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

// ============================================================
// ALTERNATIVE: Using initStream for complex scenarios
// ============================================================
// If you need more control over when ads load, use initStream:
//
// ⚠️ IMPORTANT: Always cancel stream subscriptions in dispose()!
// Failure to cancel causes memory leaks in navigable pages.
// Only main.dart (app-level) subscriptions are safe without cancel.
//
// class _MyWidgetState extends State<MyWidget> {
//   StreamSubscription<bool>? _initSub;
//
//   @override
//   void initState() {
//     super.initState();
//     if (AdFlow.instance.isInitialized) {
//       _loadMyAds();
//     } else {
//       _initSub = AdFlow.instance.initStream.listen((_) {
//         _loadMyAds();
//       });
//     }
//   }
//
//   @override
//   void dispose() {
//     _initSub?.cancel();  // ⚠️ REQUIRED to prevent memory leak!
//     super.dispose();
//   }
//
//   void _loadMyAds() {
//     // Your custom ad loading logic
//   }
// }
// ============================================================

// ============================================================
// PRELOADING COMPARISON
// ============================================================
//
// 📦 AUTOMATIC (via initialize params) - RECOMMENDED
// ------------------------------------------------
// Pros: Simple, runs in background, no extra code
// Cons: Less control over timing
//
// AdFlow.instance.initialize(
//   preloadInterstitial: true,  // Auto-loads after consent
//   preloadRewarded: true,      // Auto-loads after consent
//   preloadAppOpen: true,       // Auto-loads after consent
// );
//
// 🔧 MANUAL (call loadAd() directly)
// ------------------------------------------------
// Pros: Full control, load on-demand, custom callbacks
// Cons: More code, must handle timing yourself
//
// await AdFlow.instance.waitForInit();
// await AdFlow.instance.interstitial.loadAd();
// await AdFlow.instance.rewarded.loadAd();
// await AdFlow.instance.appOpen.loadAd();
//
// 🎯 SMART (preloadAds method)
// ------------------------------------------------
// Pros: Only loads ad types with production IDs configured
// Cons: Requires production config (not test mode)
//
// await AdFlow.instance.preloadAds();
//
// ============================================================
