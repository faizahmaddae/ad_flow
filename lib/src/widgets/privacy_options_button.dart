import 'package:flutter/material.dart';

import '../consent/consent_gateway.dart';

/// The persistent "Manage consent" entry point AdMob policy requires when
/// `getPrivacyOptionsRequirementStatus()` is `required` (invariant 2).
///
/// Renders nothing when no entry point is required, so it can be dropped
/// unconditionally into a settings screen.
class PrivacyOptionsButton extends StatelessWidget {
  /// Creates the button over [consent].
  const PrivacyOptionsButton({
    required this.consent,
    this.label = 'Privacy settings',
    this.onError,
    super.key,
  });

  /// The consent gateway that reports the requirement and shows the form.
  final ConsentGateway consent;

  /// Button label. Localize for real apps.
  final String label;

  /// Invoked when showing the privacy options form fails.
  final void Function(Object error)? onError;

  @override
  Widget build(BuildContext context) {
    if (!consent.isPrivacyOptionsRequired) return const SizedBox.shrink();
    return TextButton(
      onPressed: () async {
        try {
          await consent.showPrivacyOptions();
        } catch (e) {
          onError?.call(e);
        }
      },
      child: Text(label),
    );
  }
}
