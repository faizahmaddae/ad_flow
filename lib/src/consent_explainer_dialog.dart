// Copyright 2024 - AdMob Integration Package
// Pre-consent explainer dialog for better user experience

import 'package:flutter/material.dart';

// ============================================================================
// LOCALIZATION - Customizable Texts
// ============================================================================

/// Holds all customizable texts for [ConsentExplainerDialog].
///
/// Override any or all texts to localize or customize the dialog.
///
/// Example - Spanish localization:
/// ```dart
/// const spanishTexts = ConsentExplainerTexts(
///   title: 'Tu Privacidad Importa',
///   description: 'Esta aplicación es gratuita porque muestra anuncios...',
///   continueButton: 'Continuar',
/// );
///
/// await ConsentExplainerDialog.show(context, texts: spanishTexts);
/// ```
class ConsentExplainerTexts {
  const ConsentExplainerTexts({
    this.title = 'Your Privacy Matters',
    this.description =
        'This app is free because it shows ads. '
        'To keep it free and improve your experience, '
        'we\'d like to show you relevant ads based on your interests.',
    this.benefitRelevantAds = 'Ads that match your interests',
    this.benefitDataSecure = 'Your data stays secure',
    this.benefitKeepFree = 'Helps keep the app free',
    this.settingsHint = 'You can change your preferences anytime in Settings.',
    this.continueButton = 'Continue',
    this.skipButton = 'I\'ll decide on the next screen',
  });

  /// Dialog title
  final String title;

  /// Main description paragraph
  final String description;

  /// First benefit item text
  final String benefitRelevantAds;

  /// Second benefit item text
  final String benefitDataSecure;

  /// Third benefit item text
  final String benefitKeepFree;

  /// Hint about settings (shown in info box)
  final String settingsHint;

  /// Primary action button text
  final String continueButton;

  /// Secondary skip button text
  final String skipButton;

  /// Creates a copy with some values replaced.
  ConsentExplainerTexts copyWith({
    String? title,
    String? description,
    String? benefitRelevantAds,
    String? benefitDataSecure,
    String? benefitKeepFree,
    String? settingsHint,
    String? continueButton,
    String? skipButton,
  }) {
    return ConsentExplainerTexts(
      title: title ?? this.title,
      description: description ?? this.description,
      benefitRelevantAds: benefitRelevantAds ?? this.benefitRelevantAds,
      benefitDataSecure: benefitDataSecure ?? this.benefitDataSecure,
      benefitKeepFree: benefitKeepFree ?? this.benefitKeepFree,
      settingsHint: settingsHint ?? this.settingsHint,
      continueButton: continueButton ?? this.continueButton,
      skipButton: skipButton ?? this.skipButton,
    );
  }
}

/// Holds all customizable texts for [ATTExplainerDialog].
///
/// Override any or all texts to localize the iOS ATT explainer.
///
/// Example - German localization:
/// ```dart
/// const germanTexts = ATTExplainerTexts(
///   title: 'Tracking erlauben?',
///   description: 'Auf dem nächsten Bildschirm fragt Apple...',
///   gotItButton: 'Verstanden',
/// );
///
/// await ATTExplainerDialog.show(context, texts: germanTexts);
/// ```
class ATTExplainerTexts {
  const ATTExplainerTexts({
    this.title = 'Allow Tracking?',
    this.description =
        'On the next screen, Apple will ask if you allow tracking. '
        'Tapping "Allow" helps us show you ads that are more relevant to you.',
    this.footnote = 'Your choice won\'t affect the number of ads you see.',
    this.gotItButton = 'Got it',
  });

  /// Dialog title
  final String title;

  /// Main description text
  final String description;

  /// Footnote/disclaimer text (shown in italic)
  final String footnote;

  /// Button text
  final String gotItButton;

  /// Creates a copy with some values replaced.
  ATTExplainerTexts copyWith({
    String? title,
    String? description,
    String? footnote,
    String? gotItButton,
  }) {
    return ATTExplainerTexts(
      title: title ?? this.title,
      description: description ?? this.description,
      footnote: footnote ?? this.footnote,
      gotItButton: gotItButton ?? this.gotItButton,
    );
  }
}

// ============================================================================
// DEFAULT TEXTS (for easy access)
// ============================================================================

/// Default English texts for [ConsentExplainerDialog].
const kDefaultConsentExplainerTexts = ConsentExplainerTexts();

/// Default English texts for [ATTExplainerDialog].
const kDefaultATTExplainerTexts = ATTExplainerTexts();

// ============================================================================
// CONSENT EXPLAINER DIALOG
// ============================================================================

/// A friendly pre-consent dialog that explains why we're asking for consent.
///
/// This improves UX by giving users context before the official
/// consent popups appear (GDPR form, iOS ATT prompt).
///
/// Usage:
/// ```dart
/// // With default English texts
/// final userProceed = await ConsentExplainerDialog.show(context);
///
/// // With custom/localized texts
/// final userProceed = await ConsentExplainerDialog.show(
///   context,
///   texts: ConsentExplainerTexts(
///     title: 'Votre vie privée compte',
///     description: 'Cette application est gratuite...',
///     continueButton: 'Continuer',
///   ),
/// );
/// ```
class ConsentExplainerDialog {
  ConsentExplainerDialog._();

  /// Shows the pre-consent explainer dialog.
  ///
  /// [texts] - Optional custom texts for localization. Uses English defaults if not provided.
  ///
  /// Returns `true` if user taps "Continue", `false` if dismissed.
  static Future<bool> show(
    BuildContext context, {
    ConsentExplainerTexts texts = kDefaultConsentExplainerTexts,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConsentExplainerContent(texts: texts),
    );
    return result ?? false;
  }
}

class _ConsentExplainerContent extends StatelessWidget {
  const _ConsentExplainerContent({required this.texts});

  final ConsentExplainerTexts texts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.privacy_tip_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),

            const SizedBox(height: 20),

            // Title
            Text(
              texts.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Explanation
            Text(
              texts.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // Benefits list
            _buildBenefitItem(
              context,
              Icons.ads_click,
              texts.benefitRelevantAds,
            ),
            const SizedBox(height: 8),
            _buildBenefitItem(
              context,
              Icons.lock_outline,
              texts.benefitDataSecure,
            ),
            const SizedBox(height: 8),
            _buildBenefitItem(
              context,
              Icons.favorite_outline,
              texts.benefitKeepFree,
            ),

            const SizedBox(height: 24),

            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texts.settingsHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  texts.continueButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Skip text
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                texts.skipButton,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

// ============================================================================
// ATT EXPLAINER DIALOG (iOS Only)
// ============================================================================

/// A simpler, more compact explainer for iOS ATT specifically.
class ATTExplainerDialog {
  ATTExplainerDialog._();

  /// Shows a brief explanation before the iOS ATT popup.
  ///
  /// [texts] - Optional custom texts for localization. Uses English defaults if not provided.
  static Future<bool> show(
    BuildContext context, {
    ATTExplainerTexts texts = kDefaultATTExplainerTexts,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ATTExplainerContent(texts: texts),
    );
    return result ?? false;
  }
}

class _ATTExplainerContent extends StatelessWidget {
  const _ATTExplainerContent({required this.texts});

  final ATTExplainerTexts texts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.track_changes,
          size: 30,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(texts.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            texts.description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            texts.footnote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(texts.gotItButton),
          ),
        ),
      ],
    );
  }
}
