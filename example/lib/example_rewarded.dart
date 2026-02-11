// ============================================================================
// Rewarded Ads Example
// ============================================================================
// Demonstrates every rewarded ad pattern:
//
//   1. Basic load → show with reward callback
//   2. Reactive "Watch Ad" button with status listeners
//   3. Rewarded ads with "Remove Ads" (rewardedAdsIgnoreRemoveAds)
//   4. All callbacks explained
//
// AdFlow is already initialized by main.dart with preloadRewarded: true.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

import 'example_all_ads.dart';

class RewardedExamplePage extends StatefulWidget {
  const RewardedExamplePage({super.key});

  @override
  State<RewardedExamplePage> createState() => _RewardedExamplePageState();
}

class _RewardedExamplePageState extends State<RewardedExamplePage> {
  int _coins = 0;
  int _gems = 0;
  String _lastEvent = 'No events yet';

  @override
  void initState() {
    super.initState();
    AdFlow.instance.rewarded.addStatusListener(_rebuild);
  }

  @override
  void dispose() {
    AdFlow.instance.rewarded.removeStatusListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _log(String event) {
    setState(() => _lastEvent = event);
    debugPrint('Rewarded: $event');
  }

  // --------------------------------------------------------------------------
  // Pattern 1: Basic — load and show with all callbacks
  // --------------------------------------------------------------------------
  Future<void> _basicLoadAndShow() async {
    // Load
    await AdFlow.instance.rewarded.loadAd(
      onAdLoaded: (_) => _log('Ad loaded ✓'),
      onAdFailedToLoad: (error) =>
          _log('Load failed: ${error.message} (code: ${error.code})'),
    );

    if (!AdFlow.instance.rewarded.isLoaded) return;

    // Show
    final shown = await AdFlow.instance.rewarded.showAd(
      // REQUIRED — called when the user completes the ad
      onUserEarnedReward: (reward) {
        setState(() => _coins += reward.amount.toInt());
        _log('Earned ${reward.amount} ${reward.type}!');
      },
      // Optional — called when user closes the ad
      onAdDismissed: () {
        _log('Ad dismissed — reload for next time');
        AdFlow.instance.rewarded.loadAd();
      },
      // Optional — called if the ad fails to show
      onAdFailedToShow: () {
        _log('Failed to show');
      },
    );

    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rewarded ad not available')),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Pattern 2: Reactive button — only enabled when ad is ready
  // --------------------------------------------------------------------------
  Future<void> _watchForGems() async {
    await AdFlow.instance.rewarded.showAd(
      onUserEarnedReward: (reward) {
        setState(() => _gems += 5);
        _log('Earned 5 gems!');
      },
      onAdDismissed: () => AdFlow.instance.rewarded.loadAd(),
      onAdFailedToShow: () => _log('No ad available'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AdFlow.instance.rewarded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewarded Ads'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  StatusChip(loaded: mgr.isLoaded, loading: mgr.isLoading),
                  const SizedBox(height: 8),
                  Text(
                    'Last event: $_lastEvent',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Wallet ──
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _WalletItem(icon: Icons.monetization_on, label: 'Coins', value: _coins),
                  _WalletItem(icon: Icons.diamond, label: 'Gems', value: _gems),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Pattern 1: Basic ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Basic Load & Show',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manually load, then show with all callbacks: '
                    'onUserEarnedReward, onAdDismissed, onAdFailedToShow.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: mgr.isLoading ? null : _basicLoadAndShow,
                    icon: const Icon(Icons.download),
                    label: const Text('Load & Show for Coins'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Pattern 2: Reactive button ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2. Reactive "Watch Ad" Button',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Uses addStatusListener to rebuild when ad state changes. '
                    'Button is disabled until ad is loaded.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      // Only enable when ad is loaded (reactive via status listener)
                      onPressed: mgr.isLoaded ? _watchForGems : null,
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(
                        mgr.isLoaded
                            ? 'Watch Ad for 5 Gems'
                            : mgr.isLoading
                                ? 'Loading…'
                                : 'No Ad Available',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Pattern 3: Remove Ads behavior ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3. Remove Ads Behavior',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'By default, rewardedAdsIgnoreRemoveAds is true — '
                    'rewarded ads keep working even when "Remove Ads" is '
                    'purchased. Users who want rewards can still watch.\n\n'
                    'Set it to false in AdFlowConfig to block rewarded '
                    'ads along with all other ad types.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Reload button ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '4. Manual Reload',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rewarded ads auto-reload after being shown. '
                    'Use this to manually trigger a reload.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: mgr.isLoading
                        ? null
                        : () {
                            mgr.loadAd(
                              onAdLoaded: (_) => _log('Reloaded ✓'),
                              onAdFailedToLoad: (error) =>
                                  _log('Reload failed: ${error.message}'),
                            );
                          },
                    icon: const Icon(Icons.refresh),
                    label: Text(mgr.isLoading ? 'Loading…' : 'Reload'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WALLET ITEM
// ============================================================================
class _WalletItem extends StatelessWidget {
  const _WalletItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
