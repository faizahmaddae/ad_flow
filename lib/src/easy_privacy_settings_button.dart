// Copyright 2024 - AdMob Integration Package
// Easy Privacy Settings Button Widget

import 'package:flutter/material.dart';
import 'consent_manager.dart';

/// A convenience widget that shows a privacy settings button when required.
///
/// This widget:
/// - Automatically shows/hides based on privacy options requirement
/// - Opens the GDPR privacy options form when tapped
/// - Fully customizable appearance
///
/// GDPR requires apps to provide a way for users to change their consent.
/// Use this widget in your app's settings screen.
///
/// Example:
/// ```dart
/// // Basic usage - auto shows/hides based on GDPR requirement
/// EasyPrivacySettingsButton()
///
/// // With custom text
/// EasyPrivacySettingsButton(
///   text: 'Manage Privacy',
/// )
///
/// // Fully custom child widget
/// EasyPrivacySettingsButton(
///   child: ListTile(
///     leading: Icon(Icons.privacy_tip),
///     title: Text('Privacy Settings'),
///     trailing: Icon(Icons.chevron_right),
///   ),
/// )
///
/// // Always visible (ignores GDPR requirement check)
/// EasyPrivacySettingsButton(
///   alwaysShow: true,
/// )
/// ```
class EasyPrivacySettingsButton extends StatefulWidget {
  /// Creates an EasyPrivacySettingsButton.
  ///
  /// [text] is the button text (default: 'Privacy Settings').
  /// [child] is a custom widget to display instead of the default button.
  /// [alwaysShow] if true, always shows the button regardless of GDPR status.
  /// [onPressed] optional callback when the button is pressed.
  /// [onFormDismissed] optional callback when the privacy form is dismissed.
  /// [style] optional button style for the default button.
  /// [icon] optional icon for the default button.
  const EasyPrivacySettingsButton({
    super.key,
    this.text = 'Privacy Settings',
    this.child,
    this.alwaysShow = false,
    this.onPressed,
    this.onFormDismissed,
    this.style,
    this.icon,
  });

  /// The text to display on the button.
  final String text;

  /// A custom widget to display instead of the default button.
  /// When provided, [text], [style], and [icon] are ignored.
  final Widget? child;

  /// If true, always shows the button regardless of GDPR requirement.
  /// Default is false (only shows when privacy options are required).
  final bool alwaysShow;

  /// Optional callback when the button is pressed.
  /// Called before showing the privacy form.
  final VoidCallback? onPressed;

  /// Optional callback when the privacy form is dismissed.
  final VoidCallback? onFormDismissed;

  /// Optional style for the default button.
  final ButtonStyle? style;

  /// Optional icon for the default button.
  final IconData? icon;

  @override
  State<EasyPrivacySettingsButton> createState() =>
      _EasyPrivacySettingsButtonState();
}

class _EasyPrivacySettingsButtonState extends State<EasyPrivacySettingsButton> {
  bool _isRequired = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPrivacyRequirement();
  }

  Future<void> _checkPrivacyRequirement() async {
    // First check cached value for instant display
    final cachedValue = ConsentManager.instance.isPrivacyOptionsRequired();
    if (mounted) {
      setState(() {
        _isRequired = cachedValue;
        _isLoading = false;
      });
    }

    // Then verify with async check for accuracy
    final asyncValue = await ConsentManager.instance
        .isPrivacyOptionsRequiredAsync();
    if (mounted && asyncValue != _isRequired) {
      setState(() {
        _isRequired = asyncValue;
      });
    }
  }

  void _showPrivacyForm() {
    widget.onPressed?.call();

    ConsentManager.instance.showPrivacyOptionsForm(
      onComplete: (error) {
        if (error != null) {
          debugPrint('Privacy form error: ${error.message}');
        }
        widget.onFormDismissed?.call();
        // Re-check requirement after form dismissal
        _checkPrivacyRequirement();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Don't show while loading (unless alwaysShow is true)
    if (_isLoading && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    // Don't show if not required (unless alwaysShow is true)
    if (!_isRequired && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    // Custom child widget
    if (widget.child != null) {
      return GestureDetector(onTap: _showPrivacyForm, child: widget.child);
    }

    // Default button
    return TextButton.icon(
      onPressed: _showPrivacyForm,
      style: widget.style,
      icon: Icon(widget.icon ?? Icons.privacy_tip_outlined),
      label: Text(widget.text),
    );
  }
}

/// A ListTile version of the privacy settings button for settings screens.
///
/// Example:
/// ```dart
/// ListView(
///   children: [
///     // Other settings...
///     PrivacySettingsListTile(),
///   ],
/// )
/// ```
class PrivacySettingsListTile extends StatefulWidget {
  /// Creates a PrivacySettingsListTile.
  const PrivacySettingsListTile({
    super.key,
    this.title = 'Privacy Settings',
    this.subtitle = 'Manage your ad preferences',
    this.leading,
    this.alwaysShow = false,
    this.onTap,
    this.onFormDismissed,
  });

  /// The title of the list tile.
  final String title;

  /// The subtitle of the list tile.
  final String? subtitle;

  /// Optional leading widget (defaults to privacy icon).
  final Widget? leading;

  /// If true, always shows the tile regardless of GDPR requirement.
  final bool alwaysShow;

  /// Optional callback when the tile is tapped.
  final VoidCallback? onTap;

  /// Optional callback when the privacy form is dismissed.
  final VoidCallback? onFormDismissed;

  @override
  State<PrivacySettingsListTile> createState() =>
      _PrivacySettingsListTileState();
}

class _PrivacySettingsListTileState extends State<PrivacySettingsListTile> {
  bool _isRequired = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPrivacyRequirement();
  }

  Future<void> _checkPrivacyRequirement() async {
    final cachedValue = ConsentManager.instance.isPrivacyOptionsRequired();
    if (mounted) {
      setState(() {
        _isRequired = cachedValue;
        _isLoading = false;
      });
    }

    final asyncValue = await ConsentManager.instance
        .isPrivacyOptionsRequiredAsync();
    if (mounted && asyncValue != _isRequired) {
      setState(() {
        _isRequired = asyncValue;
      });
    }
  }

  void _showPrivacyForm() {
    widget.onTap?.call();

    ConsentManager.instance.showPrivacyOptionsForm(
      onComplete: (error) {
        if (error != null) {
          debugPrint('Privacy form error: ${error.message}');
        }
        widget.onFormDismissed?.call();
        _checkPrivacyRequirement();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    if (!_isRequired && !widget.alwaysShow) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: widget.leading ?? const Icon(Icons.privacy_tip_outlined),
      title: Text(widget.title),
      subtitle: widget.subtitle != null ? Text(widget.subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: _showPrivacyForm,
    );
  }
}
