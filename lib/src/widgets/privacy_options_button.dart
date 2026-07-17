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

  /// Invoked when showing the privacy options form fails — surface it to
  /// the user (e.g. a SnackBar): this is the GDPR-mandated manage-consent
  /// control, and a tap that silently does nothing is a dead end.
  ///
  /// When null, the failure is reported through [FlutterError.reportError]
  /// (visible in logs and crash reporting) rather than swallowed
  /// (2026-07 audit).
  final void Function(Object error)? onError;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: consent.privacyOptionsRequired,
      builder: (context, required, _) {
        if (!required) return const SizedBox.shrink();
        return TextButton(
          onPressed: () async {
            try {
              await consent.showPrivacyOptions();
            } catch (e, stack) {
              final handler = onError;
              if (handler != null) {
                handler(e);
              } else {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: e,
                    stack: stack,
                    library: 'ad_flow',
                    context: ErrorDescription(
                      'while showing the privacy options form',
                    ),
                  ),
                );
              }
            }
          },
          child: Text(label),
        );
      },
    );
  }
}
