import 'dart:async';
import 'dart:math';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Randomized-interleaving fuzz over the controller state machines
/// (2026-07 audit).
///
/// This suite's bug history is precisely illegal-interleaving bugs found one
/// at a time (ADR-024 races, review findings #3/#4, the refresh/resize
/// cluster). Instead of enumerating interleavings by hand, drive a random —
/// but SEEDED, so failures replay — sequence of public operations, SDK
/// events and timer/clock advances, and assert the resource/state invariants
/// after every step:
///
/// 1. No leaked handles: at most one live (undisposed) handle exists, and it
///    is the controller's current one.
/// 2. State/handle consistency: `AdLoaded` implies a handle.
/// 3. Terminal cleanliness: after dispose(), every handle the SDK ever
///    produced is disposed.
///
/// On failure, the printed seed reproduces the exact sequence.
void main() {
  const seeds = 24;
  const opsPerRun = 120;

  group('BannerAdController fuzz', () {
    for (var seed = 0; seed < seeds; seed++) {
      test('seed $seed survives $opsPerRun random ops leak-free', () {
        final random = Random(seed);
        final sdk = FakeAdSdk()
          ..enforceConsentGate = false
          ..canRequestAdsResult = true;
        final coordinator = FullScreenAdCoordinator();
        var enabled = true;
        fakeAsync((async) {
          final c = BannerAdController(
            sdk: sdk,
            gate: AdGate(
              canRequestAds: sdk.canRequestAds,
              isEnabled: () => enabled,
            ),
            config: const BannerConfig(
              adUnitId: PlatformAdUnitId(android: 'unit-b'),
              minRefresh: Duration(seconds: 60),
            ),
            adUnitId: 'unit-b',
            retry: RetryPolicy(const RetryConfig(), random: random.nextDouble),
            coordinator: coordinator,
          );

          void checkInvariants(String afterOp) {
            final live = sdk.banners.where((b) => !b.disposed).toList();
            expect(
              live.length,
              lessThanOrEqualTo(1),
              reason: '[seed $seed after $afterOp] >1 live banner: leak',
            );
            if (live.isNotEmpty) {
              expect(
                live.single,
                same(c.handle),
                reason:
                    '[seed $seed after $afterOp] a live banner that is not '
                    'the current handle is a leak',
              );
            }
            if (c.state.value is AdLoaded) {
              expect(
                c.handle,
                isNotNull,
                reason: '[seed $seed after $afterOp] AdLoaded without handle',
              );
            }
          }

          for (var i = 0; i < opsPerRun; i++) {
            final op = random.nextInt(10);
            switch (op) {
              case 0 || 1:
                unawaited(c.load(width: 320));
              case 2:
                unawaited(c.resize(200 + random.nextInt(6) * 100));
              case 3:
                // Hold or release in-flight loads.
                if (sdk.loadHold == null) {
                  sdk.loadHold = Completer<void>();
                } else {
                  sdk.loadHold!.complete();
                  sdk.loadHold = null;
                }
              case 4:
                // Toggle load failures.
                sdk.alwaysLoadError = sdk.alwaysLoadError == null
                    ? const AdFlowError(AdFlowErrorKind.loadFailed, 'no fill')
                    : null;
              case 5:
                enabled = !enabled;
                unawaited(c.recheckGate());
              case 6:
                final live = sdk.banners.where((b) => !b.disposed).toList();
                if (live.isNotEmpty) {
                  live.single.simulateEvent(
                    ViewAdEvent.values[random.nextInt(4)],
                  );
                }
              case 7:
                async.elapse(Duration(seconds: 1 + random.nextInt(90)));
              case 8:
                async.flushMicrotasks();
              case 9:
                unawaited(c.recheckGate());
            }
            async.flushMicrotasks();
            checkInvariants('op#$i($op)');
          }

          // Release any parked load, settle everything, then tear down.
          sdk.loadHold?.complete();
          sdk.loadHold = null;
          sdk.alwaysLoadError = null;
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 10));
          async.flushMicrotasks();
          checkInvariants('settle');

          c.dispose();
          async.flushMicrotasks();
          expect(
            sdk.banners.every((b) => b.disposed),
            isTrue,
            reason: '[seed $seed] handles leaked past dispose()',
          );
        });
        coordinator.dispose();
      });
    }
  });

  group('InterstitialAdController fuzz', () {
    for (var seed = 0; seed < seeds; seed++) {
      test('seed $seed survives $opsPerRun random ops leak-free', () {
        final random = Random(seed);
        final sdk = FakeAdSdk()
          ..enforceConsentGate = false
          ..canRequestAdsResult = true;
        final coordinator = FullScreenAdCoordinator();
        var enabled = true;
        var now = DateTime(2026, 7, 17, 12);
        fakeAsync((async) {
          final c = InterstitialAdController(
            sdk: sdk,
            gate: AdGate(
              canRequestAds: sdk.canRequestAds,
              isEnabled: () => enabled,
            ),
            caps: StoredFrequencyCapPolicy(
              store: InMemoryKeyValueStore(),
              slotCaps: const {},
              globalCap: const FrequencyCap(),
              now: () => now,
            ),
            coordinator: coordinator,
            config: const InterstitialConfig(
              adUnitId: PlatformAdUnitId(android: 'unit-i'),
            ),
            adUnitId: 'unit-i',
            retry: RetryPolicy(const RetryConfig(), random: random.nextDouble),
            now: () => now,
          );

          // The fake enforces legal event ordering (dismiss only after
          // show), so track what is legal to simulate.
          FakeFullScreenAdHandle? shownAd;

          void checkInvariants(String afterOp) {
            final live = sdk.interstitials.where((h) => !h.disposed).toList();
            expect(
              live.length,
              lessThanOrEqualTo(1),
              reason: '[seed $seed after $afterOp] >1 live interstitial',
            );
            if (c.state.value is AdLoaded) {
              expect(c.isReady, isTrue, reason: '[seed $seed after $afterOp]');
            }
            expect(
              coordinator.isFullScreenAdVisible,
              c.state.value is AdShowing,
              reason:
                  '[seed $seed after $afterOp] coordinator claim must track '
                  'AdShowing exactly (single controller in this run)',
            );
          }

          for (var i = 0; i < opsPerRun; i++) {
            final op = random.nextInt(10);
            switch (op) {
              case 0 || 1:
                unawaited(c.load());
              case 2:
                unawaited(
                  c.show().then((shown) {
                    if (shown) {
                      shownAd = sdk.interstitials
                          .where((h) => !h.disposed)
                          .firstOrNull;
                    }
                  }),
                );
              case 3:
                if (sdk.loadHold == null) {
                  sdk.loadHold = Completer<void>();
                } else {
                  sdk.loadHold!.complete();
                  sdk.loadHold = null;
                }
              case 4:
                sdk.alwaysLoadError = sdk.alwaysLoadError == null
                    ? const AdFlowError(AdFlowErrorKind.loadFailed, 'no fill')
                    : null;
              case 5:
                enabled = !enabled;
                unawaited(c.recheckGate());
              case 6:
                final ad = shownAd;
                if (ad != null && !ad.disposed && c.state.value is AdShowing) {
                  ad.simulateDismissed();
                  shownAd = null;
                }
              case 7:
                final advance = Duration(seconds: 1 + random.nextInt(90));
                now = now.add(advance);
                async.elapse(advance);
              case 8:
                async.flushMicrotasks();
              case 9:
                unawaited(c.recheckGate());
            }
            async.flushMicrotasks();
            checkInvariants('op#$i($op)');
          }

          sdk.loadHold?.complete();
          sdk.loadHold = null;
          sdk.alwaysLoadError = null;
          async.flushMicrotasks();
          final ad = shownAd;
          if (ad != null && !ad.disposed && c.state.value is AdShowing) {
            ad.simulateDismissed();
          }
          now = now.add(const Duration(minutes: 10));
          async.elapse(const Duration(minutes: 10));
          async.flushMicrotasks();
          checkInvariants('settle');

          c.dispose();
          async.flushMicrotasks();
          expect(
            sdk.interstitials.every((h) => h.disposed),
            isTrue,
            reason: '[seed $seed] handles leaked past dispose()',
          );
        });
        coordinator.dispose();
      });
    }
  });
}
