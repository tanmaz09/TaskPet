import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Task {
  String id;
  String title;
  int points; // energy value, set by the difficulty tier for new tasks
  int difficulty; // 0 easy, 1 medium, 2 hard
  bool done;

  static const tierPoints = [5, 10, 20];
  static const tierNames = ['Easy', 'Medium', 'Hard'];
  static const tierEmoji = ['🌱', '⚡', '🔥'];

  /// Tasks saved before difficulty existed keep their old points and get the
  /// closest tier, so nothing changes for them.
  static int difficultyForPoints(int p) => p <= 7 ? 0 : (p <= 14 ? 1 : 2);

  Task({
    required this.id,
    required this.title,
    int? points,
    int? difficulty,
    this.done = false,
  })  : difficulty = difficulty ??
            (points == null ? 1 : difficultyForPoints(points)),
        points = points ?? tierPoints[difficulty ?? 1];

  int get weight => difficulty + 1; // effort weight: 1, 2 or 3
  String get difficultyName => tierNames[difficulty];
  String get difficultyEmoji => tierEmoji[difficulty];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'points': points,
        'difficulty': difficulty,
        'done': done,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'],
        title: j['title'],
        points: j['points'] as int? ?? 10,
        difficulty: j['difficulty'] as int?,
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
  final bool perfectWeek; // 7th perfect day of the week: golden feast
  const TaskResult(this.perfectDay, this.bossDefeated,
      [this.perfectWeek = false]);
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
  int perfectWeeks; // weeks with all 7 days perfect
  String feastDate; // yyyy-MM-dd of the last golden feast
  List<String> perfectDates; // yyyy-MM-dd history for the heatmap
  List<String> restDates; // planned rest days (streak-safe)
  List<String> rankedDates; // perfect days with enough effort for leaderboards
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
    this.perfectWeeks = 0,
    this.feastDate = '',
    this.perfectDates = const [],
    this.restDates = const [],
    this.rankedDates = const [],
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

  /// Perfect days in one week needed to defeat the boss. A rest day still
  /// leaves 6 days, so resting never costs you the boss.
  static const bossTarget = 6;

  /// All 7 days perfect in one week: the creature gets a golden feast.
  static const perfectWeekTarget = 7;

  /// A perfect day only counts for leaderboards (later) when the day's tasks
  /// add up to at least this much effort, so one trivial task can't win.
  /// Easy = 1, Medium = 2, Hard = 3.
  static const minRankedWeight = 3;

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

  static DateTime _parseDate(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Whole calendar days from [a] to [b] (DST-safe).
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  /// Handles week rollover and day rollover: resets checkboxes and applies
  /// one penalty (or one streak freeze) for EVERY missed day, not just one.
  ///
  /// Safe to call often (app start, resume, once a minute while open): it
  /// does nothing when the date hasn't changed. Returns true if state changed.
  ///
  /// All state is changed before the first `await`, so two overlapping
  /// calls can't double-apply a penalty.
  Future<bool> onNewDay() async {
    var changed = false;

    final monday = _mondayStr();
    if (weekStart != monday) {
      weekStart = monday;
      bossProgress = 0;
      changed = true;
    }

    final today = _today();
    if (lastCheckDate == today) {
      if (changed) await save();
      return changed;
    }

    if (lastCheckDate.isNotEmpty) {
      final gap = _daysBetween(_parseDate(lastCheckDate), DateTime.now());
      if (gap < 0) {
        // The phone's clock moved backwards. Don't punish or reset anything.
        if (changed) await save();
        return changed;
      }
      if (tasks.isNotEmpty) {
        // Every day from the last check up to yesterday is judged: a planned
        // rest day is skipped, the last-checked day is skipped if it was
        // perfect, and each remaining day counts as missed.
        final last = _parseDate(lastCheckDate);
        var missed = 0;
        for (var i = 0; i < gap && i < 400; i++) {
          final d = _dateStr(DateTime(last.year, last.month, last.day + i));
          if (restDates.contains(d)) continue;
          if (i == 0 && lastPerfectDate == lastCheckDate) continue;
          missed += 1;
        }
        if (missed > 60) missed = 60;
        for (var i = 0; i < missed; i++) {
          if (streak > 0 && freezes > 0) {
            freezes -= 1; // a freeze protects a streak that exists
            energy = (energy - 10).clamp(0, 100);
          } else {
            streak = 0;
            energy = (energy - 25).clamp(0, 100);
          }
        }
      }
    }

    for (final t in tasks) {
      t.done = false;
    }
    lastCheckDate = today;
    await save();
    return true;
  }

  Future<TaskResult> completeTask(Task task) async {
    if (task.done) return const TaskResult(false, false);
    task.done = true;
    energy = (energy + (task.points / 2).round()).clamp(0, 100);

    var perfect = false;
    var bossDefeated = false;
    var perfectWeek = false;
    final today = _today();
    // A day counts once. Adding and finishing a new task after a perfect
    // day does not make a second perfect day.
    if (tasks.isNotEmpty &&
        tasks.every((t) => t.done) &&
        lastPerfectDate != today) {
      perfect = true;
      streak += 1;
      if (streak > longestStreak) longestStreak = streak;
      totalPerfectDays += 1;
      if (!perfectDates.contains(today)) perfectDates.add(today);
      if (perfectDates.length > 400) {
        perfectDates.removeRange(0, perfectDates.length - 400);
      }
      if (dayCanBeRanked && !rankedDates.contains(today)) {
        rankedDates.add(today);
        if (rankedDates.length > 400) {
          rankedDates.removeRange(0, rankedDates.length - 400);
        }
      }
      energy = (energy + 20).clamp(0, 100);
      lastPerfectDate = today;

      bossProgress += 1;
      if (bossProgress == bossTarget) {
        bossesDefeated += 1;
        freezes = (freezes + 1).clamp(0, maxFreezes);
        bossDefeated = true;
      }
      if (bossProgress == perfectWeekTarget) {
        perfectWeeks += 1;
        feastDate = today;
        energy = 100;
        perfectWeek = true;
      }
    }
    await save();
    return TaskResult(perfect, bossDefeated, perfectWeek);
  }

  Future<void> addTask(String title, int difficulty) async {
    tasks.add(Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      difficulty: difficulty,
    ));
    await save();
  }

  /// The title can always change. Difficulty can't change once the task is
  /// done today, because its energy was already given.
  Future<void> editTask(Task task, String title, int difficulty) async {
    task.title = title;
    if (!task.done && task.difficulty != difficulty) {
      task.difficulty = difficulty;
      task.points = Task.tierPoints[difficulty];
    }
    await save();
  }

  Future<void> deleteTask(Task task) async {
    tasks.removeWhere((t) => t.id == task.id);
    await save();
  }

  int get doneToday => tasks.where((t) => t.done).length;

  /// Total effort of today's tasks (Easy 1, Medium 2, Hard 3).
  int get totalWeight => tasks.fold<int>(0, (a, t) => a + t.weight);
  bool get dayCanBeRanked => totalWeight >= minRankedWeight;

  /// The golden feast glow lasts the rest of that day and all of the next.
  bool get feastActive =>
      feastDate.isNotEmpty &&
      (feastDate == _today() || feastDate == _today(offsetDays: -1));

  // ---------- rest day (one per week) ----------

  bool get isRestToday => restDates.contains(_today());

  bool get restUsedThisWeek =>
      restDates.any((d) => d.compareTo(weekStart) >= 0);

  bool get canTakeRest =>
      tasks.isNotEmpty &&
      !isRestToday &&
      !restUsedThisWeek &&
      lastPerfectDate != _today();

  Future<void> takeRestDay() async {
    if (!canTakeRest) return;
    restDates.add(_today());
    if (restDates.length > 60) {
      restDates.removeRange(0, restDates.length - 60);
    }
    await save();
  }

  // ---------- backup ----------

  Map<String, dynamic> toBackup() => {
        'version': 4,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'energy': energy,
        'streak': streak,
        'longestStreak': longestStreak,
        'perfect': totalPerfectDays,
        'freezes': freezes,
        'bossProgress': bossProgress,
        'bossesDefeated': bossesDefeated,
        'perfectWeeks': perfectWeeks,
        'feastDate': feastDate,
        'perfectDates': perfectDates,
        'restDates': restDates,
        'rankedDates': rankedDates,
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
    perfectWeeks = j['perfectWeeks'] ?? 0;
    feastDate = j['feastDate'] ?? '';
    perfectDates = (j['perfectDates'] as List? ?? []).cast<String>();
    restDates = (j['restDates'] as List? ?? []).cast<String>();
    rankedDates = (j['rankedDates'] as List? ?? []).cast<String>();
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
      perfectWeeks: p.getInt('perfectWeeks') ?? 0,
      feastDate: p.getString('feastDate') ?? '',
      perfectDates: (jsonDecode(p.getString('perfectDates') ?? '[]') as List)
          .cast<String>(),
      restDates: (jsonDecode(p.getString('restDates') ?? '[]') as List)
          .cast<String>(),
      rankedDates: (jsonDecode(p.getString('rankedDates') ?? '[]') as List)
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
    await p.setInt('perfectWeeks', perfectWeeks);
    await p.setString('feastDate', feastDate);
    await p.setString('perfectDates', jsonEncode(perfectDates));
    await p.setString('restDates', jsonEncode(restDates));
    await p.setString('rankedDates', jsonEncode(rankedDates));
    await p.setString('lastCheck', lastCheckDate);
    await p.setString('lastPerfect', lastPerfectDate);
    await p.setString('weekStart', weekStart);
  }
}
