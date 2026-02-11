// Expanded tests for EasyPrivacySettingsButton and PrivacySettingsListTile

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();
    AdFlowPlatform.platformOverride = TargetPlatform.android;
    final mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;
  });

  tearDown(() async {
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('EasyPrivacySettingsButton', () {
    testWidgets('shows SizedBox.shrink when not required and not alwaysShow', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: EasyPrivacySettingsButton()),
      );
      await tester.pumpAndSettle();

      // Should show nothing when privacy options not required
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows button when alwaysShow is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyPrivacySettingsButton(alwaysShow: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Settings'), findsOneWidget);
    });

    testWidgets('custom text is displayed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EasyPrivacySettingsButton(
              alwaysShow: true,
              text: 'My Privacy',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Privacy'), findsOneWidget);
    });

    testWidgets('custom icon is displayed', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('onPressed callback is called on tap', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EasyPrivacySettingsButton(
              alwaysShow: true,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Settings'));
      expect(pressed, true);
    });

    testWidgets('custom child widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EasyPrivacySettingsButton(
              alwaysShow: true,
              child: Text('Custom Child'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Child'), findsOneWidget);
    });

    testWidgets('disposes without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: EasyPrivacySettingsButton(alwaysShow: true)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // Should not throw
    });
  });

  group('PrivacySettingsListTile', () {
    testWidgets('shows SizedBox.shrink when not required', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PrivacySettingsListTile())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows ListTile when alwaysShow is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PrivacySettingsListTile(alwaysShow: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Settings'), findsOneWidget);
      expect(find.text('Manage your ad preferences'), findsOneWidget);
    });

    testWidgets('custom title and subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrivacySettingsListTile(
              alwaysShow: true,
              title: 'Custom Title',
              subtitle: 'Custom Sub',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Title'), findsOneWidget);
      expect(find.text('Custom Sub'), findsOneWidget);
    });

    testWidgets('onTap callback is called on tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivacySettingsListTile(
              alwaysShow: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Settings'));
      expect(tapped, true);
    });

    testWidgets('custom leading widget', (tester) async {
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
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('disposes without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PrivacySettingsListTile(alwaysShow: true)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    });
  });
}
