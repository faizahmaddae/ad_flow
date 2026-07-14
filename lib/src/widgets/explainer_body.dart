import 'package:flutter/material.dart';

/// Shared layout for ad_flow's package-supplied full-screen screens (the
/// rewarded-interstitial intro and the two consent/ATT primers).
///
/// Centres [children] when they fit, and SCROLLS them when they do not.
///
/// This is not cosmetic. All three screens put their dismiss control last: the
/// rewarded intro's mandatory **skip** option, and the primers' only way out.
/// A plain centred `Column` overflows on a small device at a large
/// accessibility text scale (measured: 128 logical px of overflow for the
/// intro, 704 for the ATT primer and 1536 for the consent primer at 320x568 /
/// 200% scale with the package's own default copy), which pushes exactly those
/// controls off-screen where they are also not hit-testable. For the rewarded
/// intro that turns an AdMob-mandated opt-out into an unreachable one; for the
/// primers it is an un-escapable dead end in front of the GDPR form.
///
/// Localized copy is routinely longer than English, so this is reachable well
/// below 200% scale for many of the maintainer's users.
class ExplainerBody extends StatelessWidget {
  /// Creates a scroll-safe, centred body.
  const ExplainerBody({required this.children, super.key});

  /// The screen's content, laid out in a stretched [Column].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                // Fill the viewport so `center` still centres when the content
                // is short, while letting the column grow (and scroll) when the
                // text is large. Subtract the padding we just added, or the
                // minimum height would itself force a 48px scroll.
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
