import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/src/consent/tcf_consent.dart' show tcfConsentFrom;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  group('TcfConsent.refusedDeviceAccess', () {
    test('GDPR applies and purpose 1 refused → true', () {
      const tcf = TcfConsent(gdprApplies: true, purposeConsents: '0111111111');
      expect(tcf.refusedDeviceAccess, isTrue);
    });

    test('GDPR applies and nothing stored yet → true (not asked yet)', () {
      const tcf = TcfConsent(gdprApplies: true, purposeConsents: '');
      expect(tcf.refusedDeviceAccess, isTrue);
    });

    test('GDPR applies and purpose 1 granted → false', () {
      const tcf = TcfConsent(gdprApplies: true, purposeConsents: '1000000000');
      expect(tcf.refusedDeviceAccess, isFalse);
    });

    test('GDPR does not apply → false, whatever is stored', () {
      const tcf = TcfConsent(gdprApplies: false, purposeConsents: '0');
      expect(tcf.refusedDeviceAccess, isFalse);
    });
  });

  group('tcfConsentFrom', () {
    test('no keys → null', () {
      expect(tcfConsentFrom(const {}), isNull);
    });

    test('reads the int UMP writes, and the string and bool other CMPs '
        'write', () {
      for (final applies in <Object>[1, '1', true]) {
        expect(
          tcfConsentFrom({
            'IABTCF_gdprApplies': applies,
            'IABTCF_PurposeConsents': '1',
          }),
          const TcfConsent(gdprApplies: true, purposeConsents: '1'),
        );
      }
      expect(
        tcfConsentFrom(const {'IABTCF_gdprApplies': 0}),
        const TcfConsent(gdprApplies: false, purposeConsents: ''),
      );
    });

    test('a non-string purpose record reads as empty', () {
      expect(
        tcfConsentFrom(const {
          'IABTCF_gdprApplies': 1,
          'IABTCF_PurposeConsents': 101,
        }),
        const TcfConsent(gdprApplies: true, purposeConsents: ''),
      );
    });
  });

  group('readDeviceTcfConsent', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('null off iOS — the only platform with a tracking prompt', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'IABTCF_gdprApplies': 1,
            'IABTCF_PurposeConsents': '0',
          });
      expect(await readDeviceTcfConsent(), isNull);
    });

    test('on iOS, reads the raw IABTCF keys', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'IABTCF_gdprApplies': 1,
            'IABTCF_PurposeConsents': '0000000000',
            'unrelated': 'x',
          });
      expect(
        await readDeviceTcfConsent(),
        const TcfConsent(gdprApplies: true, purposeConsents: '0000000000'),
      );
    });

    test('on iOS with no record → null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      expect(await readDeviceTcfConsent(), isNull);
    });

    test('a failing preferences backend reads as null, never throws', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SharedPreferencesAsyncPlatform.instance = _ThrowingPrefs();
      expect(await readDeviceTcfConsent(), isNull);
    });
  });
}

/// A preferences backend whose every read fails, like a missing channel.
final class _ThrowingPrefs extends InMemorySharedPreferencesAsync {
  _ThrowingPrefs() : super.empty();

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => throw StateError('no channel');
}
