import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

/// CHANGE THIS to your timezone (e.g. 'America/New_York', 'Europe/London').
const String localTimezone = 'Asia/Dhaka';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

tz.TZDateTime _nextInstanceOf(int hour) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

Future<void> scheduleDailyReminders() async {
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
    _nextInstanceOf(9),
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
    _nextInstanceOf(21),
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(localTimezone));

  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final state = await GameState.load();
  await state.onNewDay();
  await scheduleDailyReminders();

  runApp(TaskPetApp(state: state));
}

class TaskPetApp extends StatefulWidget {
  final GameState state;
  const TaskPetApp({super.key, required this.state});

  @override
  State<TaskPetApp> createState() => _TaskPetAppState();
}

class _TaskPetAppState extends State<TaskPetApp> {
  bool? _onboarded;

  @override
  void initState() {
    super.initState();
    GameState.isOnboarded()
        .then((v) => setState(() => _onboarded = v));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskPet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: _onboarded == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _onboarded!
              ? HomeScreen(state: widget.state)
              : OnboardingScreen(
                  onDone: () async {
                    await GameState.markOnboarded();
                    setState(() => _onboarded = true);
                  },
                ),
    );
  }
}
