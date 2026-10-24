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
  testWidgets('Settings screen shows backup and app information', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Backup erstellen'), findsOneWidget);
    expect(find.text('Backup wiederherstellen'), findsOneWidget);
    expect(find.text('Garantien exportieren'), findsNothing);
    expect(find.text('Daten importieren'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Google Drive Sync'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Google Drive Sync'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Versicherungs-Report erstellen (PDF)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Versicherungs-Report erstellen (PDF)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Über BonKeepr'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Über BonKeepr'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Impressum'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Impressum'), findsOneWidget);
  });
}
