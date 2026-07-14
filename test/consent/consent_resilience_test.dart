import 'package:ad_flow/src/consent/consent_gateway.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// A seam whose ATT calls throw a RAW platform error (not the documented
/// [AdFlowError]) — what `app_tracking_transparency` actually does when its
/// channel is missing or the host app has no NSUserTrackingUsageDescription.
class _AttThrowingSdk extends FakeAdSdk {
  @override
  Future<AttStatus> getTrackingAuthorizationStatus() async =>
      throw const FormatException('MissingPluginException: att');
}

void main() {
  test(
    'a raw platform throw from ATT never suppresses the GDPR flow (ADR-031)',
    () async {
      final sdk = _AttThrowingSdk()
        ..consentStatus = AdConsentStatus.required
        ..consentFormAvailable = true
        ..privacyOptionsRequirement = PrivacyOptionsRequirement.required
        ..onConsentFormShown = () {}
        ..canRequestAdsResult = true;
      final gateway = UmpConsentGateway(sdk, attExplainer: (_) async {});

      await gateway.ensureCanRequestAds();

      expect(
        sdk.consentUpdateCalls,
        hasLength(1),
        reason: 'the consent info update must still run when ATT blows up',
      );
      expect(
        sdk.loadAndShowConsentFormCalls,
        1,
        reason:
            'the REQUIRED GDPR form must never be suppressed by an ATT '
            'failure — ATT and GDPR are independent regimes (ADR-031)',
      );
      expect(gateway.privacyOptionsRequired.value, isTrue);
      expect(gateway.lastError, isNotNull, reason: 'the failure is surfaced');
      gateway.dispose();
      await sdk.dispose();
    },
  );

  test('a failed consent info update still surfaces the privacy-options entry '
      'point when ads keep serving (invariant 2)', () async {
    // The returning EEA user who already consented on a previous launch:
    // canRequestAds() is true from cached UMP state, so ads WILL serve — but
    // this launch is offline, so the info update fails.
    final sdk = FakeAdSdk()
      ..consentUpdateError = const AdFlowError(
        AdFlowErrorKind.consent,
        'offline',
      )
      ..canRequestAdsResult = true
      ..privacyOptionsRequirement = PrivacyOptionsRequirement.required;
    final gateway = UmpConsentGateway(sdk);

    final canRequest = await gateway.ensureCanRequestAds();

    expect(canRequest, isTrue, reason: 'cached consent keeps ads serving');
    expect(
      gateway.privacyOptionsRequired.value,
      isTrue,
      reason:
          'ads are serving to an EEA user, so the "Manage consent" entry '
          'point is REQUIRED — a failed info update must not hide it',
    );
    gateway.dispose();
    await sdk.dispose();
  });
}
