import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Task {
  String id;
  String title;
  int points;
  bool done;

  Task({
    required this.id,
    required this.title,
    this.points = 10,
    this.done = false,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'points': points, 'done': done};

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'],
        title: j['title'],
        points: j['points'] ?? 10,
        done: j['done'] ?? false,
      );
}

class CreatureStage {
  final String emoji;
  final String name;
  final int threshold; // total perfect days needed
  const CreatureStage(this.emoji, this.name, this.threshold);
}

class TaskResult {
  final bool perfectDay;
  final bool bossDefeated;
  const TaskResult(this.perfectDay, this.bossDefeated);
}

class GameState {
  List<Task> tasks;
  int energy; // 0-100, creature's condition
  int streak; // consecutive perfect days
  int longestStreak;
  int totalPerfectDays;
  int freezes; // streak freezes, earned from weekly boss
  int bossProgress; // perfect days this week (0-7)
  int bossesDefeated;
  List<String> perfectDates; // yyyy-MM-dd history for the heatmap
  String lastCheckDate;
  String lastPerfectDate;
  String weekStart; // yyyy-MM-dd of current week's Monday

  GameState({
    this.tasks = const [],
    this.energy = 50,
    this.streak = 0,
    this.longestStreak = 0,
    this.totalPerfectDays = 0,
    this.freezes = 0,
    this.bossProgress = 0,
    this.bossesDefeated = 0,
    this.perfectDates = const [],
    this.lastCheckDate = '',
    this.lastPerfectDate = '',
    this.weekStart = '',
  });

  static const stages = [
    CreatureStage('🥚', 'Egg', 0),
    CreatureStage('🐣', 'Hatchling', 3),
    CreatureStage('🐥', 'Fledgling', 7),
    CreatureStage('🦅', 'Soaring', 14),
    CreatureStage('🐉', 'Dragon', 30),
  ];

  static const maxFreezes = 3;

  CreatureStage get stage =>
      stages.reversed.firstWhere((s) => totalPerfectDays >= s.threshold);

  int? get nextThreshold {
    for (final s in stages) {
      if (s.threshold > totalPerfectDays) return s.threshold;
    }
    return null;
  }

  String get mood {
    if (energy >= 70) return '😄 Thriving';
    if (energy >= 40) return '🙂 Content';
    if (energy > 0) return '😟 Struggling';
    return '😴 Starving — complete tasks now!';
  }

  static String _dateStr(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _today({int offsetDays = 0}) =>
      _dateStr(DateTime.now().add(Duration(days: offsetDays)));

  static String _mondayStr() {
    final now = DateTime.now();
    final monday =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return _dateStr(monday);
  }

  /// Called on every app start. Handles week rollover and day rollover:
  /// resets checkboxes, applies decay (or consumes a streak freeze).
  Future<void> onNewDay() async {
    final monday = _mondayStr();
    if (weekStart != monday) {
      weekStart = monday;
      bossProgress = 0;
    }

    final today = _today();
    if (lastCheckDate == today) {
      await save();
      return;
    }

    final yesterday = _today(offsetDays: -1);
    if (tasks.isNotEmpty && lastPerfectDate != yesterday) {
      if (freezes > 0) {
        freezes -= 1; // streak freeze consumed automatically
        energy = (energy - 10).clamp(0, 100);
      } else {
        streak = 0;
        energy = (energy - 25).clamp(0, 100);
      }
    }
    for (final t in tasks) {
      t.done = false;
    }
    lastCheckDate = today;
    await save();
  }

  Future<TaskResult> completeTask(Task task) async {
    if (task.done) return const TaskResult(false, false);
    task.done = true;
    energy = (energy + (task.points / 2).round()).clamp(0, 100);

    var perfect = false;
    var bossDefeated = false;
    if (tasks.isNotEmpty && tasks.every((t) => t.done)) {
      perfect = true;
      streak += 1;
      if (streak > longestStreak) longestStreak = streak;
      totalPerfectDays += 1;
      final today = _today();
      if (!perfectDates.contains(today)) perfectDates.add(today);
      if (perfectDates.length > 400) {
        perfectDates.removeRange(0, perfectDates.length - 400);
      }
      energy = (energy + 20).clamp(0, 100);
      lastPerfectDate = today;
      bossProgress += 1;
      if (bossProgress >= 7) {
        bossProgress = 0;
        bossesDefeated += 1;
        freezes = (freezes + 1).clamp(0, maxFreezes);
        bossDefeated = true;
      }
    }
    await save();
    return TaskResult(perfect, bossDefeated);
  }

  Future<void> addTask(String title, int points) async {
    tasks.add(Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      points: points,
    ));
    await save();
  }

