import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

/// Uses the phone's own timezone. If the name isn't in the timezone
/// database (some old Android IDs), falls back to any zone with the same
/// current UTC offset so reminders still fire at the right local hour.
Future<void> _configureLocalTimezone() async {
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

  final state = await GameState.load();
  await state.onNewDay();

  runApp(TaskPetApp(state: state));

  // Notifications run AFTER the app is on screen, so they can't block it.
  try {
    await _configureLocalTimezone();
    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await scheduleDailyReminders();
  } catch (e) {
    debugPrint('Notification setup failed: $e');
  }
}

class TaskPetApp extends StatefulWidget {
  final GameState state;
  const TaskPetApp({super.key, required this.state});

  @override
  State<TaskPetApp> createState() => _TaskPetAppState();
}

class _TaskPetAppState extends State<TaskPetApp> with WidgetsBindingObserver {
  bool? _onboarded;
  Timer? _dayWatcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GameState.isOnboarded().then((v) => setState(() => _onboarded = v));
    // Catches midnight while the app is open on screen.
    _dayWatcher =
        Timer.periodic(const Duration(minutes: 1), (_) => _checkNewDay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayWatcher?.cancel();
    super.dispose();
  }

  Future<void> _checkNewDay() async {
    final changed = await widget.state.onNewDay();
    if (changed && mounted) setState(() {});
  }

  // Catches the app coming back from the background on a new day.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _checkNewDay();
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
