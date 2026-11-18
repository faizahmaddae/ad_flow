/// Copy and presenter typedef for the optional pre-ATT priming ("explainer")
/// screen.
///
/// The screen is a pure primer: it explains, in the app's own words and
/// language, what Apple's tracking prompt will ask — the real prompt always
/// follows. Opt-in; an app that passes no presenter makes no ATT call at all
/// (UMP-driven ATT). There is no primer before the GDPR form (6.0,
/// ADR-086).
library;

/// Copy for the ATT priming screen shown *before* Apple's system tracking
/// prompt (iOS, client-driven ATT mode).
///
/// Immutable and `const`-constructible with sensible English defaults —
/// override the fields (or [copyWith]) to localize.
class AttExplainerContent {
  /// Creates ATT primer copy; defaults are generic English strings.
  const AttExplainerContent({
    this.title = 'Allow tracking?',
    this.description =
        'On the next screen Apple will ask if you allow tracking. '
        'Allowing it helps us show ads that are more relevant to you.',
    this.footnote = "Your choice won't affect the number of ads you see.",
    this.continueLabel = 'Got it',
  });

  /// Headline.
  final String title;

  /// Body text explaining what the Apple prompt will ask.
  final String description;

  /// Footnote clarifying that ad quantity is unaffected by the choice.
  final String footnote;

  /// Label of the button that proceeds to the system prompt.
  final String continueLabel;

  /// Returns a copy with the given fields replaced.
  AttExplainerContent copyWith({
    String? title,
    String? description,
    String? footnote,
    String? continueLabel,
  }) => AttExplainerContent(
    title: title ?? this.title,
    description: description ?? this.description,
    footnote: footnote ?? this.footnote,
    continueLabel: continueLabel ?? this.continueLabel,
  );
}

/// Presents the ATT priming screen; completes when the primer is dismissed
/// (Apple's system prompt always follows). Mirrors `RewardedIntroPresenter`.
typedef AttExplainerPresenter =
    Future<void> Function(AttExplainerContent content);
