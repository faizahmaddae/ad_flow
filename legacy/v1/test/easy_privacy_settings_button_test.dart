// Copyright 2024 - AdMob Integration Package
// Widget tests for EasyPrivacySettingsButton and PrivacySettingsListTile

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EasyPrivacySettingsButton', () {
    group('constructor and properties', () {
      test('has correct default values', () {
        const button = EasyPrivacySettingsButton();

        expect(button.text, 'Privacy Settings');
        expect(button.child, isNull);
        expect(button.alwaysShow, false);
        expect(button.onPressed, isNull);
        expect(button.onFormDismissed, isNull);
        expect(button.style, isNull);
        expect(button.icon, isNull);
      });

      test('accepts custom text', () {
        const button = EasyPrivacySettingsButton(text: 'Custom Text');
        expect(button.text, 'Custom Text');
      });

      test('accepts custom child widget', () {
        const child = Text('Custom Child');
        const button = EasyPrivacySettingsButton(child: child);
        expect(button.child, child);
      });

      test('accepts alwaysShow flag', () {
        const button = EasyPrivacySettingsButton(alwaysShow: true);
        expect(button.alwaysShow, true);
      });

      test('accepts custom icon', () {
        const button = EasyPrivacySettingsButton(icon: Icons.settings);
        expect(button.icon, Icons.settings);
      });

      test('accepts callbacks', () {
        void onPressed() {}
        void onFormDismissed() {}

        final button = EasyPrivacySettingsButton(
          onPressed: onPressed,
          onFormDismissed: onFormDismissed,
        );

        expect(button.onPressed, onPressed);
        expect(button.onFormDismissed, onFormDismissed);
      });

      test('accepts custom style', () {
        final style = ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.red),
        );
        final button = EasyPrivacySettingsButton(style: style);
        expect(button.style, style);
      });
    });

    group('rendering with alwaysShow=true', () {
      testWidgets('renders button with default text and icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: EasyPrivacySettingsButton(alwaysShow: true)),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(EasyPrivacySettingsButton), findsOneWidget);
        expect(find.text('Privacy Settings'), findsOneWidget);
        expect(find.byIcon(Icons.privacy_tip_outlined), findsOneWidget);
      });

      testWidgets('renders custom text', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                text: 'Manage Privacy',
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Manage Privacy'), findsOneWidget);
      });

      testWidgets('renders custom icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                icon: Icons.settings,
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byIcon(Icons.settings), findsOneWidget);
      });

      testWidgets('renders custom child instead of default button', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                child: ListTile(
                  leading: Icon(Icons.privacy_tip),
                  title: Text('Custom Privacy'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(ListTile), findsOneWidget);
        expect(find.text('Custom Privacy'), findsOneWidget);
        // Default button should not be present when custom child is used
        expect(find.byType(TextButton), findsNothing);
      });

      testWidgets('wraps custom child in GestureDetector', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                child: Text('Tap Me'),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(GestureDetector), findsOneWidget);
        expect(find.text('Tap Me'), findsOneWidget);
      });
    });

    group('rendering without alwaysShow', () {
      testWidgets('renders SizedBox.shrink when not required', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyPrivacySettingsButton())),
        );

        // Initial loading state
        await tester.pump();

        // After async check completes
        await tester.pumpAndSettle();

        // Should render nothing when not in GDPR region
        // (ConsentManager returns false by default in tests)
        expect(find.byType(EasyPrivacySettingsButton), findsOneWidget);
        // No TextButton should be visible
        expect(find.byType(TextButton), findsNothing);
      });
    });

    group('callbacks', () {
      testWidgets('calls onPressed when button is tapped', (tester) async {
        bool onPressedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                onPressed: () {
                  onPressedCalled = true;
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        await tester.tap(find.text('Privacy Settings'));
        await tester.pump();

        expect(onPressedCalled, true);
      });

      testWidgets('calls onPressed when custom child is tapped', (
        tester,
      ) async {
        bool onPressedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EasyPrivacySettingsButton(
                alwaysShow: true,
                child: const Text('Custom'),
                onPressed: () {
                  onPressedCalled = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.text('Custom'));
        await tester.pump();

        expect(onPressedCalled, true);
      });
    });

    group('lifecycle', () {
      testWidgets('disposes cleanly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: EasyPrivacySettingsButton(alwaysShow: true)),
          ),
        );

        await tester.pump();

        // Replace the widget to trigger dispose
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('No Button'))),
        );

        expect(find.byType(EasyPrivacySettingsButton), findsNothing);
      });

      testWidgets('handles mounted check in async callback', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: EasyPrivacySettingsButton(alwaysShow: true)),
          ),
        );

        // Immediately remove widget before async completes
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Gone'))),
        );

        // Should not throw due to mounted check
        await tester.pumpAndSettle();
      });
    });
  });

  group('PrivacySettingsListTile', () {
    group('constructor and properties', () {
      test('has correct default values', () {
        const tile = PrivacySettingsListTile();

        expect(tile.title, 'Privacy Settings');
        expect(tile.subtitle, 'Manage your ad preferences');
        expect(tile.leading, isNull);
        expect(tile.alwaysShow, false);
        expect(tile.onTap, isNull);
        expect(tile.onFormDismissed, isNull);
      });

      test('accepts custom title', () {
        const tile = PrivacySettingsListTile(title: 'Custom Title');
        expect(tile.title, 'Custom Title');
      });

      test('accepts custom subtitle', () {
        const tile = PrivacySettingsListTile(subtitle: 'Custom Subtitle');
        expect(tile.subtitle, 'Custom Subtitle');
      });

      test('accepts null subtitle', () {
        const tile = PrivacySettingsListTile(subtitle: null);
        expect(tile.subtitle, isNull);
      });

      test('accepts custom leading widget', () {
        const leading = Icon(Icons.lock);
        const tile = PrivacySettingsListTile(leading: leading);
        expect(tile.leading, leading);
      });

      test('accepts alwaysShow flag', () {
        const tile = PrivacySettingsListTile(alwaysShow: true);
        expect(tile.alwaysShow, true);
      });

      test('accepts callbacks', () {
        void onTap() {}
        void onFormDismissed() {}

        final tile = PrivacySettingsListTile(
          onTap: onTap,
          onFormDismissed: onFormDismissed,
        );

        expect(tile.onTap, onTap);
        expect(tile.onFormDismissed, onFormDismissed);
      });
    });

    group('rendering with alwaysShow=true', () {
      testWidgets('renders ListTile with default values', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PrivacySettingsListTile(alwaysShow: true)),
          ),
        );

        await tester.pump();

        expect(find.byType(PrivacySettingsListTile), findsOneWidget);
        expect(find.byType(ListTile), findsOneWidget);
        expect(find.text('Privacy Settings'), findsOneWidget);
        expect(find.text('Manage your ad preferences'), findsOneWidget);
        expect(find.byIcon(Icons.privacy_tip_outlined), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets('renders custom title and subtitle', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PrivacySettingsListTile(
                alwaysShow: true,
                title: 'Custom Title',
                subtitle: 'Custom Subtitle',
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Custom Title'), findsOneWidget);
        expect(find.text('Custom Subtitle'), findsOneWidget);
      });

      testWidgets('renders without subtitle when null', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PrivacySettingsListTile(alwaysShow: true, subtitle: null),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Privacy Settings'), findsOneWidget);
        expect(find.text('Manage your ad preferences'), findsNothing);
      });

      testWidgets('renders custom leading widget', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PrivacySettingsListTile(
                alwaysShow: true,
                leading: Icon(Icons.lock),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byIcon(Icons.lock), findsOneWidget);
        // Default icon should not be present
        expect(find.byIcon(Icons.privacy_tip_outlined), findsNothing);
      });
    });

    group('rendering without alwaysShow', () {
      testWidgets('renders SizedBox.shrink when not required', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PrivacySettingsListTile())),
        );

        await tester.pumpAndSettle();

        expect(find.byType(PrivacySettingsListTile), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
      });
    });

    group('callbacks', () {
      testWidgets('calls onTap when tile is tapped', (tester) async {
        bool onTapCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PrivacySettingsListTile(
                alwaysShow: true,
                onTap: () {
                  onTapCalled = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        await tester.tap(find.byType(ListTile));
        await tester.pump();

        expect(onTapCalled, true);
      });
    });

    group('lifecycle', () {
      testWidgets('disposes cleanly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PrivacySettingsListTile(alwaysShow: true)),
          ),
        );

        await tester.pump();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('No Tile'))),
        );

        expect(find.byType(PrivacySettingsListTile), findsNothing);
      });

      testWidgets('handles mounted check in async callback', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PrivacySettingsListTile(alwaysShow: true)),
          ),
        );

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Gone'))),
        );

        await tester.pumpAndSettle();
      });
    });
  });
}
