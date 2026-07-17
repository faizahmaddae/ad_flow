import 'dart:async';

import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;

  const fullConfig = AdFlowConfig(
    banner: BannerConfig(adUnitId: PlatformAdUnitId(android: 'b-a')),
    interstitial: InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i-a'),
      cap: FrequencyCap(),
    ),
    rewarded: RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r-a')),
    rewardedInterstitial: RewardedInterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'ri-a'),
    ),
    nativeAd: NativeConfig(
      adUnitId: PlatformAdUnitId(android: 'n-a'),
      templateKind: NativeTemplateKind.small,
    ),
    appOpen: AppOpenConfig(
      adUnitId: PlatformAdUnitId(android: 'ao-a'),
      cap: FrequencyCap(),
    ),
    testDeviceIds: ['dev-1'],
  );

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
  });
  tearDown(() => sdk.dispose());

  Future<AdFlow> boot({
    AdFlowConfig config = fullConfig,
    bool consentOpens = true,
  }) async {
    if (consentOpens) {
      // EEA-style: the gate opens when the form is dismissed.
      sdk.consentStatus = AdConsentStatus.required;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };
    }
    final ads = await AdFlow.initialize(
      config,
      sdk: sdk,
      store: InMemoryKeyValueStore(),
      platform: AdPlatform.android,
      rewardedIntroPresenter: (_) async => true,
    );
    // initialize() now returns BEFORE consent (non-blocking, ADR-032). Most
    // tests below assert the *started* state (preloads applied, request config
    // pushed), so wait for the background startup to finish before returning.
    await ads.whenReady;
    return ads;
  }

  group('initialize', () {
    test('NON-BLOCKING: initialize returns before consent resolves; '
        'whenReady completes after the gate opens; nothing loads before it '
        '(ADR-032)', () async {
      // Hold the consent info update. Against a blocking initialize the
      // returned Future would never complete; against non-blocking init it
      // returns at once (the 1s timeout would fire on a regression).
      final consentGate = Completer<void>();
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false;
      sdk.consentUpdateHold = consentGate;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };

      final ads = await AdFlow.initialize(
        fullConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        rewardedIntroPresenter: (_) async => true,
      ).timeout(const Duration(seconds: 1));
      expect(identical(AdFlow.instance, ads), isTrue); // _instance set at once

      var ready = false;
      unawaited(ads.whenReady.then((_) => ready = true));
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse); // whenReady pending while consent is held
      expect(sdk.loadLog, isEmpty); // invariant 1: no load before the gate

      consentGate.complete(); // consent resolves → form dismissed → gate opens
      expect(await ads.whenReady, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sdk.interstitials, hasLength(1)); // preloads ran after the gate
      ads.dispose();
    });

    test(
      'CONFIG-BEFORE-LOAD: an on-demand banner load does NOT fire before '
      'updateRequestConfiguration is applied, even with the consent gate '
      'already open (review-fix #5 under non-blocking init, ADR-033)',
      () async {
        // Hold SDK init so request configuration (applied after init, ADR-028)
        // is delayed. Consent is non-EEA → the gate opens immediately, so ONLY
        // a config-readiness gate can stop the load.
        sdk.initializeHold = Completer<void>();
        sdk.consentStatus = AdConsentStatus.notRequired;
        sdk.canRequestAdsResult = true;

        final ads = await AdFlow.initialize(
          fullConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
          rewardedIntroPresenter: (_) async => true,
        );
        // The app mounts a banner on frame 1 (as the example now does).
        final banner = ads.banner();
        final loadFuture = banner.load(width: 320);

        await Future<void>.delayed(Duration.zero); // drain microtasks
        // init is held → config not applied → the banner MUST NOT have loaded,
        // or its first request would go out untagged (testDeviceIds/COPPA).
        expect(sdk.requestConfigs, isEmpty);
        expect(sdk.bannerSpecs, isEmpty);

        sdk.initializeHold!.complete(); // init done → config applied
        await ads.whenReady;
        await loadFuture;
        expect(sdk.requestConfigs, hasLength(1)); // config applied first
        expect(
          sdk.bannerSpecs.single.adUnitId,
          'b-a',
        ); // then the banner loaded
        banner.dispose();
        ads.dispose();
      },
    );

    test('CONFIG-GATE ROBUSTNESS: a hanging updateRequestConfiguration does '
        'not wedge loads forever — the config gate degrades open after the '
        'timeout, so loads proceed rather than await _configApplied forever '
        '(ADR-033)', () {
      fakeAsync((async) {
        sdk.updateRequestConfigurationHold = Completer<void>(); // config hangs
        sdk.consentStatus = AdConsentStatus.notRequired;
        sdk.canRequestAdsResult = true;

        AdFlow? ads;
        unawaited(
          AdFlow.initialize(
            fullConfig,
            sdk: sdk,
            store: InMemoryKeyValueStore(),
            platform: AdPlatform.android,
            rewardedIntroPresenter: (_) async => true,
          ).then((f) => ads = f),
        );
        async.flushMicrotasks();
        final banner = ads!.banner(); // mounted on the first frame
        unawaited(banner.load(width: 320));

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(sdk.bannerSpecs, isEmpty); // config hung → load correctly waits

        async.elapse(const Duration(seconds: 31)); // past the config timeout
        async.flushMicrotasks();
        // The config gate degraded open → the banner load proceeded (better
        // than hanging forever on weak internet). The completer never leaks.
        expect(sdk.bannerSpecs, isNotEmpty);
        banner.dispose();
        ads!.dispose();
      });
    });

    test(
      'a throwing updateRequestConfiguration still releases the config '
      'gate — loads proceed (degraded), the completer never leaks (ADR-033)',
      () async {
        sdk.updateRequestConfigurationError = const AdFlowError(
          AdFlowErrorKind.unknown,
          'config boom',
        );
        sdk.consentStatus = AdConsentStatus.notRequired;
        sdk.canRequestAdsResult = true;

        final ads = await AdFlow.initialize(
          fullConfig,
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
          rewardedIntroPresenter: (_) async => true,
        );
        final banner = ads.banner();
        await banner.load(width: 320); // must complete, not hang
        expect(
          sdk.bannerSpecs.single.adUnitId,
          'b-a',
        ); // load proceeded degraded
        banner.dispose();
        ads.dispose();
      },
    );

    test('whenReady completes false and nothing loads when the gate stays '
        'closed', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false; // the user never resolves the form

      final ads = await AdFlow.initialize(
        fullConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        rewardedIntroPresenter: (_) async => true,
      );

      expect(await ads.whenReady, isFalse);
      expect(sdk.loadLog, isEmpty); // gate closed → no loads (invariant 1)
      ads.dispose();
    });

    testWidgets('the app tree builds and renders while consent is still '
        'pending — no FutureBuilder<AdFlow> gate needed', (tester) async {
      sdk.consentUpdateHold = Completer<void>(); // consent held all through
      sdk.canRequestAdsResult = false;

      final ads = await AdFlow.initialize(
        const AdFlowConfig(), // no slots: nothing to load
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );

      // Render a tree using the instance immediately, without awaiting consent.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: ads.adsEnabled,
              builder: (_, enabled, _) => Text('home enabled=$enabled'),
            ),
          ),
        ),
      );
      // The home screen is on screen even though consent has not resolved.
      expect(find.text('home enabled=true'), findsOneWidget);

      sdk.consentUpdateHold!.complete();
      await tester.pumpAndSettle();
      ads.dispose();
    });

    test('dispose() during background startup is safe — the _start _disposed '
        'guard stops the app-open manager from (re)subscribing to foreground '
        'events and stops preloads (ADR-032)', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = true;
      sdk.consentUpdateHold = Completer<void>(); // park _start on consent

      final ads = await AdFlow.initialize(
        fullConfig, // appOpen configured
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        rewardedIntroPresenter: (_) async => true,
      );
      // Dispose while _start is still awaiting consent (init/config done).
      ads.dispose();
      expect(sdk.hasForegroundListener, isFalse); // manager not started yet

      // Release consent. The _disposed guard must skip _appOpen.start() and the
      // preloads — without it, start() re-subscribes appForegroundEvents on the
      // disposed manager (a leak this assertion catches).
      sdk.consentUpdateHold!.complete();
      expect(await ads.whenReady, isTrue); // resolves without throwing
      expect(sdk.hasForegroundListener, isFalse); // no (re)subscription
      expect(sdk.loadLog, isEmpty); // no preloads on the torn-down graph
    });

    test('whenReady captures a background _start failure: resolves false, '
        'never throws, no unhandled async error (ADR-032 error net)', () async {
      // A throwing canRequestAds() models the production gateway's final
      // (outside-try/catch) canRequestAds() failing → _start rejects.
      sdk.canRequestAdsError = const AdFlowError(
        AdFlowErrorKind.consent,
        'boom',
      );

      final ads = await AdFlow.initialize(
        fullConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        rewardedIntroPresenter: (_) async => true,
      );

      // _begin's .catchError converts the rejection to false — whenReady must
      // NOT throw (flutter_test also fails on any unhandled async error).
      expect(await ads.whenReady, isFalse);
      ads.dispose();
    });

    test('end to end: init ∥ consent → request config → preloads → show → '
        'revenue callback', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero); // let preloads land

      // Init and consent both ran; config pushed after the gate opened.
      expect(sdk.initializeCalls, 1);
      expect(sdk.consentUpdateCalls, hasLength(1));
      expect(sdk.requestConfigs.single.testDeviceIds, ['dev-1']);

      // Every configured full-screen format preloaded exactly once.
      expect(sdk.interstitials, hasLength(1));
      expect(sdk.rewardeds, hasLength(1));
      expect(sdk.rewardedInterstitials, hasLength(1));
      expect(sdk.appOpens, hasLength(1)); // via the app-open manager

      // Show an interstitial and collect revenue.
      final paid = <AdPaidEvent>[];
      ads.onPaidEvent = paid.add;
      expect(await ads.interstitial.show(), isTrue);
      const event = AdPaidEvent(
        adUnitId: 'i-a',
        valueMicros: 5000,
        currencyCode: 'USD',
        precision: AdRevenuePrecision.precise,
      );
      sdk.interstitials.single.simulatePaid(event);
      expect(paid, [event.taggedWithSlot('interstitial')]);

      ads.dispose();
    });

    test('closed consent gate: nothing loads, nothing crashes', () async {
      final ads = await boot(consentOpens: false);
      await Future<void>.delayed(Duration.zero);

      expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
      ads.dispose();
    });

    test('request configuration is applied even when consent is closed at '
        'init (review finding #5) — it sends no ad request, so gating it '
        'on consent only means test-device/child-directed/content-rating '
        'settings never reach the SDK if consent resolves later', () async {
      final ads = await boot(consentOpens: false);
      await Future<void>.delayed(Duration.zero);

      expect(sdk.requestConfigs, hasLength(1));
      expect(sdk.requestConfigs.single.testDeviceIds, ['dev-1']);
      ads.dispose();
    });

    test(
      'a native SDK that never calls initialize() back does not wedge '
      'whenReady forever — the 30s init timeout (ADR-027) still bounds the '
      'background startup. Under ADR-032 initialize() no longer awaits '
      '_start, so the timeout now protects whenReady rather than initialize.',
      () {
        fakeAsync((async) {
          sdk.initializeHold = Completer<void>(); // native init never returns
          sdk.consentStatus = AdConsentStatus.notRequired;
          sdk.canRequestAdsResult = true;

          AdFlow? ads;
          bool? ready;
          unawaited(
            AdFlow.initialize(
              fullConfig,
              sdk: sdk,
              store: InMemoryKeyValueStore(),
              platform: AdPlatform.android,
              rewardedIntroPresenter: (_) async => true,
            ).then((flow) {
              ads = flow;
              unawaited(flow.whenReady.then((r) => ready = r));
            }),
          );

          async.flushMicrotasks();
          // initialize() returned at once — it never waits on init.
          expect(ads, isNotNull);
          // ...but the background startup (whenReady) is still pending.
          expect(ready, isNull);

          async.elapse(const Duration(seconds: 31));
          // The 30s init timeout unblocked the background _start.
          expect(ready, isNotNull);
          ads!.dispose();
        });
      },
    );

    test(
      'updateRequestConfiguration is NOT called until the background init '
      'completes (ADR-028 ordering preserved inside _start): the plugin '
      'services MobileAds#updateRequestConfiguration SYNCHRONOUSLY on the '
      'platform thread while MobileAds#initialize runs on a background '
      'thread; running them concurrently deadlocks a cold device, so config '
      'must wait for init. Under ADR-032 initialize() returns immediately, '
      'so the ordering guarantee now lives entirely in the background task.',
      () {
        fakeAsync((async) {
          sdk.initializeHold = Completer<void>();
          sdk.consentStatus = AdConsentStatus.notRequired;
          sdk.canRequestAdsResult = true;

          AdFlow? ads;
          unawaited(
            AdFlow.initialize(
              fullConfig,
              sdk: sdk,
              store: InMemoryKeyValueStore(),
              platform: AdPlatform.android,
              rewardedIntroPresenter: (_) async => true,
            ).then((flow) => ads = flow),
          );

          // Drain every microtask/timer allowed to run while init is held.
          async.elapse(const Duration(seconds: 5));

          // initialize() returned immediately (non-blocking) even though init
          // is still held.
          expect(ads, isNotNull);
          // Request configuration must NOT have been pushed while init is
          // unfinished (the platform-thread-deadlock ordering bug ADR-028
          // fixes — still enforced, just inside the background _start now).
          expect(
            sdk.requestConfigs,
            isEmpty,
            reason:
                'updateRequestConfiguration ran before init completed — the '
                'platform-thread-deadlock ordering bug ADR-028 fixes.',
          );

          // Once init completes, config is applied (still unconditionally,
          // preserving review finding #5) and the background startup finishes.
          sdk.initializeHold!.complete();
          async.elapse(const Duration(seconds: 1));

          expect(sdk.requestConfigs, hasLength(1));
          expect(sdk.requestConfigs.single.testDeviceIds, ['dev-1']);
          ads!.dispose();
        });
      },
    );

    test(
      'unconfigured slots build no controllers and throw on access',
      () async {
        final ads = await boot(
          config: const AdFlowConfig(
            interstitial: InterstitialConfig(
              adUnitId: PlatformAdUnitId(android: 'i-a'),
              cap: FrequencyCap(),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(sdk.loadLog, ['interstitial:i-a']);
        expect(
          () => ads.rewarded,
          throwsA(
            isA<AdFlowError>().having(
              (e) => e.kind,
              'kind',
              AdFlowErrorKind.invalidConfig,
            ),
          ),
        );
        expect(() => ads.appOpen, throwsA(isA<AdFlowError>()));
        ads.dispose();
      },
    );

    test('rewardedInterstitial without a presenter fails fast', () async {
      sdk.canRequestAdsResult = true;
      await expectLater(
        AdFlow.initialize(
          const AdFlowConfig(
            rewardedInterstitial: RewardedInterstitialConfig(
              adUnitId: PlatformAdUnitId(android: 'ri-a'),
            ),
          ),
          sdk: sdk,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
        ),
        throwsA(isA<AdFlowError>()),
      );
    });

    test(
      'instance points at the latest initialize and clears on dispose',
      () async {
        final ads = await boot();
        expect(AdFlow.instance, same(ads));
        ads.dispose();
        expect(() => AdFlow.instance, throwsStateError);
      },
    );

    test('dispose is idempotent — calling it twice does not throw', () async {
      final ads = await boot();
      ads.dispose();
      expect(ads.dispose, returnsNormally);
    });

    test('dispose() releases a self-created ConsentGateway but leaves an '
        'injected one usable', () async {
      // Self-created (no `consent:` injected): AdFlow owns it, so dispose()
      // must release its internal ValueNotifier. `addListener` on a disposed
      // ChangeNotifier throws — that is the direct, unambiguous proof that the
      // notifier really was released.
      //
      // (This used to assert that a post-dispose ensureCanRequestAds() THREW a
      // FlutterError from the write-after-dispose. That "proof" was really a
      // latent bug: the consent flow is async and backgrounded, so a genuine
      // dispose()-during-startup would have thrown that same error into the
      // background zone. The gateway now guards its notifier writes with a
      // _disposed check, so post-dispose use is inert instead of explosive —
      // and the ownership assertion below no longer depends on a crash.)
      final owned = await boot();
      final ownedConsent = owned.consent;
      owned.dispose();
      expect(
        () => ownedConsent.privacyOptionsRequired.addListener(() {}),
        throwsFlutterError,
        reason: 'AdFlow owns a self-created gateway and must dispose it',
      );
      sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
      await expectLater(
        ownedConsent.ensureCanRequestAds(),
        completes,
        reason:
            'a disposed gateway degrades quietly; it must not throw a '
            'use-after-dispose error into the background startup zone',
      );

      // Injected: the caller supplied it and may keep using it after this
      // particular AdFlow is gone (e.g. sharing one gateway across a
      // re-initialize) — AdFlow must not dispose it out from under them.
      final injectedSdk = FakeAdSdk()..canRequestAdsResult = true;
      final injectedConsent = UmpConsentGateway(injectedSdk);
      addTearDown(() {
        injectedConsent.dispose();
        injectedSdk.dispose();
      });
      final injected = await AdFlow.initialize(
        const AdFlowConfig(),
        sdk: injectedSdk,
        consent: injectedConsent,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      injected.dispose();
      await expectLater(
        injectedConsent.ensureCanRequestAds(),
        completion(isTrue),
      );
    });
  });

  group('explainer / ATT priming (slice 4)', () {
    test('end to end: ATT primer + prompt, then consent primer + form, then '
        'the gate opens and preloads run', () async {
      final events = <String>[];
      sdk.attStatus = AttStatus.notDetermined;
      sdk.attRequestResult = AttStatus.authorized;
      sdk.consentStatus = AdConsentStatus.required;
      sdk.consentFormAvailable = true;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
        events.add('form');
      };

      final ads = await AdFlow.initialize(
        fullConfig,
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
        rewardedIntroPresenter: (_) async => true,
        attExplainer: (_) async => events.add('att-primer'),
        consentExplainer: (_) async => events.add('consent-primer'),
      );
      // initialize() returns before the (background) explainer/consent flow;
      // wait for it, then a microtask for the preloads to land.
      await ads.whenReady;
      await Future<void>.delayed(Duration.zero);

      expect(events, ['att-primer', 'consent-primer', 'form']);
      expect(sdk.requestTrackingAuthorizationCalls, 1);
      expect(sdk.loadAndShowConsentFormCalls, 1);
      // The gate opened → the interstitial preloaded (enforceConsentGate
      // would have thrown on a load with the gate closed).
      expect(sdk.interstitials, hasLength(1));
      ads.dispose();
    });

    test('no explainers: no ATT call at all, consent flow unchanged '
        '(regression guard for the default path)', () async {
      final ads = await boot(); // boot() passes no explainers
      await Future<void>.delayed(Duration.zero);

      expect(sdk.requestTrackingAuthorizationCalls, 0);
      expect(sdk.loadAndShowConsentFormCalls, 1);
      ads.dispose();
    });

    test(
      'an injected consent gateway ignores the facade explainer params',
      () async {
        // The explainer params only configure a gateway AdFlow creates
        // itself; an injected gateway is used verbatim.
        final injectedSdk = FakeAdSdk()
          ..attStatus = AttStatus.notDetermined
          ..attRequestResult = AttStatus.authorized
          ..canRequestAdsResult = true;
        final injectedConsent = UmpConsentGateway(injectedSdk); // no explainer
        addTearDown(() {
          injectedConsent.dispose();
          injectedSdk.dispose();
        });

        final ads = await AdFlow.initialize(
          const AdFlowConfig(),
          sdk: injectedSdk,
          consent: injectedConsent,
          store: InMemoryKeyValueStore(),
          platform: AdPlatform.android,
          attExplainer: (_) async {}, // ignored — gateway was injected
        );
        await ads.whenReady; // let the background startup finish

        expect(injectedSdk.requestTrackingAuthorizationCalls, 0);
        ads.dispose();
      },
    );
  });

  group('remove-ads (enable/disableAds)', () {
    test('disableAds blocks loads and shows; enableAds restores', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero);
      final loadsAfterBoot = sdk.loadLog.length;

      ads.disableAds();
      expect(ads.adsEnabled.value, isFalse);
      expect(await ads.interstitial.show(), isFalse);

      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.loadLog.length, loadsAfterBoot); // nothing new loaded
      banner.dispose();

      ads.enableAds();
      expect(await ads.interstitial.show(), isTrue);
      ads.dispose();
    });
  });

  group('banner()/native() factories', () {
    test('mint independent controllers with resolved ids', () async {
      final ads = await boot();
      await Future<void>.delayed(Duration.zero);

      final b1 = ads.banner();
      final b2 = ads.banner();
      expect(b1, isNot(same(b2)));
      await b1.load(width: 320);
      expect(sdk.bannerSpecs.last.adUnitId, 'b-a');
      b1.dispose();
      b2.dispose();

      final n = ads.native();
      await n.load();
      expect(sdk.nativeSpecs.last.adUnitId, 'n-a');
      n.dispose();
      ads.dispose();
    });

    test('testMode swaps factory-built controllers to sample IDs', () async {
      sdk.canRequestAdsResult = true;
      final ads = await AdFlow.initialize(
        AdFlowConfig(
          banner: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'prod-b'),
          ),
          testMode: true,
        ),
        sdk: sdk,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      final banner = ads.banner();
      await banner.load(width: 320);
      expect(sdk.bannerSpecs.single.adUnitId, TestAdUnitIds.banner.android);
      banner.dispose();
      ads.dispose();
    });

    test('missing slot config throws invalidConfig', () async {
      final ads = await boot(
        config: const AdFlowConfig(
          interstitial: InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'i-a'),
            cap: FrequencyCap(),
          ),
        ),
      );
      expect(() => ads.banner(), throwsA(isA<AdFlowError>()));
      expect(() => ads.native(), throwsA(isA<AdFlowError>()));
      ads.dispose();
    });
  });

  test(
    'the global frequency cap spans INVOLUNTARY formats through the facade '
    'graph, but never blocks a user-initiated rewarded ad (ADR-039)',
    () async {
      final ads = await AdFlow.initialize(
        const AdFlowConfig(
          interstitial: InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'i-a'),
            cap: FrequencyCap(),
          ),
          rewarded: RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r-a')),
          appOpen: AppOpenConfig(
            adUnitId: PlatformAdUnitId(android: 'ao-a'),
            cap: FrequencyCap(),
          ),
          globalFrequencyCap: FrequencyCap(minGap: Duration(minutes: 10)),
        ),
        sdk: sdk..canRequestAdsResult = true,
        store: InMemoryKeyValueStore(),
        platform: AdPlatform.android,
      );
      await ads.whenReady; // background startup (preloads) finishes
      await Future<void>.delayed(Duration.zero);

      expect(await ads.interstitial.show(), isTrue);
      // Dismiss it so the coordinator is clear — only the cap remains. The
      // impression is recorded on this dismiss (ADR-040).
      sdk.interstitials.single.simulateShowed();
      sdk.interstitials.single.simulateDismissed();
      await Future<void>.delayed(Duration.zero);

      // An APP-OPEN ad is involuntary: the global 10-minute gap blocks it.
      expect(ads.appOpenController.isReady, isTrue);
      expect(await ads.appOpenController.show(), isFalse);

      // A REWARDED ad is one the user asked for, in exchange for a reward: the
      // global gap must never silently swallow it (ADR-039).
      expect(ads.rewarded.isReady, isTrue);
      expect(await ads.rewarded.show(onReward: (_) {}), isTrue);
      ads.dispose();
    },
  );

  test('openAdInspector delegates to the seam', () async {
    final ads = await boot();
    final result = await ads.openAdInspector();
    expect(result.isSuccess, isTrue);
    expect(sdk.adInspectorCalls, 1);
    ads.dispose();
  });
}
