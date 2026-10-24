import 'package:flutter/material.dart';

import '../consent/explainer_content.dart';
import 'explainer_body.dart';

/// The optional ATT priming screen shown before Apple's system tracking
/// prompt (iOS, client-driven ATT mode): explains, in the app's own words,
/// what the next system dialog will ask.
///
/// A pure primer — the single button just dismisses it, and Apple's system
/// prompt always follows. Pass [presenter] as `attExplainer` to
/// `AdFlow.initialize`, use [show] from your own presenter, or embed the
/// widget in a custom route yourself. Mirrors the shape of
/// `RewardedIntroScreen`.
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

  /// A ready-made `attExplainer` for `AdFlow.initialize` that shows this
  /// primer on [navigatorKey]'s navigator (the key of your `MaterialApp`).
  ///
  /// ```dart
  /// AdFlow.initialize(
  ///   config,
  ///   attExplainer: AttExplainerScreen.presenter(navigatorKey),
  /// );
  /// ```
  ///
  /// Passing an `attExplainer` opts into client-driven ATT (see
  /// `AdFlow.initialize`). The key is read when the primer is due, so the
  /// package never holds a `BuildContext`; when the navigator is not mounted
  /// the primer is skipped and Apple's prompt still follows.
  static AttExplainerPresenter presenter(
    GlobalKey<NavigatorState> navigatorKey,
  ) => (content) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await show(context, content);
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ExplainerBody scrolls rather than clipping: the Continue button below is
    // the only way out of this primer, and Apple's system prompt only fires
    // after it (see ExplainerBody's doc).
    return ExplainerBody(
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
    );
  }
}
