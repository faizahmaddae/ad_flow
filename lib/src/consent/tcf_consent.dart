import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the IAB TCF v2 record that UMP leaves on the device says, as far as
/// the App Tracking Transparency decision needs it (ADR-082).
///
/// UMP writes the record (`IABTCF_*` keys) when the user answers the GDPR
/// message. ad_flow reads it only to decide whether to ask Apple's tracking
/// question afterwards: a user who just refused GDPR purpose 1 is not asked.
@immutable
class TcfConsent {
  /// Creates a record.
  const TcfConsent({required this.gdprApplies, required this.purposeConsents});

  /// Whether GDPR applies to this user (`IABTCF_gdprApplies` is 1).
  final bool gdprApplies;

  /// `IABTCF_PurposeConsents`: one `0`/`1` per TCF purpose, purpose 1 first.
  final String purposeConsents;

  /// Whether the user, under GDPR, refused TCF purpose 1 ("store and/or access
  /// information on a device"). Every personalised ad needs purpose 1, so
  /// asking Apple's tracking question after this refusal would be asking for
  /// tracking twice. An empty record under GDPR (no answer stored) also counts:
  /// without an answer, tracking must not be asked for yet.
  bool get refusedDeviceAccess =>
      gdprApplies && !purposeConsents.startsWith('1');

  @override
  bool operator ==(Object other) =>
      other is TcfConsent &&
      other.gdprApplies == gdprApplies &&
      other.purposeConsents == purposeConsents;

  @override
  int get hashCode => Object.hash(gdprApplies, purposeConsents);

  @override
  String toString() =>
      'TcfConsent(gdprApplies: $gdprApplies, purposeConsents: '
      '$purposeConsents)';
}

/// Reads the device's TCF record, or null when there is none or it cannot be
/// read. Never throws.
typedef TcfConsentReader = Future<TcfConsent?> Function();

const _gdprAppliesKey = 'IABTCF_gdprApplies';
const _purposeConsentsKey = 'IABTCF_PurposeConsents';

/// The default [TcfConsentReader]: the `IABTCF_*` keys UMP writes to the
/// app's standard `NSUserDefaults`.
///
/// iOS only — the only platform with a tracking prompt; returns null
/// elsewhere. `SharedPreferencesAsync` reads `UserDefaults` by the raw key on
/// iOS (no `flutter.` prefix; verified in `shared_preferences_foundation`
/// 2.6.2), so no native code is needed. Any failure reads as "no record"
/// (null): the caller then asks the tracking question as it would for a user
/// outside the EEA, which is the documented default flow.
Future<TcfConsent?> readDeviceTcfConsent() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return null;
  try {
    final values = await SharedPreferencesAsync().getAll(
      allowList: const {_gdprAppliesKey, _purposeConsentsKey},
    );
    return tcfConsentFrom(values);
  } catch (_) {
    return null;
  }
}

/// Builds a [TcfConsent] from raw stored values, or null when neither key is
/// present. Tolerates the value types different writers use for
/// `IABTCF_gdprApplies` (int, string or bool).
@visibleForTesting
TcfConsent? tcfConsentFrom(Map<String, Object?> values) {
  final applies = values[_gdprAppliesKey];
  final purposes = values[_purposeConsentsKey];
  if (applies == null && purposes == null) return null;
  return TcfConsent(
    gdprApplies: applies == 1 || applies == '1' || applies == true,
    purposeConsents: purposes is String ? purposes : '',
  );
}
