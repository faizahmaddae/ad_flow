import 'package:flutter/material.dart';

import '../consent/explainer_content.dart';

/// The optional consent priming screen shown before the UMP GDPR form:
/// explains, in the app's own words, why consent is about to be requested.
///
/// A pure primer — both buttons simply dismiss it, and the real consent form
/// always follows. Use [show] as the `consentExplainer` presenter of
/// `AdFlow.initialize`, or embed the widget in a custom route yourself.
/// Mirrors the shape of `RewardedIntroScreen`.
class ConsentExplainerScreen extends StatelessWidget {
  /// Creates the consent primer rendering [content].
  const ConsentExplainerScreen({required this.content, super.key});

  /// The copy to display.
  final ConsentExplainerContent content;

  /// Pushes the primer as a full-screen dialog route; completes when it is
  /// dismissed (by either button, or any other route dismissal). The real
  /// UMP form always follows regardless of which button was tapped.
  static Future<void> show(
    BuildContext context,
    ConsentExplainerContent content,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ConsentExplainerScreen(content: content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                content.title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                content.description,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              for (final bullet in content.bullets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(bullet, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                content.settingsHint,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(content.continueLabel),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(content.skipLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
