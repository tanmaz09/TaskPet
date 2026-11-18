import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import 'creature_painter.dart';

class CreaturePage extends StatefulWidget {
  final GameState state;

  /// False while another tab is showing, so the animations can rest.
  final bool active;
  const CreaturePage({super.key, required this.state, this.active = true});

  @override
  State<CreaturePage> createState() => _CreaturePageState();
}

class _CreaturePageState extends State<CreaturePage>
    with TickerProviderStateMixin {
  late final AnimationController _anim; // looping scene motion
  late final AnimationController _hopCtl; // tap hop
  late final AnimationController _blinkCtl; // one blink
  late final AnimationController _giggleCtl; // hearts after a tap
  final ValueNotifier<Offset> _look = ValueNotifier(Offset.zero);
  late final Listenable _repaint;

  final math.Random _rnd = math.Random();
  Timer? _blinkTimer;
  Timer? _lookReset;
  DateTime? _wakeUntil;
  bool _reduceMotion = false;

  bool get _animate => widget.active && !_reduceMotion;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    _hopCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _blinkCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _giggleCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _repaint =
        Listenable.merge([_anim, _hopCtl, _blinkCtl, _giggleCtl, _look]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the phone's "remove animations" accessibility setting.
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncRunning();
  }

  @override
  void didUpdateWidget(CreaturePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRunning();
  }

  void _syncRunning() {
    if (_animate) {
      if (!_anim.isAnimating) _anim.repeat();
      if (_blinkTimer == null) _scheduleBlink();
    } else {
      _anim.stop();
      _blinkTimer?.cancel();
      _blinkTimer = null;
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _rnd.nextInt(3200)), () {
      if (!mounted || !_animate) {
        _blinkTimer = null;
        return;
      }
      _blinkCtl.forward(from: 0).then((_) {
        if (mounted) _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _lookReset?.cancel();
    _anim.dispose();
    _hopCtl.dispose();
    _blinkCtl.dispose();
    _giggleCtl.dispose();
    _look.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ touch

  void _poke() {
    // Touching a sleeping creature wakes it for a while.
    _wakeUntil = DateTime.now().add(const Duration(seconds: 10));
    HapticFeedback.lightImpact();
    if (_reduceMotion) {
      setState(() {});
      return;
    }
    _hopCtl.forward(from: 0);
    _giggleCtl.forward(from: 0);
  }

  void _updateLook(Offset local, Size size) {
    _lookReset?.cancel();
    final dx = (local.dx - size.width / 2) / (size.width / 2);
    final dy = (local.dy - size.height * 0.6) / (size.height * 0.6);
    _look.value = Offset(
      dx.clamp(-1.0, 1.0).toDouble(),
      dy.clamp(-1.0, 1.0).toDouble(),
    );
  }

  void _releaseLook() {
    _lookReset?.cancel();
    _lookReset = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _look.value = Offset.zero;
    });
  }

  // ------------------------------------------------------------ build

  CreaturePainter _painter(int stageIndex, bool allDone) {
    final s = widget.state;
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;
    final isNight = hour >= 23 || hour < 5;
    final awake = _wakeUntil != null && now.isBefore(_wakeUntil!);
    final sleeping = isNight && !awake && s.energy > 0;
    final hungry =
        !sleeping && hour >= 17 && s.tasks.isNotEmpty && !allDone;

    return CreaturePainter(
      stage: stageIndex,
      energy: s.energy,
      t: _anim.value,
      hour: hour,
      blink: math.sin(_blinkCtl.value * math.pi),
      hop: _hopCtl.value,
      giggle:
          _giggleCtl.status == AnimationStatus.dismissed ? 1.0 : _giggleCtl.value,
      look: _look.value,
      sleeping: sleeping,
      hungry: hungry,
    );
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
    final allDone = s.tasks.isNotEmpty && s.tasks.every((t) => t.done);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 300,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return Listener(
                  onPointerDown: (e) => _updateLook(e.localPosition, size),
                  onPointerMove: (e) => _updateLook(e.localPosition, size),
                  onPointerUp: (_) => _releaseLook(),
                  onPointerCancel: (_) => _releaseLook(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _poke,
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _repaint,
                        builder: (_, __) => CustomPaint(
                          painter: _painter(stageIndex, allDone),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Tap your creature',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${s.stage.emoji} ${s.stage.name}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
  }
}
