// ============================================================================
// All Ads — Complete Demo
// ============================================================================
// Shows every ad type, remove ads toggle, and error stream in one page.
// AdFlow is already initialized by main.dart — this page just uses it.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

class AllAdsPage extends StatefulWidget {
  const AllAdsPage({super.key});

  @override
  State<AllAdsPage> createState() => _AllAdsPageState();
}

class _AllAdsPageState extends State<AllAdsPage> {
  bool _adsEnabled = true;

  @override
  void initState() {
    super.initState();
    _adsEnabled = AdsEnabledManager.instance.isEnabled;
    AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);
  }

  @override
  void dispose() {
    AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
    super.dispose();
  }

  void _onAdsEnabledChanged(bool enabled) {
    if (mounted) setState(() => _adsEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Ads'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: const [EasyPrivacySettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RemoveAdsCard(adsEnabled: _adsEnabled),
          const SizedBox(height: 12),
          const _InterstitialCard(),
          const SizedBox(height: 12),
          const _RewardedCard(),
          const SizedBox(height: 12),
          const _NativeAdCard(),
          const SizedBox(height: 12),
          const _BannerShowcaseCard(),
          const SizedBox(height: 12),
          const _ErrorStreamCard(),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: EasyBannerAd()),
    );
  }
}

// ============================================================================
// REMOVE ADS
// ============================================================================
class _RemoveAdsCard extends StatelessWidget {
  const _RemoveAdsCard({required this.adsEnabled});
  final bool adsEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove Ads', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Simulates an in-app purchase. Disabling ads '
              'stops all ad loading/showing and persists across restarts.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  adsEnabled ? Icons.visibility : Icons.visibility_off,
                  color: adsEnabled ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(adsEnabled ? 'Ads Enabled' : 'Ads Disabled'),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () async {
                    if (adsEnabled) {
                      await AdFlow.instance.disableAds();
                    } else {
                      await AdFlow.instance.enableAds();
                      await AdFlow.instance.preloadAds();
                    }
                  },
                  child: Text(adsEnabled ? 'Disable' : 'Enable'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// INTERSTITIAL
// ============================================================================
class _InterstitialCard extends StatefulWidget {
  const _InterstitialCard();

  @override
  State<_InterstitialCard> createState() => _InterstitialCardState();
}

class _InterstitialCardState extends State<_InterstitialCard> {
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
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

  Future<void> _show() async {
    setState(() => _tapCount++);
    final shown = await AdFlow.instance.interstitial.showAd(
      onAdDismissed: () => AdFlow.instance.interstitial.loadAd(),
      onAdFailedToShow: () => AdFlow.instance.interstitial.loadAd(),
    );
    if (!shown && mounted) {
      final msg = AdFlow.instance.interstitial.isLoaded
          ? 'Cooldown active — wait before showing again'
          : 'Interstitial not loaded yet';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AdFlow.instance.interstitial;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interstitial',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            StatusChip(
              loaded: mgr.isLoaded,
              loading: mgr.isLoading,
              canShow: mgr.canShowAd,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _show,
              icon: const Icon(Icons.fullscreen),
              label: Text('Show ($_tapCount)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// REWARDED
// ============================================================================
class _RewardedCard extends StatefulWidget {
  const _RewardedCard();

  @override
  State<_RewardedCard> createState() => _RewardedCardState();
}

class _RewardedCardState extends State<_RewardedCard> {
  int _coins = 0;

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

  Future<void> _watchAd() async {
    if (!AdFlow.instance.rewarded.isLoaded) {
      await AdFlow.instance.rewarded.loadAd();
      return;
    }
    await AdFlow.instance.rewarded.showAd(
      onUserEarnedReward: (reward) {
        setState(() => _coins += reward.amount.toInt());
      },
      onAdDismissed: () => AdFlow.instance.rewarded.loadAd(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AdFlow.instance.rewarded;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rewarded', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            StatusChip(loaded: mgr.isLoaded, loading: mgr.isLoading),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _watchAd,
              icon: const Icon(Icons.play_circle_outline),
              label: Text('Watch Ad  (Coins: $_coins)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// NATIVE
// ============================================================================
class _NativeAdCard extends StatelessWidget {
  const _NativeAdCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Native Ad', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const SizedBox(
              height: 300,
              child: EasyNativeAd(factoryId: 'medium_template', height: 300),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BANNER SHOWCASE
// ============================================================================
class _BannerShowcaseCard extends StatelessWidget {
  const _BannerShowcaseCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Banner Variants',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text('Collapsible', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            const EasyBannerAd(collapsible: true),
            const SizedBox(height: 16),
            Text(
              'Fixed Size (320×50)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            const Center(child: EasyBannerAd(adSize: AdSize.banner)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR STREAM
// ============================================================================
class _ErrorStreamCard extends StatefulWidget {
  const _ErrorStreamCard();

  @override
  State<_ErrorStreamCard> createState() => _ErrorStreamCardState();
}

class _ErrorStreamCardState extends State<_ErrorStreamCard> {
  final List<String> _errors = [];
  StreamSubscription<AdFlowError>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AdFlow.instance.errorStream.listen((error) {
      if (mounted) {
        setState(() {
          _errors.insert(0, '${error.type.name}: ${error.message}');
          if (_errors.length > 10) _errors.removeLast();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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
                Text(
                  'Error Stream',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_errors.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _errors.clear()),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_errors.isEmpty)
              const Text(
                'No errors yet',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              )
            else
              ..._errors.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• $e',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED: Status chip (used across examples)
// ============================================================================
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.loaded,
    required this.loading,
    this.canShow,
  });

  final bool loaded;
  final bool loading;
  final bool? canShow;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _chip(
          loading
              ? 'Loading…'
              : loaded
              ? 'Loaded'
              : 'Not loaded',
          loading
              ? Colors.orange
              : loaded
              ? Colors.green
              : Colors.grey,
        ),
        if (canShow != null)
          _chip(
            canShow! ? 'Can show' : 'Cooldown',
            canShow! ? Colors.green : Colors.orange,
          ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
