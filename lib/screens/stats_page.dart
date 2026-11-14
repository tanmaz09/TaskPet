import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';

class StatsPage extends StatelessWidget {
  final GameState state;
  final VoidCallback onChanged;
  const StatsPage({super.key, required this.state, required this.onChanged});

  static String _dateStr(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _export(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final file =
          await File('${dir.path}/taskpet_backup.json').create();
      await file.writeAsString(state.exportJson());
      await Share.shareXFiles([XFile(file.path)],
          text: 'TaskPet backup');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null || picked.files.single.path == null) return;
      final raw =
          await File(picked.files.single.path!).readAsString();
      await state.importJson(raw);
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restored ✅')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final today = DateTime.now();
    final todayStr = _dateStr(today);

    // Build the last 12 weeks (84 days), Monday-first, blanks for days
    // before the 84-day window.
    final days = <String?>[];
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 83));
    // pad leading blanks so the first column starts on Monday
    final pad = start.weekday - 1;
    days.addAll(List.filled(pad, null));
    for (var i = 0; i < 84; i++) {
      days.add(_dateStr(start.add(Duration(days: i))));
    }

    const perfectColor = Color(0xFF2EC4A6);
    const noneColor = Color(0xFF2A2A2A);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stat cards
        Row(
          children: [
            _statCard(context, '🔥', '${s.longestStreak}', 'best streak'),
            _statCard(context, '🏆', '${s.totalPerfectDays}', 'perfect days'),
            _statCard(context, '⚔️', '${s.bossesDefeated}', 'bosses beaten'),
            _statCard(context, '🧊', '${s.freezes}', 'freezes'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚔️ Weekly Boss',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    'Get 7 perfect days in one week to defeat the boss and earn +1 🧊 streak freeze.'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.bossProgress / 7),
                const SizedBox(height: 4),
                Text('${s.bossProgress}/7 this week'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Last 12 weeks',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var col = 0; col < days.length / 7; col++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Column(
                            children: [
                              for (var row = 0; row < 7; row++)
                                () {
                                  final d = days[col * 7 + row];
                                  final isPerfect =
                                      d != null && s.perfectDates.contains(d);
                                  final isToday = d == todayStr;
                                  return Container(
                                    width: 16,
                                    height: 16,
                                    margin: const EdgeInsets.all(1.5),
                                    decoration: BoxDecoration(
                                      color: isPerfect
                                          ? perfectColor
                                          : noneColor,
                                      borderRadius:
                                          BorderRadius.circular(3),
                                      border: isToday
                                          ? Border.all(
                                              color: Colors.white,
                                              width: 1.5)
                                          : null,
                                    ),
                                  );
                                }(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Each green square = a perfect day',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Backup',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                    'Export your progress as a JSON file, or restore from a previous backup.'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _export(context),
                      icon: const Icon(Icons.upload),
                      label: const Text('Export'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _import(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Import'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(
      BuildContext context, String emoji, String value, String label) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
