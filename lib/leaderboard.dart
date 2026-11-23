import 'models.dart';

/// Perfect days this week that count for the leaderboard: only days whose
/// tasks added up to enough effort (Easy 1, Medium 2, Hard 3, total 3+), so
/// one trivial task can't win. Capped at 7.
int rankedThisWeek(GameState s) {
  final week = s.weekStart;
  final n = s.rankedDates.where((d) => d.compareTo(week) >= 0).length;
  return n > 7 ? 7 : n;
}

class LeaderboardRow {
  final String uid;
  final String name;
  final int stage;
  final int week; // ranked perfect days this week
  final int streak;
  final bool isMe;

  /// 1, 2, 3... with ties sharing a rank; null when there are no ranked
  /// days yet (nobody is ranked last for having a quiet week).
  int? rank;

  LeaderboardRow({
    required this.uid,
    required this.name,
    required this.stage,
    required this.week,
    required this.streak,
    this.isMe = false,
  });
}

/// Sorts by this week's score (then streak, then name) and assigns ranks.
/// Equal scores share a rank (1, 1, 3), and a score of 0 gets no rank.
List<LeaderboardRow> rankLeaderboard(List<LeaderboardRow> input) {
  final rows = [...input];
  rows.sort((a, b) {
    var c = b.week.compareTo(a.week);
    if (c != 0) return c;
    c = b.streak.compareTo(a.streak);
    if (c != 0) return c;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  int? lastWeek;
  var lastRank = 0;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.week <= 0) {
      r.rank = null;
      continue;
    }
    if (lastWeek != null && r.week == lastWeek) {
      r.rank = lastRank;
    } else {
      lastRank = i + 1;
      lastWeek = r.week;
      r.rank = lastRank;
    }
  }
  return rows;
}
