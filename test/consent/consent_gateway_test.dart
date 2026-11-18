import 'dart:async';

import 'package:ad_flow/src/consent/consent_gateway.dart';
import 'package:ad_flow/src/consent/tcf_consent.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late UmpConsentGateway gateway;

  setUp(() {
    sdk = FakeAdSdk();
    gateway = UmpConsentGateway(sdk);
  });
  tearDown(() {
    gateway.dispose();
    sdk.dispose();
  });

  group('ensureCanRequestAds', () {
    test('non-EEA: update runs, form no-ops, gate opens', () async {
      sdk.consentStatus = AdConsentStatus.notRequired;
      sdk.canRequestAdsResult = true;

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(sdk.consentUpdateCalls, hasLength(1));
      // Mirrors Google's sample: called unconditionally, no-ops internally.
      expect(sdk.loadAndShowConsentFormCalls, 1);
      expect(gateway.lastError, isNull);
    });

    test('EEA: form dismissal opens the gate', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false;
      sdk.onConsentFormShown = () {
        sdk.canRequestAdsResult = true;
        sdk.consentStatus = AdConsentStatus.obtained;
      };

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(sdk.loadAndShowConsentFormCalls, 1);
      expect(gateway.lastError, isNull);
    });

    test('EEA: user keeps consent unresolved, gate stays closed', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.canRequestAdsResult = false;

      expect(await gateway.ensureCanRequestAds(), isFalse);
    });

    test(
      'update error degrades to canRequestAds (previously obtained)',
      () async {
        const error = AdFlowError(AdFlowErrorKind.consent, 'network down');
        sdk.consentUpdateError = error;
        sdk.canRequestAdsResult = true; // consent obtained on a prior launch

        final canRequest = await gateway.ensureCanRequestAds();

        expect(canRequest, isTrue);
        expect(gateway.lastError, same(error));
        // Form step must be skipped after a failed update.
        expect(sdk.loadAndShowConsentFormCalls, 0);
      },
    );

    test('update error with no prior consent yields false', () async {
      sdk.consentUpdateError = const AdFlowError(
        AdFlowErrorKind.consent,
        'network down',
      );
      sdk.canRequestAdsResult = false;

      expect(await gateway.ensureCanRequestAds(), isFalse);
      expect(gateway.lastError, isNotNull);
    });

    test(
      'form error degrades to canRequestAds and surfaces lastError',
      () async {
        const error = AdFlowError(AdFlowErrorKind.consent, 'form failed');
        sdk.consentFormError = error;
        sdk.canRequestAdsResult = false;

        expect(await gateway.ensureCanRequestAds(), isFalse);
        expect(gateway.lastError, same(error));
      },
    );

    test('lastError clears on a subsequent successful run', () async {
      sdk.consentUpdateError = const AdFlowError(
        AdFlowErrorKind.consent,
        'flaky',
      );
      await gateway.ensureCanRequestAds();
      expect(gateway.lastError, isNotNull);

      sdk.consentUpdateError = null;
      sdk.canRequestAdsResult = true;
      await gateway.ensureCanRequestAds();
      expect(gateway.lastError, isNull);
    });

    test('hanging info update times out and degrades', () async {
      gateway = UmpConsentGateway(
        sdk,
        infoUpdateTimeout: const Duration(milliseconds: 50),
      );
      sdk.consentUpdateHold = Completer<void>();
      sdk.canRequestAdsResult = true;

      final canRequest = await gateway.ensureCanRequestAds();

      expect(canRequest, isTrue);
      expect(gateway.lastError?.kind, AdFlowErrorKind.timeout);
      expect(sdk.loadAndShowConsentFormCalls, 0);
    });

    test(
      'concurrent calls join the in-flight run (double-load guard)',
      () async {
        sdk.consentUpdateHold = Completer<void>();
        sdk.canRequestAdsResult = true;

        final first = gateway.ensureCanRequestAds();
        final second = gateway.ensureCanRequestAds();
        sdk.consentUpdateHold!.complete();

        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(sdk.consentUpdateCalls, hasLength(1));
        expect(sdk.loadAndShowConsentFormCalls, 1);
      },
    );

    test('a later call after completion runs the flow again', () async {
      sdk.canRequestAdsResult = true;
      await gateway.ensureCanRequestAds();
      await gateway.ensureCanRequestAds();
      expect(sdk.consentUpdateCalls, hasLength(2));
    });

    test('forwards tagForUnderAgeOfConsent and debug options', () async {
      gateway = UmpConsentGateway(sdk, tagForUnderAgeOfConsent: true);
      const debug = ConsentDebugOptions(
        geography: ConsentDebugGeography.eea,
        testIdentifiers: ['HASH'],
      );

      await gateway.ensureCanRequestAds(debug: debug);

      expect(sdk.consentUpdateCalls.single.tagForUnderAgeOfConsent, isTrue);
      expect(sdk.consentUpdateCalls.single.debug, same(debug));
    });
  });

  group('privacy options', () {
    test('isPrivacyOptionsRequired reflects the post-flow status', () async {
      sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
      expect(gateway.isPrivacyOptionsRequired, isFalse); // before the flow

      await gateway.ensureCanRequestAds();
      expect(gateway.isPrivacyOptionsRequired, isTrue);
    });

    test('showPrivacyOptions delegates to the seam', () async {
      await gateway.showPrivacyOptions();
      expect(sdk.showPrivacyOptionsFormCalls, 1);
    });

    test('showPrivacyOptions rethrows form errors', () async {
      const error = AdFlowError(AdFlowErrorKind.consent, 'no form');
      sdk.privacyOptionsFormError = error;
      await expectLater(gateway.showPrivacyOptions(), throwsA(same(error)));
    });
  });

  test('reset delegates to the seam', () async {
    await gateway.reset();
    expect(sdk.resetConsentCalls, 1);
  });

  group('explainer / ATT flow (slice 3)', () {
    test('no presenters: today\'s behaviour exactly — no ATT, no primer '
        '(regression guard)', () async {
      sdk.consentStatus = AdConsentStatus.required;
      sdk.consentFormAvailable = true;
      sdk.canRequestAdsResult = true;

      await gateway.ensureCanRequestAds(); // default gateway, no explainers

      expect(sdk.requestTrackingAuthorizationCalls, 0); // no ATT at all
      expect(sdk.loadAndShowConsentFormCalls, 1); // form as before
    });

    group('ATT', () {
      test('the explainer runs before requestTrackingAuthorization', () async {
        var callsAtPrimer = -1;
        sdk.attStatus = AttStatus.notDetermined;
        sdk.attRequestResult = AttStatus.authorized;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async {
            callsAtPrimer = sdk.requestTrackingAuthorizationCalls;
          },
        );

        await gateway.ensureCanRequestAds();

        expect(callsAtPrimer, 0); // prompt had not fired when the primer ran
        expect(sdk.requestTrackingAuthorizationCalls, 1); // it fired after
      });

      test('the step is skipped when status is already authorized', () async {
        final events = <String>[];
        sdk.attStatus = AttStatus.authorized;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty);
        expect(sdk.requestTrackingAuthorizationCalls, 0);
      });

      test('the step is skipped when status is already denied', () async {
        final events = <String>[];
        sdk.attStatus = AttStatus.denied;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty);
        expect(sdk.requestTrackingAuthorizationCalls, 0);
      });

      test('non-iOS (notSupported) skips the ATT step even with an explainer '
          '(Android)', () async {
        final events = <String>[];
        sdk.attStatus = AttStatus.notSupported;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty);
        expect(sdk.requestTrackingAuthorizationCalls, 0);
      });

      test('attPromptDelay is respected (fakeAsync)', () {
        fakeAsync((async) {
          sdk.attStatus = AttStatus.notDetermined;
          sdk.attRequestResult = AttStatus.authorized;
          sdk.canRequestAdsResult = true;
          gateway = UmpConsentGateway(
            sdk,
            attExplainer: (_) async {},
            attPromptDelay: const Duration(milliseconds: 200),
          );

          var done = false;
          gateway.ensureCanRequestAds().then((_) => done = true);

          async.flushMicrotasks(); // run the primer future to completion
          // The delay has NOT elapsed yet, so the prompt must not have fired.
          expect(sdk.requestTrackingAuthorizationCalls, 0);

          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();
          expect(sdk.requestTrackingAuthorizationCalls, 1);
          expect(done, isTrue);
        });
      });

      test('a throwing ATT explainer still proceeds to the system prompt '
          'and records lastError', () async {
        sdk.attStatus = AttStatus.notDetermined;
        sdk.attRequestResult = AttStatus.authorized;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => throw StateError('boom'),
        );

        await gateway.ensureCanRequestAds();

        expect(sdk.requestTrackingAuthorizationCalls, 1); // prompt still fired
        expect(gateway.lastError, isNotNull);
        expect(gateway.lastError!.kind, AdFlowErrorKind.consent);
      });
    });

    group('order (ADR-082, App Store 5.1.1(iv)): the GDPR flow first, the '
        'tracking question last', () {
      late List<String> events;

      /// An EEA user (form required) who has not answered ATT yet.
      void armEea({
        AttStatus requestResult = AttStatus.authorized,
        TcfConsentReader? readTcf,
      }) {
        events = <String>[];
        sdk.attStatus = AttStatus.notDetermined;
        sdk.attRequestResult = requestResult;
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = true;
        sdk.canRequestAdsResult = true;
        sdk.onConsentFormShown = () => events.add('form');
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => events.add('att-primer'),
          consentExplainer: (_) async => events.add('consent-primer'),
          readTcfConsent: readTcf ?? () async => null,
        );
      }

      test('consent primer → GDPR form → ATT primer → ATT prompt', () async {
        int? updatesAtAttPrimer, formsAtAttPrimer, promptsAtAttPrimer;
        events = <String>[];
        sdk.attStatus = AttStatus.notDetermined;
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = true;
        sdk.onConsentFormShown = () => events.add('form');
        gateway = UmpConsentGateway(
          sdk,
          consentExplainer: (_) async => events.add('consent-primer'),
          attExplainer: (_) async {
            events.add('att-primer');
            updatesAtAttPrimer = sdk.consentUpdateCalls.length;
            formsAtAttPrimer = sdk.loadAndShowConsentFormCalls;
            promptsAtAttPrimer = sdk.requestTrackingAuthorizationCalls;
          },
          readTcfConsent: () async => null,
        );

        await gateway.ensureCanRequestAds();

        expect(events, ['consent-primer', 'form', 'att-primer']);
        // By the ATT primer the whole GDPR flow had run, the prompt had not.
        expect(updatesAtAttPrimer, 1);
        expect(formsAtAttPrimer, 1);
        expect(promptsAtAttPrimer, 0);
        expect(sdk.requestTrackingAuthorizationCalls, 1);
      });

      test('the required GDPR form is shown whatever the user later answers '
          'to ATT', () async {
        armEea(requestResult: AttStatus.denied);
        await gateway.ensureCanRequestAds();
        expect(events, ['consent-primer', 'form', 'att-primer']);
        expect(sdk.loadAndShowConsentFormCalls, 1);
      });

      test('the ATT step waits for the consent answer before it starts: '
          'the whole run resolves only after the prompt', () async {
        armEea();
        final canRequest = await gateway.ensureCanRequestAds();
        expect(sdk.requestTrackingAuthorizationCalls, 1);
        expect(canRequest, isTrue);
      });

      test('a failed consent info update defers ATT to a later run', () async {
        armEea();
        sdk.consentUpdateError = const AdFlowError(
          AdFlowErrorKind.consent,
          'offline',
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty); // no primer, no form, no ATT
        expect(sdk.requestTrackingAuthorizationCalls, 0);
        expect(gateway.lastError?.message, 'offline');

        // The network is back: the retry run asks in the compliant order.
        sdk.consentUpdateError = null;
        await gateway.ensureCanRequestAds();
        expect(events, ['consent-primer', 'form', 'att-primer']);
        expect(sdk.requestTrackingAuthorizationCalls, 1);
      });

      test('a consent form error also defers ATT', () async {
        armEea();
        sdk.consentFormError = const AdFlowError(
          AdFlowErrorKind.consent,
          'form failed',
        );

        await gateway.ensureCanRequestAds();

        expect(events, ['consent-primer']);
        expect(sdk.requestTrackingAuthorizationCalls, 0);
        expect(gateway.lastError?.message, 'form failed');
      });

      test('a timed-out consent info update also defers ATT', () {
        fakeAsync((async) {
          events = <String>[];
          sdk.attStatus = AttStatus.notDetermined;
          sdk.consentUpdateHold = Completer<void>();
          gateway = UmpConsentGateway(
            sdk,
            attExplainer: (_) async => events.add('att-primer'),
            readTcfConsent: () async => null,
            infoUpdateTimeout: const Duration(seconds: 30),
          );

          var done = false;
          gateway.ensureCanRequestAds().then((_) => done = true);
          async.elapse(const Duration(seconds: 31));
          async.flushMicrotasks();

          expect(done, isTrue);
          expect(events, isEmpty);
          expect(sdk.requestTrackingAuthorizationCalls, 0);
          expect(gateway.lastError?.kind, AdFlowErrorKind.timeout);
        });
      });
    });

    group('ATT after a GDPR answer (TCF purpose 1)', () {
      Future<void> runWith(TcfConsentReader readTcf) async {
        sdk.attStatus = AttStatus.notDetermined;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async {},
          readTcfConsent: readTcf,
        );
        await gateway.ensureCanRequestAds();
      }

      test('GDPR applies and purpose 1 was refused → no ATT primer, no '
          'prompt', () async {
        var primers = 0;
        sdk.attStatus = AttStatus.notDetermined;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async => primers++,
          readTcfConsent: () async => const TcfConsent(
            gdprApplies: true,
            purposeConsents: '0000000000',
          ),
        );

        final canRequest = await gateway.ensureCanRequestAds();

        expect(primers, 0);
        expect(sdk.requestTrackingAuthorizationCalls, 0);
        expect(canRequest, isTrue); // ads still flow (limited ads)
        expect(gateway.lastError, isNull); // a choice, not a failure
      });

      test('GDPR applies with no answer stored → not asked', () async {
        await runWith(
          () async => const TcfConsent(gdprApplies: true, purposeConsents: ''),
        );
        expect(sdk.requestTrackingAuthorizationCalls, 0);
      });

      test('GDPR applies and purpose 1 was granted → asked', () async {
        await runWith(
          () async => const TcfConsent(
            gdprApplies: true,
            purposeConsents: '1111111111',
          ),
        );
        expect(sdk.requestTrackingAuthorizationCalls, 1);
      });

      test('GDPR does not apply → asked', () async {
        await runWith(
          () async => const TcfConsent(gdprApplies: false, purposeConsents: ''),
        );
        expect(sdk.requestTrackingAuthorizationCalls, 1);
      });

      test('no TCF record (outside the EEA) → asked', () async {
        await runWith(() async => null);
        expect(sdk.requestTrackingAuthorizationCalls, 1);
      });

      test('a throwing TCF reader → asked, nothing recorded', () async {
        await runWith(() async => throw StateError('no prefs'));
        expect(sdk.requestTrackingAuthorizationCalls, 1);
        expect(gateway.lastError, isNull);
      });

      test(
        'the record is read only when ATT is actually undetermined',
        () async {
          var reads = 0;
          sdk.attStatus = AttStatus.authorized;
          sdk.canRequestAdsResult = true;
          gateway = UmpConsentGateway(
            sdk,
            attExplainer: (_) async {},
            readTcfConsent: () async {
              reads++;
              return null;
            },
          );

          await gateway.ensureCanRequestAds();

          expect(reads, 0);
        },
      );
    });

    group('consent primer', () {
      test('runs before loadAndShowConsentFormIfRequired', () async {
        final events = <String>[];
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = true;
        sdk.onConsentFormShown = () => events.add('form');
        gateway = UmpConsentGateway(
          sdk,
          consentExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, ['primer', 'form']);
      });

      test('is skipped for non-EEA (no form will appear)', () async {
        final events = <String>[];
        sdk.consentStatus = AdConsentStatus.notRequired;
        sdk.canRequestAdsResult = true;
        gateway = UmpConsentGateway(
          sdk,
          consentExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty); // primer skipped
        expect(sdk.loadAndShowConsentFormCalls, 1); // form call still made
      });

      test('is skipped when required but no form is available', () async {
        final events = <String>[];
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = false;
        gateway = UmpConsentGateway(
          sdk,
          consentExplainer: (_) async => events.add('primer'),
        );

        await gateway.ensureCanRequestAds();

        expect(events, isEmpty);
      });

      test('a throwing consent primer still proceeds to the form and '
          'records lastError', () async {
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = true;
        gateway = UmpConsentGateway(
          sdk,
          consentExplainer: (_) async => throw StateError('boom'),
        );

        await gateway.ensureCanRequestAds();

        expect(sdk.loadAndShowConsentFormCalls, 1); // form still shown
        expect(gateway.lastError, isNotNull);
      });
    });

    test('full pipeline ordering: info update → consent primer → form → ATT '
        'primer → ATT prompt (ADR-082)', () async {
      final events = <String>[];
      int? reqAtAttPrimer, updAtAttPrimer;
      int? reqAtConsentPrimer, updAtConsentPrimer;
      sdk.attStatus = AttStatus.notDetermined;
      sdk.attRequestResult = AttStatus.authorized;
      sdk.consentStatus = AdConsentStatus.required;
      sdk.consentFormAvailable = true;
      sdk.onConsentFormShown = () => events.add('form');
      gateway = UmpConsentGateway(
        sdk,
        attExplainer: (_) async {
          events.add('att-primer');
          reqAtAttPrimer = sdk.requestTrackingAuthorizationCalls;
          updAtAttPrimer = sdk.consentUpdateCalls.length;
        },
        consentExplainer: (_) async {
          events.add('consent-primer');
          reqAtConsentPrimer = sdk.requestTrackingAuthorizationCalls;
          updAtConsentPrimer = sdk.consentUpdateCalls.length;
        },
        readTcfConsent: () async => null,
      );

      await gateway.ensureCanRequestAds();

      expect(events, ['consent-primer', 'form', 'att-primer']);
      // At the consent primer the info update has run; no tracking prompt yet.
      expect(updAtConsentPrimer, 1);
      expect(reqAtConsentPrimer, 0);
      // At the ATT primer the GDPR flow is over and the prompt is still to
      // come — ATT is strictly last.
      expect(updAtAttPrimer, 1);
      expect(reqAtAttPrimer, 0);
      expect(sdk.requestTrackingAuthorizationCalls, 1);
    });
  });
}
