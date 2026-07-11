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
  tearDown(() => sdk.dispose());

  Widget host() => MaterialApp(
    home: Scaffold(body: PrivacyOptionsButton(consent: consent)),
  );

  testWidgets('hidden when no privacy entry point is required', (
    tester,
  ) async {
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
}
