import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../notifications.dart';
import '../widgets/energy_orb.dart';
import '../widgets/evolution_overlay.dart';

class TasksPage extends StatefulWidget {
  final GameState state;
  final VoidCallback onChanged;
  const TasksPage({super.key, required this.state, required this.onChanged});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _addTask() async {
    final titleCtrl = TextEditingController();
    var difficulty = 1;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New daily task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Task (e.g. Read 20 min)'),
              ),
              const SizedBox(height: 18),
              const Text('How hard is it?'),
              const SizedBox(height: 8),
              _DifficultyPicker(
                value: difficulty,
                onChanged: (v) => setLocal(() => difficulty = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Harder tasks feed your creature more.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx, (title, difficulty));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.state.addTask(result.$1, result.$2);
      widget.onChanged();
    }
  }

  Future<void> _editTask(Task task) async {
    final titleCtrl = TextEditingController(text: task.title);
    var difficulty = task.difficulty;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Task'),
              ),
              const SizedBox(height: 18),
              const Text('Difficulty'),
              const SizedBox(height: 8),
              _DifficultyPicker(
                value: difficulty,
                enabled: !task.done,
                onChanged: (v) => setLocal(() => difficulty = v),
              ),
              if (task.done) ...[
                const SizedBox(height: 8),
                const Text(
                  'Done today, so the difficulty is locked until tomorrow.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx, (title, difficulty));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.state.editTask(task, result.$1, result.$2);
      widget.onChanged();
    }
  }

  Future<void> _confirmRest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🌙 Take today as a rest day?'),
        content: const Text(
          'Your streak and creature stay safe today, even if you finish '
          'nothing.\n\n'
          'You get one rest day per week. It does not count toward the '
          'weekly boss, and reminders stay quiet for the rest of today.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Take rest day'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.state.takeRestDay();
    widget.onChanged();
    try {
      await scheduleDailyReminders(restToday: true);
    } catch (e) {
      debugPrint('Could not update reminders: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rest well 🌙 Your streak is safe today.')),
    );
  }

  /// [from] is the screen position of the task that was tapped; the energy
  /// orb flies from there to the Creature tab.
  Future<void> _onChecked(Task task, Offset from) async {
    final stageBefore = widget.state.stage;
    final res = await widget.state.completeTask(task);
    final stageAfter = widget.state.stage;
    widget.onChanged();

    if (!mounted) return;
    flyEnergyOrb(context, from: from);

    if (!res.perfectDay) {
      HapticFeedback.selectionClick();
      return;
    }

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);

    // Let the orb land before the big moments start.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    if (stageAfter != stageBefore) {
      await showEvolution(
        context,
        fromStage: GameState.stages.indexOf(stageBefore),
        toStage: GameState.stages.indexOf(stageAfter),
        emoji: stageAfter.emoji,
        name: stageAfter.name,
      );
      if (!mounted) return;
    }

    _confetti.play();

    if (res.bossDefeated) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚔️ WEEKLY BOSS DEFEATED!'),
          content: const Text(
            '6 perfect days in one week!\n\nReward: +1 🧊 streak freeze\n\nFinish all 7 days for a 🌟 golden feast.',
            style: TextStyle(fontSize: 18),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Claim reward'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    if (res.perfectWeek) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🌟 PERFECT WEEK!'),
          content: const Text(
            'All 7 days perfect!\n\nYour creature enjoys a golden feast: '
            'energy fully restored and a golden glow for two days.',
            style: TextStyle(fontSize: 18),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Feast!'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PERFECT DAY! 🎉 Your creature grows stronger.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _restAndTips(GameState s) {
    if (s.isRestToday) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.indigo.withOpacity(0.18),
            border: Border.all(color: Colors.indigoAccent.withOpacity(0.35)),
          ),
          child: const Text(
            '🌙 Rest day. Your streak is safe today. You can still finish '
            'tasks if you feel like it.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    final tips = <Widget>[];
    if (s.canTakeRest) {
      tips.add(Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _confirmRest,
          icon: const Icon(Icons.bedtime_outlined, size: 18),
          label: const Text('Take a rest day'),
        ),
      ));
    }
    if (!s.dayCanBeRanked) {
      tips.add(const Text(
        'Tip: a day needs at least 3 effort points to count for leaderboards '
        '(Easy 1, Medium 2, Hard 3). Add a harder task or two.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ));
    }
    if (tips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tips,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
          body: s.tasks.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No tasks yet.\n\nAdd your fixed daily tasks — your creature can ONLY be fed by completing them all.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _StatsCard(state: s),
                    ),
                    _restAndTips(s),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: s.tasks.length,
                        itemBuilder: (_, i) => _TaskTile(
                          key: ValueKey(s.tasks[i].id),
                          task: s.tasks[i],
                          index: i,
                          onCheck: (pos) => _onChecked(s.tasks[i], pos),
                          onEdit: () => _editTask(s.tasks[i]),
                          onDelete: () async {
                            await s.deleteTask(s.tasks[i]);
                            widget.onChanged();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 35,
            child: const SizedBox(width: double.infinity, height: 200),
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final GameState state;
  const _StatsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Colors.teal.withOpacity(0.25),
            Colors.teal.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('${state.streak}', '🔥 streak'),
          _divider(),
          _stat('${state.doneToday}/${state.tasks.length}', "today"),
          _divider(),
          _stat('${state.freezes}', '🧊 freezes'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      );

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: Colors.white.withOpacity(0.08),
      );
}

class _TaskTile extends StatefulWidget {
  final Task task;
  final int index;
  final void Function(Offset from) onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _TaskTile({
    super.key,
    required this.task,
    required this.index,
    required this.onCheck,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    Future.delayed(Duration(milliseconds: widget.index * 70), () {
      if (mounted) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Where the check icon sits on screen, so the energy orb can start there.
    final box = context.findRenderObject() as RenderBox?;
    final from = (box != null && box.hasSize)
        ? box.localToGlobal(Offset(44, box.size.height / 2))
        : const Offset(60, 300);
    widget.onCheck(from);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final curved = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero)
          .animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: task.done
                  ? [Colors.teal.withOpacity(0.20), Colors.teal.withOpacity(0.06)]
                  : [
                      Colors.white.withOpacity(0.045),
                      Colors.white.withOpacity(0.015),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: task.done
                  ? Colors.teal.withOpacity(0.55)
                  : Colors.white.withOpacity(0.07),
            ),
          ),
          child: ListTile(
            onTap: task.done ? null : _handleTap,
            onLongPress: widget.onEdit,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: AnimatedScale(
              scale: task.done ? 1.25 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.elasticOut,
              child: Icon(
                task.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: task.done ? Colors.tealAccent : Colors.grey,
                size: 26,
              ),
            ),
            title: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                decoration:
                    task.done ? TextDecoration.lineThrough : null,
                color: task.done ? Colors.grey : Colors.white,
                fontSize: 16,
              ),
              child: Text(task.title),
            ),
            subtitle: task.done
                ? const Text('Done — locked until tomorrow ✅',
                    style: TextStyle(fontSize: 12))
                : Text(
                    '${task.difficultyEmoji} ${task.difficultyName} · tap to complete · hold to edit',
                    style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.grey,
              onPressed: widget.onDelete,
            ),
          ),
        ),
      ),
    );
  }
}


class _DifficultyPicker extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _DifficultyPicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < Task.tierNames.length; i++)
          ChoiceChip(
            label: Text('${Task.tierEmoji[i]} ${Task.tierNames[i]}'),
            selected: value == i,
            onSelected: enabled ? (_) => onChanged(i) : null,
          ),
      ],
    );
  }
}
