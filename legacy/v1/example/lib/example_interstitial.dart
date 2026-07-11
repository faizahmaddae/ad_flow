// ============================================================================
// Interstitial Ads Example
// ============================================================================
// Demonstrates every interstitial pattern:
//
//   1. Show a preloaded ad (simplest)
//   2. Manual load → show with all callbacks
//   3. Show every N actions
//   4. Cooldown behavior + ignoreCooldown
//   5. Status listeners for reactive UI
//
// AdFlow is already initialized by main.dart with preloadInterstitial: true.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

import 'example_all_ads.dart';

class InterstitialExamplePage extends StatefulWidget {
  const InterstitialExamplePage({super.key});

  @override
  State<InterstitialExamplePage> createState() =>
      _InterstitialExamplePageState();
}

class _InterstitialExamplePageState extends State<InterstitialExamplePage> {
  int _showCount = 0;
  int _actionCount = 0;

  @override
  void initState() {
    super.initState();
    // Listen to ALL state changes (loading, loaded, showing, dismissed)
    AdFlow.instance.interstitial.addStatusListener(_rebuild);
  }

  @override
  void dispose() {
    AdFlow.instance.interstitial.removeStatusListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------------------
  // Pattern 1: Show preloaded ad
  // --------------------------------------------------------------------------
  Future<void> _showPreloaded() async {
    final shown = await AdFlow.instance.interstitial.showAd(
      onAdDismissed: () {
        debugPrint('Interstitial dismissed — continue your flow');
      },
      onAdFailedToShow: () {
        debugPrint('No ad to show — continue your flow anyway');
      },
    );

    if (shown) {
      setState(() => _showCount++);
    } else if (mounted) {
      _showSnack('Ad not ready or cooldown active');
    }
  }

  // --------------------------------------------------------------------------
  // Pattern 2: Manual load → show
  // --------------------------------------------------------------------------
  Future<void> _manualLoadAndShow() async {
    // Step 1: Load with callbacks
    await AdFlow.instance.interstitial.loadAd(
      onAdLoaded: (_) {
        debugPrint('Interstitial loaded — ready to show');
      },
      onAdFailedToLoad: (error) {
        debugPrint('Load failed: ${error.message} (code: ${error.code})');
        if (mounted) _showSnack('Load failed: ${error.message}');
      },
    );

    // Step 2: Show if loaded
    if (AdFlow.instance.interstitial.isLoaded) {
      final shown = await AdFlow.instance.interstitial.showAd(
        onAdDismissed: () {
          debugPrint('Ad dismissed');
          // Reload for next time
          AdFlow.instance.interstitial.loadAd();
        },
        onAdFailedToShow: () {
          debugPrint('Show failed');
        },
      );
      if (shown) setState(() => _showCount++);
    }
  }

  // --------------------------------------------------------------------------
  // Pattern 3: Show every N actions
  // --------------------------------------------------------------------------
  void _performAction() {
    setState(() => _actionCount++);

    // Show an interstitial every 5 actions
    if (_actionCount % 5 == 0) {
      if (AdFlow.instance.interstitial.isLoaded &&
          AdFlow.instance.interstitial.canShowAd) {
        AdFlow.instance.interstitial.showAd(
          onAdDismissed: () => AdFlow.instance.interstitial.loadAd(),
        );
        setState(() => _showCount++);
      }
    }
  }

  // --------------------------------------------------------------------------
  // Pattern 4: Ignore cooldown
  // --------------------------------------------------------------------------
  Future<void> _showIgnoringCooldown() async {
    final shown = await AdFlow.instance.interstitial.showAd(
      ignoreCooldown: true, // Bypass the 30-second cooldown
      onAdDismissed: () => AdFlow.instance.interstitial.loadAd(),
    );
    if (shown) {
      setState(() => _showCount++);
    } else if (mounted) {
      _showSnack('No ad loaded');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AdFlow.instance.interstitial;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interstitial Ads'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  StatusChip(
                    loaded: mgr.isLoaded,
                    loading: mgr.isLoading,
                    canShow: mgr.canShowAd,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Shown $_showCount times this session',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Pattern 1: Preloaded
          _SectionCard(
            number: '1',
            title: 'Show Preloaded',
            description:
                'Simplest approach — if preloadInterstitial was set during init, '
                'just call showAd(). The ad is already loaded.',
            child: FilledButton.icon(
              onPressed: _showPreloaded,
              icon: const Icon(Icons.fullscreen),
              label: const Text('Show Ad'),
            ),
          ),
          const SizedBox(height: 12),

          // Pattern 2: Manual
          _SectionCard(
            number: '2',
            title: 'Manual Load → Show',
            description:
                'Load the ad yourself with onAdLoaded / onAdFailedToLoad '
                'callbacks, then show when ready.',
            child: FilledButton.icon(
              onPressed: mgr.isLoading ? null : _manualLoadAndShow,
              icon: const Icon(Icons.download),
              label: const Text('Load & Show'),
            ),
          ),
          const SizedBox(height: 12),

          // Pattern 3: Every N actions
          _SectionCard(
            number: '3',
            title: 'Show Every 5 Actions',
            description:
                'Track user actions and show an ad every 5th action. '
                'Action count: $_actionCount (next ad at ${((_actionCount ~/ 5) + 1) * 5})',
            child: FilledButton.icon(
              onPressed: _performAction,
              icon: const Icon(Icons.touch_app),
              label: Text('Do Action ($_actionCount)'),
            ),
          ),
          const SizedBox(height: 12),

          // Pattern 4: Cooldown
          _SectionCard(
            number: '4',
            title: 'Cooldown & ignoreCooldown',
            description:
                'By default, there\'s a 30-second cooldown between interstitials. '
                'Use ignoreCooldown: true to bypass it.',
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showPreloaded,
                    icon: const Icon(Icons.timer),
                    label: const Text('With Cooldown'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showIgnoringCooldown,
                    icon: const Icon(Icons.timer_off),
                    label: const Text('Skip Cooldown'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Pattern 5: Reload
          _SectionCard(
            number: '5',
            title: 'Manual Reload',
            description: 'Reload the interstitial ad manually.',
            child: OutlinedButton.icon(
              onPressed: mgr.isLoading ? null : () => mgr.loadAd(),
              icon: const Icon(Icons.refresh),
              label: Text(mgr.isLoading ? 'Loading…' : 'Reload'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED SECTION CARD
// ============================================================================
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.title,
    required this.description,
    required this.child,
  });

  final String number;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(number, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
