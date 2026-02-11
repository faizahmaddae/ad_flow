// ============================================================================
// Banner Ads Example
// ============================================================================
// Demonstrates every way to show banner ads:
//
//   1. EasyBannerAd — Drop-in widget (zero boilerplate)
//   2. Adaptive banner via BannerAdManager (manual control)
//   3. Collapsible banner via BannerAdManager
//   4. Fixed-size banner
//
// AdFlow is already initialized by main.dart.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

class BannerExamplePage extends StatelessWidget {
  const BannerExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banner Ads'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _EasyBannerSection(),
          SizedBox(height: 24),
          _ManualBannerSection(),
          SizedBox(height: 24),
          _CollapsibleBannerSection(),
          SizedBox(height: 24),
          _FixedSizeBannerSection(),
          SizedBox(height: 24),
          _AllSizesSection(),
          SizedBox(height: 80),
        ],
      ),

      // Sticky adaptive banner in the bottom bar
      bottomNavigationBar: const SafeArea(child: EasyBannerAd()),
    );
  }
}

// ============================================================================
// 1. EASY BANNER — Zero boilerplate
// ============================================================================
class _EasyBannerSection extends StatelessWidget {
  const _EasyBannerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. EasyBannerAd (Drop-in)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Just place it in your widget tree. It handles init waiting, '
          'loading, Remove Ads, and disposal automatically.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: const EasyBannerAd(),
        ),
        const SizedBox(height: 8),
        Text(
          'Code: const EasyBannerAd()',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 2. MANUAL BANNER — Full control with BannerAdManager
// ============================================================================
class _ManualBannerSection extends StatefulWidget {
  const _ManualBannerSection();

  @override
  State<_ManualBannerSection> createState() => _ManualBannerSectionState();
}

class _ManualBannerSectionState extends State<_ManualBannerSection> {
  // Create your own BannerAdManager for full control
  final _manager = BannerAdManager();
  String _status = 'Not loaded';

  @override
  void initState() {
    super.initState();
    // Status listener — fires on every state change
    _manager.addStatusListener(_onStatusChanged);
  }

  @override
  void dispose() {
    _manager.removeStatusListener(_onStatusChanged);
    _manager.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {
      if (_manager.isLoading) {
        _status = 'Loading…';
      } else if (_manager.isLoaded) {
        _status = 'Loaded ✓';
      } else {
        _status = 'Not loaded';
      }
    });
  }

  Future<void> _loadBanner() async {
    await _manager.loadAdaptiveBanner(
      context: context,
      // onAdLoaded receives the BannerAd instance
      onAdLoaded: (ad) {
        debugPrint('Banner loaded: ${ad.adUnitId}');
      },
      // onAdFailedToLoad receives both the ad and the error
      onAdFailedToLoad: (ad, error) {
        debugPrint('Banner failed: ${error.message} (code: ${error.code})');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Banner failed: ${error.message}')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. Manual BannerAdManager',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Full control: create a BannerAdManager, load with callbacks, '
          'listen to status changes, and display the ad widget yourself.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _manager.isLoading ? null : _loadBanner,
              icon: const Icon(Icons.download),
              label: const Text('Load Adaptive'),
            ),
            const SizedBox(width: 12),
            Chip(
              label: Text(_status, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_manager.isLoaded)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(4),
            child: _manager.buildAdWidget(),
          )
        else
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'Tap "Load Adaptive" to load a banner',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// 3. COLLAPSIBLE BANNER
// ============================================================================
class _CollapsibleBannerSection extends StatelessWidget {
  const _CollapsibleBannerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. Collapsible Banner',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Starts expanded, then collapses after a few seconds. '
          'Users can expand again by tapping.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: const EasyBannerAd(collapsible: true),
        ),
        const SizedBox(height: 8),
        Text(
          'Code: const EasyBannerAd(collapsible: true)',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 4. FIXED-SIZE BANNER
// ============================================================================
class _FixedSizeBannerSection extends StatelessWidget {
  const _FixedSizeBannerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '4. Fixed-Size Banner',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Use a specific AdSize instead of adaptive. Good for dialogs, '
          'cards, or specific layout requirements.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: const Center(
            child: EasyBannerAd(adSize: AdSize.mediumRectangle), // 300×250
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Code: const EasyBannerAd(adSize: AdSize.mediumRectangle)',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 5. ALL COMMON SIZES
// ============================================================================
class _AllSizesSection extends StatelessWidget {
  const _AllSizesSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '5. Common Banner Sizes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _sizeRow('AdSize.banner', '320×50', AdSize.banner),
        const Divider(),
        _sizeRow('AdSize.largeBanner', '320×100', AdSize.largeBanner),
        const Divider(),
        _sizeRow('Adaptive', 'Full width', null),
      ],
    );
  }

  Widget _sizeRow(String name, String dimensions, AdSize? size) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name ($dimensions)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (size != null)
            Center(child: EasyBannerAd(adSize: size))
          else
            const EasyBannerAd(),
        ],
      ),
    );
  }
}
