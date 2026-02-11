// ============================================================================
// Native Ads Example
// ============================================================================
// Demonstrates every way to show native ads:
//
//   1. EasyNativeAd — Drop-in widget (handles everything)
//   2. EasyNativeAd with customization (styling, callbacks)
//   3. Manual NativeAdManager (full control)
//
// Requires NativeAdFactory setup on each platform.
// See: doc/NATIVE_ADS_SETUP.md
//
// AdFlow is already initialized by main.dart.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

import 'example_all_ads.dart';

class NativeExamplePage extends StatelessWidget {
  const NativeExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Ads'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _EasyNativeSection(),
          SizedBox(height: 16),
          _CustomizedNativeSection(),
          SizedBox(height: 16),
          _ManualNativeSection(),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============================================================================
// 1. EASY NATIVE — Zero boilerplate
// ============================================================================
class _EasyNativeSection extends StatelessWidget {
  const _EasyNativeSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. EasyNativeAd (Drop-in)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Handles init waiting, loading, Remove Ads, error handling, '
              'and disposal automatically. Just specify your factory ID.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const SizedBox(
              height: 300,
              child: EasyNativeAd(
                factoryId: 'medium_template',
                height: 300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Code:\nconst EasyNativeAd(\n'
              '  factoryId: \'medium_template\',\n'
              '  height: 300,\n'
              ')',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. CUSTOMIZED EASY NATIVE — Styling + callbacks
// ============================================================================
class _CustomizedNativeSection extends StatefulWidget {
  const _CustomizedNativeSection();

  @override
  State<_CustomizedNativeSection> createState() =>
      _CustomizedNativeSectionState();
}

class _CustomizedNativeSectionState extends State<_CustomizedNativeSection> {
  String _status = 'Loading…';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. EasyNativeAd with Customization',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Custom background, border radius, padding, and callbacks.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $_status',
              style: TextStyle(
                fontSize: 12,
                color: _status.contains('Loaded') ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            EasyNativeAd(
              factoryId: 'medium_template',
              height: 300,
              hideOnLoading: true,   // Collapse while loading
              hideOnError: true,     // Collapse on error / no fill
              backgroundColor: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(12),
              onAdLoaded: () {
                if (mounted) setState(() => _status = 'Loaded ✓');
              },
              onAdFailedToLoad: () {
                if (mounted) setState(() => _status = 'Failed to load');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. MANUAL NATIVE AD MANAGER — Full control
// ============================================================================
class _ManualNativeSection extends StatefulWidget {
  const _ManualNativeSection();

  @override
  State<_ManualNativeSection> createState() => _ManualNativeSectionState();
}

class _ManualNativeSectionState extends State<_ManualNativeSection> {
  final _manager = NativeAdManager();

  @override
  void initState() {
    super.initState();
    _manager.addStatusListener(_onStatusChanged);
  }

  @override
  void dispose() {
    _manager.removeStatusListener(_onStatusChanged);
    _manager.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAd() async {
    await _manager.loadAd(
      factoryId: 'medium_template',
      // onAdLoaded receives the NativeAd instance
      onAdLoaded: (ad) {
        debugPrint('Native ad loaded: ${ad.adUnitId}');
      },
      // onAdFailedToLoad receives the LoadAdError
      onAdFailedToLoad: (error) {
        debugPrint('Native ad failed: ${error.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Native ad failed: ${error.message}')),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3. Manual NativeAdManager',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Full control: create a NativeAdManager, load with callbacks, '
              'listen to status changes, and place the ad widget yourself.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _manager.isLoading ? null : _loadAd,
                  icon: const Icon(Icons.download),
                  label: const Text('Load Native Ad'),
                ),
                const SizedBox(width: 12),
                StatusChip(
                  loaded: _manager.isLoaded,
                  loading: _manager.isLoading,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_manager.isLoaded && _manager.nativeAd != null)
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AdWidget(ad: _manager.nativeAd!),
                ),
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Tap "Load Native Ad" to load manually',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
