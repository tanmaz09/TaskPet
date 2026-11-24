import 'package:flutter/material.dart';
import '../models.dart';
import 'creature_page.dart';
import 'friends_page.dart';
import 'stats_page.dart';
import 'tasks_page.dart';
import '../notifications.dart';

class HomeScreen extends StatefulWidget {
  final GameState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final AnimationController _bg;

  @override
  void initState() {
    super.initState();
    _bg = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
        WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askForNotificationsOnce(context);
    });
  }

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pages = [
      TasksPage(state: widget.state, onChanged: refresh),
      // Tell the creature page when it is on screen so it can rest otherwise.
      CreaturePage(state: widget.state, active: _tab == 1),
      FriendsPage(state: widget.state, active: _tab == 2),
      StatsPage(state: widget.state, onChanged: refresh),
    ];

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('TaskPet'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF12544C).withOpacity(0.85),
                const Color(0xFF0A2E2E).withOpacity(0.4),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white.withOpacity(0.04),
          indicatorColor: Colors.teal.withOpacity(0.25),
          labelTextStyle: MaterialStateProperty.all(
            const TextStyle(fontSize: 12),
          ),
        ),
        child: NavigationBar(
          elevation: 0,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
            NavigationDestination(icon: Icon(Icons.pets), label: 'Creature'),
            NavigationDestination(icon: Icon(Icons.group), label: 'Friends'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          ],
        ),
      ),
    );

    // The drifting background repaints every frame; passing the scaffold as
    // `child` means only the gradient is rebuilt, not the whole screen.
    return AnimatedBuilder(
      animation: _bg,
      child: scaffold,
      builder: (context, child) {
        final dx = 0.5 + 0.3 * _bg.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + dx, -1),
              end: Alignment(1 - dx, 1),
              colors: const [
                Color(0xFF0B2424),
                Color(0xFF0E2E2C),
                Color(0xFF0A1F24),
              ],
            ),
          ),
          child: child,
        );
      },
    );
  }
}
