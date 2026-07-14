import 'dart:async';

import 'package:ad_flow/src/consent/consent_gateway.dart';
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
    test(
      'no presenters: today\'s behaviour exactly — no ATT, no primer '
      '(regression guard)',
      () async {
        sdk.consentStatus = AdConsentStatus.required;
        sdk.consentFormAvailable = true;
        sdk.canRequestAdsResult = true;

        await gateway.ensureCanRequestAds(); // default gateway, no explainers

        expect(sdk.requestTrackingAuthorizationCalls, 0); // no ATT at all
        expect(sdk.loadAndShowConsentFormCalls, 1); // form as before
      },
    );

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

    group('skipConsentPrimerIfAttDenied (COMPLIANCE: a required GDPR form is '
        'never suppressed by ATT; the flag only skips the primer)', () {
      late List<String> events;
      void armEeaWithAtt(AttStatus requestResult, {bool skip = true}) {
        events = <String>[];
        sdk.attStatus = AttStatus.notDetermined;
        sdk.attRequestResult = requestResult;
        sdk.consentStatus = AdConsentStatus.required; // EEA: form required
        sdk.consentFormAvailable = true;
        sdk.onConsentFormShown = () => events.add('form');
        gateway = UmpConsentGateway(
          sdk,
          attExplainer: (_) async {},
          consentExplainer: (_) async => events.add('primer'),
          skipConsentPrimerIfAttDenied: skip,
        );
      }

      test('EEA + ATT denied → the required GDPR form is STILL shown '
          '(GDPR and ATT are independent regimes)', () async {
        armEeaWithAtt(AttStatus.denied); // skip defaults true
        await gateway.ensureCanRequestAds();
        expect(sdk.loadAndShowConsentFormCalls, 1); // never suppressed
        expect(events, contains('form'));
      });

      test('EEA + ATT denied + default flag → only the optional primer is '
          'skipped, the form still shows', () async {
        armEeaWithAtt(AttStatus.denied);
        await gateway.ensureCanRequestAds();
        expect(events, isNot(contains('primer'))); // primer optimized away
        expect(events, contains('form')); // ...but the form still shows
      });

      test('EEA + ATT denied + flag off → the primer is shown too', () async {
        armEeaWithAtt(AttStatus.denied, skip: false);
        await gateway.ensureCanRequestAds();
        expect(events, ['primer', 'form']);
      });

      test('EEA + ATT authorized → primer and form both shown (flag '
          'irrelevant when ATT was not denied)', () async {
        armEeaWithAtt(AttStatus.authorized);
        await gateway.ensureCanRequestAds();
        expect(events, ['primer', 'form']);
      });

      test('the consent info update always runs (even when ATT was denied)',
          () async {
        armEeaWithAtt(AttStatus.denied);
        await gateway.ensureCanRequestAds();
        expect(sdk.consentUpdateCalls, hasLength(1));
        expect(sdk.loadAndShowConsentFormCalls, 1); // form no longer suppressed
      });
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

    test('full pipeline ordering: ATT primer (no ATT/consent calls yet) → '
        'requestTrackingAuthorization + info update → consent primer (both '
        'done) → form', () async {
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
      );

      await gateway.ensureCanRequestAds();

      expect(events, ['att-primer', 'consent-primer', 'form']);
      // At the ATT primer neither the system prompt nor the info update has
      // run yet — ATT is strictly first.
      expect(reqAtAttPrimer, 0);
      expect(updAtAttPrimer, 0);
      // By the consent primer, the ATT prompt AND the info update have both
      // completed — i.e. requestTrackingAuthorization ran before the info
      // update, which ran before the consent primer / form.
      expect(reqAtConsentPrimer, 1);
      expect(updAtConsentPrimer, 1);
    });
  });
}
