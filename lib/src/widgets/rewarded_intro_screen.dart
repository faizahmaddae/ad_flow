import 'package:flutter/material.dart';

import '../config/ad_flow_config.dart';
import '../controllers/rewarded_interstitial_ad_controller.dart';
import 'explainer_body.dart';

/// The mandatory intro screen shown before a rewarded interstitial:
/// clear reward messaging plus a skip option (AdMob policy — ADR-013).
///
/// Pass [presenter] as `rewardedIntroPresenter` to `AdFlow.initialize`, use
/// [show] from your own presenter, or embed the widget in a custom route and
/// pop `true` (continue) / `false` (skip) yourself.
class RewardedIntroScreen extends StatelessWidget {
  /// Creates the intro screen rendering [content].
  const RewardedIntroScreen({required this.content, super.key});

  /// The copy to display.
  final RewardIntroContent content;

  /// Pushes the intro as a full-screen dialog route; resolves to true when
  /// the user chose to watch the ad, false when skipped (or the route was
  /// dismissed any other way).
  static Future<bool> show(
    BuildContext context,
    RewardIntroContent content,
  ) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => RewardedIntroScreen(content: content),
      ),
    );
    return result ?? false;
  }

  /// A ready-made `rewardedIntroPresenter` for `AdFlow.initialize` that shows
  /// this screen on [navigatorKey]'s navigator (the key of your `MaterialApp`).
  ///
  /// ```dart
  /// AdFlow.initialize(
  ///   config,
  ///   rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
  /// );
  /// ```
  ///
  /// The key is read each time the intro is needed, so the package still
  /// never holds a `BuildContext`. When the navigator is not mounted the
  /// presenter resolves to `false`: the ad is not shown (reported as
  /// `introSkipped`) and nothing throws.
  static RewardedIntroPresenter presenter(
    GlobalKey<NavigatorState> navigatorKey,
  ) => (content) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    return show(context, content);
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ExplainerBody scrolls rather than clipping: the skip option below is the
    // last child, and AdMob requires it to remain reachable at every text
    // scale (see ExplainerBody's doc).
    return ExplainerBody(
      children: [
        Text(
          content.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          content.message,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(content.continueLabel),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(content.skipLabel),
        ),
      ],
    );
  }
}
