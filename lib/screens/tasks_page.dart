import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
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
    final pointsCtrl = TextEditingController(text: '10');
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New daily task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Task (e.g. Read 20 min)'),
            ),
            TextField(
              controller: pointsCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Points (energy gained)'),
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
              final points = int.tryParse(pointsCtrl.text.trim()) ?? 10;
              Navigator.pop(ctx, (title, points));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.state.addTask(result.$1, result.$2);
      widget.onChanged();
    }
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
            '7 perfect days in one week!\n\nReward: +1 🧊 streak freeze',
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PERFECT DAY! 🎉 Your creature grows stronger.'),
        backgroundColor: Colors.green,
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
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: s.tasks.length,
                        itemBuilder: (_, i) => _TaskTile(
                          key: ValueKey(s.tasks[i].id),
                          task: s.tasks[i],
                          index: i,
                          onCheck: (pos) => _onChecked(s.tasks[i], pos),
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
  final VoidCallback onDelete;
  const _TaskTile({
    super.key,
    required this.task,
    required this.index,
    required this.onCheck,
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
                : Text('${task.points} pts · tap to complete',
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
