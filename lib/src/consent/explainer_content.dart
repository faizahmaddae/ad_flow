/// Copy and presenter typedefs for the optional pre-consent / pre-ATT
/// priming ("explainer") screens.
///
/// These screens are pure primers: they explain, in the app's own words and
/// language, what the next system dialog will ask — the real UMP consent
/// form / Apple ATT prompt always follows. Everything here is opt-in and
/// additive; an app that passes no presenter behaves exactly as before
/// (UMP-driven, no ATT calls).
library;

/// Copy for the consent priming screen shown *before* the UMP GDPR form.
///
/// Immutable and `const`-constructible with sensible English defaults —
/// override the fields (or [copyWith]) to localize. Only shown when a
/// consent form will actually appear (non-EEA users never see it).
class ConsentExplainerContent {
  /// Creates consent primer copy; defaults are generic English strings.
  const ConsentExplainerContent({
    this.title = 'Your privacy matters',
    this.description =
        'This app is free because it shows ads. To keep it free and '
        "show you more relevant ads, we'd like your consent on the next "
        'screen.',
    this.bullets = const [
      'Ads that match your interests',
      'Your data stays secure',
      'Helps keep the app free',
    ],
    this.settingsHint = 'You can change this anytime in Settings.',
    this.continueLabel = 'Continue',
    this.skipLabel = "I'll decide on the next screen",
  });

  /// Headline.
  final String title;

  /// Body text explaining why consent is being requested.
  final String description;

  /// Short reassurance points rendered as a checklist.
  final List<String> bullets;

  /// Footnote reminding the user the choice is revisitable.
  final String settingsHint;

  /// Label of the primary button that proceeds to the consent form.
  final String continueLabel;

  /// Label of the secondary button (also just dismisses the primer — the
  /// real form still follows).
  final String skipLabel;

  /// Returns a copy with the given fields replaced. Handy for localizing a
  /// subset of the copy while keeping the rest of the defaults.
  ConsentExplainerContent copyWith({
    String? title,
    String? description,
    List<String>? bullets,
    String? settingsHint,
    String? continueLabel,
    String? skipLabel,
  }) => ConsentExplainerContent(
    title: title ?? this.title,
    description: description ?? this.description,
    bullets: bullets ?? this.bullets,
    settingsHint: settingsHint ?? this.settingsHint,
    continueLabel: continueLabel ?? this.continueLabel,
    skipLabel: skipLabel ?? this.skipLabel,
  );
}

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

/// Presents the consent priming screen; completes when the primer is
/// dismissed (the real UMP form always follows, so there is nothing to
/// return). Mirrors `RewardedIntroPresenter`.
///
/// The app decides context-validity inside the callback (e.g.
/// `if (navigatorKey.currentContext == null) return;`), so the package never
/// holds a `BuildContext`.
typedef ConsentExplainerPresenter =
    Future<void> Function(ConsentExplainerContent content);

/// Presents the ATT priming screen; completes when the primer is dismissed
/// (Apple's system prompt always follows). Mirrors `RewardedIntroPresenter`.
typedef AttExplainerPresenter =
    Future<void> Function(AttExplainerContent content);
