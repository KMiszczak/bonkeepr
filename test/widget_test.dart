// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garantieheld/settings_screen.dart';

void main() {
  testWidgets('Settings screen shows backup and app information', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Garantien exportieren'), findsOneWidget);
    expect(find.text('Daten importieren'), findsOneWidget);
    expect(find.text('Google Drive Sync'), findsOneWidget);
    expect(find.text('Über BonKeepr'), findsOneWidget);
  });
}
