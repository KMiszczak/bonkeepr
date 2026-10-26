import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'warranty_model.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initialization;

  static Future<void> _initialize() => _initialization ??= _initializePlugin();

  static Future<void> _initializePlugin() async {
    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone.identifier));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
  }

  static Future<bool> scheduleWarrantyReminder(Warranty warranty) async {
    try {
      await _initialize();
      final id = _notificationId(warranty.id);
      await _plugin.cancel(id);
      if (warranty.reminderDaysBefore < 0) return true;

      final reminderDate = warranty.expirationDate.subtract(
        Duration(days: warranty.reminderDaysBefore),
      );
      final scheduledAt = DateTime(
        reminderDate.year,
        reminderDate.month,
        reminderDate.day,
        9,
      );
      if (!scheduledAt.isAfter(DateTime.now())) return true;
      final permissionGranted = await _requestPermission();
      if (!permissionGranted) return false;

      await _plugin.zonedSchedule(
        id,
        'Garantie läuft bald ab',
        'Die Garantie für ${warranty.title} endet am ${_formatDate(warranty.expirationDate)}.',
        timezone.TZDateTime.from(scheduledAt, timezone.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'warranty_reminders',
            'Garantie-Erinnerungen',
            channelDescription: 'Erinnerungen vor dem Ablauf einer Garantie.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelWarrantyReminder(String warrantyId) async {
    try {
      await _initialize();
      await _plugin.cancel(_notificationId(warrantyId));
    } catch (_) {
      // Keep warranty deletion independent from the notification platform.
    }
  }

  static Future<bool?> notificationsEnabled() async {
    await _initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final settings = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return settings?.isEnabled;
    }
    return null;
  }

  static Future<bool> requestPermission() async {
    await _initialize();
    return _requestPermission();
  }

  static Future<bool> sendTestNotification() async {
    try {
      await _initialize();
      if (!await _requestPermission()) return false;
      const testNotificationId = 0x7ffffffe;
      await _plugin.cancel(testNotificationId);
      await _plugin.zonedSchedule(
        testNotificationId,
        'Garantie läuft bald ab!',
        'Dies ist eine Test-Benachrichtigung von BonKeepr.',
        timezone.TZDateTime.now(timezone.local).add(const Duration(seconds: 5)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'warranty_reminders',
            'Garantie-Erinnerungen',
            channelDescription: 'Erinnerungen vor dem Ablauf einer Garantie.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _requestPermission() async {
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? true;
  }

  static int _notificationId(String warrantyId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in warrantyId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
