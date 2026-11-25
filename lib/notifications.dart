import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

final Completer<void> _notificationsReady = Completer<void>();

/// Uses the phone's own timezone. If the name isn't in the timezone
/// database (some old Android IDs), falls back to any zone with the same
/// current UTC offset so reminders still fire at the right local hour.
Future<void> configureLocalTimezone() async {
  tzdata.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {
    final offsetMs = DateTime.now().timeZoneOffset.inMilliseconds;
    final match = tz.timeZoneDatabase.locations.values.firstWhere(
      (l) => l.currentTimeZone.offset == offsetMs,
      orElse: () => tz.UTC,
    );
    tz.setLocalLocation(match);
  }
}

tz.TZDateTime _nextInstanceOf(int hour, {bool skipToday = false}) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
  if (skipToday || scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

/// Schedules the daily 9 AM and 9 PM reminders. On a rest day the first
/// reminders start tomorrow, so today stays quiet. Calling this again
/// replaces the old schedule.
Future<void> scheduleDailyReminders({bool restToday = false}) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'taskpet_daily',
      'Daily reminders',
      channelDescription: 'Reminders to complete your daily tasks',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  // Morning reminder: 9 AM
  await notifications.zonedSchedule(
    1,
    'TaskPet',
    'Clear your daily tasks to feed your creature!',
    _nextInstanceOf(9, skipToday: restToday),
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
  // Evening pressure: 9 PM
  await notifications.zonedSchedule(
    2,
    'Your creature is waiting 🐣',
    "Finish today's tasks before the day ends!",
    _nextInstanceOf(21, skipToday: restToday),
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

/// One-time setup: timezone, plugin init, schedule. The permission prompt
/// is NOT shown here any more; see [askForNotificationsOnce].
Future<void> setUpNotifications({required bool restToday}) async {
  try {
    await configureLocalTimezone();
    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await scheduleDailyReminders(restToday: restToday);
  } catch (e) {
    debugPrint('Notification setup failed: $e');
  } finally {
    if (!_notificationsReady.isCompleted) _notificationsReady.complete();
  }
}

/// Explains why TaskPet sends reminders, then asks for permission. Shown at
/// most once, and never if notifications are already allowed.
Future<void> askForNotificationsOnce(BuildContext context) async {
  await _notificationsReady.future;
  final android = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('notif_asked') ?? false) return;

  final enabled = await android.areNotificationsEnabled() ?? true;
  if (enabled) {
    await prefs.setBool('notif_asked', true);
    return;
  }
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('🔔 Gentle reminders?'),
      content: const Text(
        'TaskPet can remind you at 9 AM and 9 PM to finish your tasks. '
        'That is all it sends: no ads, no spam. On rest days it stays quiet.\n\n'
        'Tip: if reminders ever arrive late, set TaskPet to "Unrestricted" '
        'in your phone\'s battery settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Allow reminders'),
        ),
      ],
    ),
  );
  await prefs.setBool('notif_asked', true);
  if (ok != true) return;

  final granted = await android.requestNotificationsPermission() ?? false;
  if (!granted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            "No problem. You can turn reminders on later in the phone's "
            'app settings.'),
      ),
    );
  }
}
