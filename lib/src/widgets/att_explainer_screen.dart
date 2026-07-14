import 'package:flutter/material.dart';

import '../consent/explainer_content.dart';

/// The optional ATT priming screen shown before Apple's system tracking
/// prompt (iOS, client-driven ATT mode): explains, in the app's own words,
/// what the next system dialog will ask.
///
/// A pure primer — the single button just dismisses it, and Apple's system
/// prompt always follows. Use [show] as the `attExplainer` presenter of
/// `AdFlow.initialize`, or embed the widget in a custom route yourself.
/// Mirrors the shape of `RewardedIntroScreen`.
class AttExplainerScreen extends StatelessWidget {
  /// Creates the ATT primer rendering [content].
  const AttExplainerScreen({required this.content, super.key});

  /// The copy to display.
  final AttExplainerContent content;

  /// Pushes the primer as a full-screen dialog route; completes when it is
  /// dismissed. Apple's system prompt always follows.
  static Future<void> show(BuildContext context, AttExplainerContent content) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AttExplainerScreen(content: content),
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
              Text(
                content.footnote,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(content.continueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
