// ============================================================================
// App Open Ads Example
// ============================================================================
// Demonstrates every app open ad pattern:
//
//   1. Automatic — ads show on cold start + foreground resume (via init flags)
//   2. Manual load → show
//   3. Pause / resume — suppress during sensitive flows
//   4. Ad availability check (loaded + not expired)
//
// AdFlow is already initialized by main.dart with:
//   preloadAppOpen: true
//   showAppOpenOnColdStart: true
//   enableAppOpenOnForeground: true
//
// Just navigate to this page — foreground ads are already working.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:ad_flow/ad_flow.dart';

import 'example_all_ads.dart';

class AppOpenExamplePage extends StatefulWidget {
  const AppOpenExamplePage({super.key});

  @override
  State<AppOpenExamplePage> createState() => _AppOpenExamplePageState();
}

class _AppOpenExamplePageState extends State<AppOpenExamplePage> {
  String _lastEvent = 'No events yet';
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    AdFlow.instance.appOpen.addStatusListener(_rebuild);
  }

  @override
  void dispose() {
    AdFlow.instance.appOpen.removeStatusListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _log(String event) {
    setState(() => _lastEvent = event);
    debugPrint('AppOpen: $event');
  }

  // --------------------------------------------------------------------------
  // Manual load
  // --------------------------------------------------------------------------
  Future<void> _manualLoad() async {
    await AdFlow.instance.appOpen.loadAd(
      onAdLoaded: (_) => _log('Ad loaded ✓'),
      onAdFailedToLoad: (error) =>
          _log('Load failed: ${error.message} (code: ${error.code})'),
    );
  }

  // --------------------------------------------------------------------------
  // Manual show
  // --------------------------------------------------------------------------
  Future<void> _manualShow() async {
    final shown = await AdFlow.instance.appOpen.showAdIfAvailable(
      onAdDismissed: () {
        _log('Ad dismissed — user returned to app');
        // Auto-reloads after being shown
      },
      onAdFailedToShow: () {
        _log('Failed to show (not loaded, expired, or showing)');
      },
    );

    if (shown) {
      _log('Ad shown ✓');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app open ad available')),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Pause / resume
  // --------------------------------------------------------------------------
  void _togglePause() {
    if (_paused) {
      AdFlow.instance.resumeAppOpenAds();
      _log('Resumed — foreground ads active');
    } else {
      AdFlow.instance.pauseAppOpenAds();
      _log('Paused — foreground ads suppressed');
    }
    setState(() => _paused = !_paused);
  }

  @override
  Widget build(BuildContext context) {
    final mgr = AdFlow.instance.appOpen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Open Ads'),
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
                  Row(
                    children: [
                      Icon(
                        mgr.isAdAvailable ? Icons.check : Icons.close,
                        size: 16,
                        color: mgr.isAdAvailable ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        mgr.isAdAvailable
                            ? 'Available (loaded + not expired)'
                            : 'Not available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last event: $_lastEvent',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Pattern 1: Automatic ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Automatic (Current Setup)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Already configured during init:\n'
                    '• showAppOpenOnColdStart: true\n'
                    '• enableAppOpenOnForeground: true\n'
                    '• maxForegroundAdsPerSession: 2\n\n'
                    'Try switching to another app and coming back — '
                    'an app open ad will appear automatically.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Pattern 2: Manual ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2. Manual Load & Show',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Load an ad manually, then show it. '
                    'showAdIfAvailable() checks both load status and the '
                    '4-hour expiry window.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: mgr.isLoading ? null : _manualLoad,
                          icon: const Icon(Icons.download),
                          label: const Text('Load'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: mgr.isAdAvailable ? _manualShow : null,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Show'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Pattern 3: Pause / resume ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3. Pause / Resume',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pause foreground app open ads during sensitive flows '
                    '(payment screens, onboarding, etc.). '
                    'Resume when done.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _paused ? Icons.pause_circle : Icons.play_circle,
                        color: _paused ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(_paused ? 'Paused' : 'Active'),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: _togglePause,
                        child: Text(_paused ? 'Resume' : 'Pause'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Info: Expiry ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '4. Ad Expiry',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'App open ads expire after 4 hours '
                    '(appOpenAdMaxCacheDuration in AdFlowConfig). '
                    'If the cached ad is expired when a show is attempted, '
                    'it will be discarded and a new one loaded automatically.',
                    style: Theme.of(context).textTheme.bodySmall,
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
