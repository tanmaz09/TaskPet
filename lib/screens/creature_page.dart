import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import 'creature_painter.dart';

class CreaturePage extends StatefulWidget {
  final GameState state;
  const CreaturePage({super.key, required this.state});

  @override
  State<CreaturePage> createState() => _CreaturePageState();
}

class _CreaturePageState extends State<CreaturePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final stageIndex = GameState.stages.indexOf(s.stage);
    final next = s.nextThreshold;
    final progress = next == null
        ? 1.0
        : (s.totalPerfectDays - GameState.stages[stageIndex].threshold) /
            (next - GameState.stages[stageIndex].threshold);
    final allDone =
        s.tasks.isNotEmpty && s.tasks.every((t) => t.done);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 300,
                width: double.infinity,
                child: CustomPaint(
                  painter: CreaturePainter(
                    stage: stageIndex,
                    energy: s.energy,
                    t: _anim.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${s.stage.emoji} ${s.stage.name}',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Stage ${stageIndex + 1} of ${GameState.stages.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (next != null) ...[
              Text(
                '${s.totalPerfectDays}/$next perfect days to next evolution',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            ] else
              const Text(
                '👑 FINAL FORM. Keep your streak alive!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white.withOpacity(0.04),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Energy  ${s.energy}/100'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: s.energy / 100,
                    color: s.energy < 25 ? Colors.red : Colors.teal,
                  ),
                  const SizedBox(height: 12),
                  Text('Mood: ${s.mood}'),
                  const SizedBox(height: 12),
                  Text('🧊 Streak freezes: ${s.freezes}/${GameState.maxFreezes}'),
                  const SizedBox(height: 4),
                  Text('⚔️ Weekly boss: ${s.bossProgress}/7 perfect days'),
                  const Divider(height: 24),
                  Text(
                    allDone
                        ? "✅ All tasks done today. Your creature is fed and happy!"
                        : "⚠️ ${s.tasks.length - s.doneToday} task(s) unfinished. Your creature is waiting — completing tasks is the ONLY way to feed it.",
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
