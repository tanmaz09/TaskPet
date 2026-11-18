import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';
import 'notifications.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = await GameState.load();
  await state.onNewDay();

  runApp(TaskPetApp(state: state));

  // Notifications run AFTER the app is on screen, so they can't block it.
  await setUpNotifications(restToday: state.isRestToday);
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