  Future<void> deleteTask(Task task) async {
    tasks.removeWhere((t) => t.id == task.id);
    await save();
  }

  int get doneToday => tasks.where((t) => t.done).length;

  // ---------- backup ----------

  Map<String, dynamic> toBackup() => {
        'version': 2,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'energy': energy,
        'streak': streak,
        'longestStreak': longestStreak,
        'perfect': totalPerfectDays,
        'freezes': freezes,
        'bossProgress': bossProgress,
        'bossesDefeated': bossesDefeated,
        'perfectDates': perfectDates,
        'lastCheck': lastCheckDate,
        'lastPerfect': lastPerfectDate,
        'weekStart': weekStart,
      };

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(toBackup());

  Future<void> importJson(String raw) async {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    tasks = (j['tasks'] as List? ?? [])
        .map((e) => Task.fromJson(e))
        .toList();
    energy = j['energy'] ?? 50;
    streak = j['streak'] ?? 0;
    longestStreak = j['longestStreak'] ?? 0;
    totalPerfectDays = j['perfect'] ?? 0;
    freezes = j['freezes'] ?? 0;
    bossProgress = j['bossProgress'] ?? 0;
    bossesDefeated = j['bossesDefeated'] ?? 0;
    perfectDates = (j['perfectDates'] as List? ?? []).cast<String>();
    lastCheckDate = j['lastCheck'] ?? '';
    lastPerfectDate = j['lastPerfect'] ?? '';
    weekStart = j['weekStart'] ?? '';
    await save();
  }

  // ---------- onboarding ----------

  static Future<bool> isOnboarded() async =>
      (await SharedPreferences.getInstance()).getBool('onboarded') ?? false;

  static Future<void> markOnboarded() async =>
      (await SharedPreferences.getInstance()).setBool('onboarded', true);

  // ---------- persistence ----------

  static Future<GameState> load() async {
    final p = await SharedPreferences.getInstance();
    final tasksJson = p.getString('tasks') ?? '[]';
    return GameState(
      tasks: (jsonDecode(tasksJson) as List)
          .map((e) => Task.fromJson(e))
          .toList(),
      energy: p.getInt('energy') ?? 50,
      streak: p.getInt('streak') ?? 0,
      longestStreak: p.getInt('longestStreak') ?? 0,
      totalPerfectDays: p.getInt('perfect') ?? 0,
      freezes: p.getInt('freezes') ?? 0,
      bossProgress: p.getInt('bossProgress') ?? 0,
      bossesDefeated: p.getInt('bossesDefeated') ?? 0,
      perfectDates: (jsonDecode(p.getString('perfectDates') ?? '[]') as List)
          .cast<String>(),
      lastCheckDate: p.getString('lastCheck') ?? '',
      lastPerfectDate: p.getString('lastPerfect') ?? '',
      weekStart: p.getString('weekStart') ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tasks', jsonEncode(tasks.map((t) => t.toJson()).toList()));
    await p.setInt('energy', energy);
    await p.setInt('streak', streak);
    await p.setInt('longestStreak', longestStreak);
    await p.setInt('perfect', totalPerfectDays);
    await p.setInt('freezes', freezes);
    await p.setInt('bossProgress', bossProgress);
    await p.setInt('bossesDefeated', bossesDefeated);
    await p.setString('perfectDates', jsonEncode(perfectDates));
    await p.setString('lastCheck', lastCheckDate);
    await p.setString('lastPerfect', lastPerfectDate);
    await p.setString('weekStart', weekStart);
  }
}
