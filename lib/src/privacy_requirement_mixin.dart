// Copyright 2024 - AdMob Integration Package
// Shared mixin for privacy settings widgets

import 'package:flutter/material.dart';
import 'consent_manager.dart';
import 'ad_flow_logger.dart';

/// Mixin that provides privacy options requirement checking logic
/// shared between [EasyPrivacySettingsButton] and [PrivacySettingsListTile].
///
/// Handles both cached (instant) and async (accurate) checks, updating
/// widget state appropriately. Also provides a helper to show the privacy
/// form and re-check afterward.
mixin PrivacyRequirementMixin<T extends StatefulWidget> on State<T> {
  bool privacyIsRequired = false;
  bool privacyIsLoading = true;

  /// Check whether privacy options are required.
  ///
  /// First uses the cached synchronous value for instant display,
  /// then verifies with an async call for accuracy.
  Future<void> checkPrivacyRequirement() async {
    // First check cached value for instant display
    final cachedValue = ConsentManager.instance.isPrivacyOptionsRequired();
    if (mounted) {
      setState(() {
        privacyIsRequired = cachedValue;
        privacyIsLoading = false;
      });
    }

    // Then verify with async check for accuracy
    final asyncValue = await ConsentManager.instance
        .isPrivacyOptionsRequiredAsync();
    if (mounted && asyncValue != privacyIsRequired) {
      setState(() {
        privacyIsRequired = asyncValue;
      });
    }
  }

  /// Shows the privacy options form and re-checks the requirement afterward.
  ///
  /// [onTapCallback] is called before showing the form (e.g. widget.onPressed).
  /// [onDismissedCallback] is called after the form is dismissed.
  void showPrivacyForm({
    VoidCallback? onTapCallback,
    VoidCallback? onDismissedCallback,
  }) {
    onTapCallback?.call();

    ConsentManager.instance.showPrivacyOptionsForm(
      onComplete: (error) {
        if (error != null) {
          adFlowLog('Privacy form error: ${error.message}');
        }
        onDismissedCallback?.call();
        // Re-check requirement after form dismissal
        checkPrivacyRequirement();
      },
    );
  }
}
