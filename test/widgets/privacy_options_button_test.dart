import 'package:ad_flow/src/consent/consent_gateway.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:ad_flow/src/widgets/privacy_options_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late UmpConsentGateway consent;

  setUp(() {
    sdk = FakeAdSdk();
    consent = UmpConsentGateway(sdk);
  });
  tearDown(() {
    consent.dispose();
    sdk.dispose();
  });

  Widget host() => MaterialApp(
    home: Scaffold(body: PrivacyOptionsButton(consent: consent)),
  );

  testWidgets('hidden when no privacy entry point is required', (tester) async {
    sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.notRequired;
    await consent.ensureCanRequestAds();

    await tester.pumpWidget(host());
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('visible when required; tap shows the privacy form '
      '(invariant 2)', (tester) async {
    sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
    await consent.ensureCanRequestAds();

    await tester.pumpWidget(host());
    expect(find.text('Privacy settings'), findsOneWidget);

    await tester.tap(find.text('Privacy settings'));
    await tester.pumpAndSettle();
    expect(sdk.showPrivacyOptionsFormCalls, 1);
  });

  testWidgets(
    'reacts when the requirement becomes true AFTER the widget is already '
    'mounted (invariant 2: the entry point must be available whenever '
    'required, not just at the widget\'s first build)',
    (tester) async {
      // Mounted before consent resolves — a settings screen that's part of
      // a persistent shell can easily render before AdFlow.initialize()
      // (and therefore the first ensureCanRequestAds()) completes.
      await tester.pumpWidget(host());
      expect(find.byType(TextButton), findsNothing);

      sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
      await consent.ensureCanRequestAds();
      await tester.pump(); // no remount, no manual setState — just a pump

      expect(find.text('Privacy settings'), findsOneWidget);
    },
  );

  testWidgets('reacts when the requirement flips back to not-required '
      '(e.g. a later re-check)', (tester) async {
    sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.required;
    await consent.ensureCanRequestAds();
    await tester.pumpWidget(host());
    expect(find.byType(TextButton), findsOneWidget);

    sdk.privacyOptionsRequirement = PrivacyOptionsRequirement.notRequired;
    await consent.ensureCanRequestAds();
    await tester.pump();

    expect(find.byType(TextButton), findsNothing);
  });
}
