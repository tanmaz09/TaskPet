import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/creature_painter.dart';

/// Full-screen evolution scene: the old creature shakes and glows, a white
/// flash hides the swap, then the new form bursts in with particles.
Future<void> showEvolution(
  BuildContext context, {
  required int fromStage,
  required int toStage,
  required String emoji,
  required String name,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, a, b) => _EvolutionScene(
      fromStage: fromStage,
      toStage: toStage,
      emoji: emoji,
      name: name,
    ),
    transitionBuilder: (ctx, anim, secondary, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _EvolutionScene extends StatefulWidget {
  final int fromStage;
  final int toStage;
  final String emoji;
  final String name;
  const _EvolutionScene({
    required this.fromStage,
    required this.toStage,
    required this.emoji,
    required this.name,
  });

  @override
  State<_EvolutionScene> createState() => _EvolutionSceneState();
}

class _EvolutionSceneState extends State<_EvolutionScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;
  bool _buzzed = false;

  // Timeline (fractions of the controller)
  static const _flashStart = 0.38;
  static const _swap = 0.44;
  static const _flashEnd = 0.56;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..addListener(() {
        if (!_buzzed && _c.value >= _swap) {
          _buzzed = true;
          HapticFeedback.heavyImpact();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _ramp(double x, double a, double b) =>
      math.max(0.0, math.min(1.0, (x - a) / (b - a)));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final done = _c.isCompleted;
        final swapped = t >= _swap;

        // White flash: ramps up before the swap, fades after.
        final flash = t < _swap
            ? _ramp(t, _flashStart, _swap)
            : 1 - _ramp(t, _swap, _flashEnd);

        final glow = t < _swap
            ? _ramp(t, 0, _flashStart)
            : 1 - 0.75 * _ramp(t, 0.46, 0.8);

        // Shake while charging, elastic pop-in after the swap.
        final shake =
            t < _flashStart ? math.sin(t * 90) * 5 * _ramp(t, 0.05, 0.3) : 0.0;
        final scale = swapped
            ? 0.6 + 0.4 * Curves.elasticOut.transform(_ramp(t, 0.46, 0.8))
            : 1.0 + 0.12 * _ramp(t, 0.1, _flashStart);

        final chargeText =
            _ramp(t, 0.05, 0.2) * (1 - _ramp(t, 0.30, 0.42));
        final reveal = _ramp(t, 0.62, 0.78);

        return PopScope(
          canPop: done,
          child: Material(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // pulsing backdrop
                Opacity(
                  opacity: 0.35 + 0.65 * glow,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF14504A), Colors.black],
                        radius: 0.9,
                      ),
                    ),
                  ),
                ),
                // sparkles converge, then burst
                CustomPaint(
                  painter: _SparklePainter(t: t, swapAt: _swap),
                ),
                // the creature
                Center(
                  child: Transform.translate(
                    offset: Offset(shake, -30),
                    child: Transform.scale(
                      scale: scale,
                      child: SizedBox(
                        width: 300,
                        height: 340,
                        child: CustomPaint(
                          painter: CreaturePainter(
                            stage: swapped ? widget.toStage : widget.fromStage,
                            energy: 100,
                            t: (t * 4) % 1.0,
                            glow: glow,
                            showScene: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // flash
                IgnorePointer(
                  child: Opacity(
                    opacity: flash,
                    child: Container(color: Colors.white),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 56),
                      Opacity(
                        opacity: chargeText,
                        child: const Text(
                          'Something is happening…',
                          style: TextStyle(fontSize: 20, color: Colors.white70),
                        ),
                      ),
                      const Spacer(),
                      Opacity(
                        opacity: reveal,
                        child: const Text(
                          'EVOLVED!',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            color: Color(0xFF64FFDA),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: reveal,
                        child: Text(
                          '${widget.emoji} ${widget.name}',
                          style: const TextStyle(
                              fontSize: 24, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: done ? 1 : 0,
                        child: FilledButton(
                          onPressed:
                              done ? () => Navigator.of(context).pop() : null,
                          child: const Text('Amazing!'),
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dots that rush inward while the creature charges, then explode outward
/// once it evolves.
class _SparklePainter extends CustomPainter {
  final double t;
  final double swapAt;
  _SparklePainter({required this.t, required this.swapAt});

  static const _colors = [
    Color(0xFF64FFDA),
    Color(0xFFFFD54F),
    Colors.white,
    Color(0xFFB39DDB),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(const Offset(0, -10));
    final rnd = math.Random(7);

    if (t < swapAt) {
      final p = math.max(0.0, math.min(1.0, t / swapAt));
      for (var i = 0; i < 24; i++) {
        final angle = rnd.nextDouble() * math.pi * 2;
        final start = 160 + rnd.nextDouble() * 140;
        final d = start * (1 - Curves.easeIn.transform(p)) + 12;
        canvas.drawCircle(
          center + Offset(math.cos(angle) * d, math.sin(angle) * d),
          2 + rnd.nextDouble() * 2.5,
          Paint()
            ..color = _colors[i % _colors.length].withOpacity(0.2 + 0.6 * p),
        );
      }
    } else {
      final p = math.max(0.0, math.min(1.0, (t - swapAt) / (1 - swapAt)));
      for (var i = 0; i < 36; i++) {
        final angle = i * math.pi * 2 / 36 + rnd.nextDouble() * 0.3;
        final speed = 90 + rnd.nextDouble() * 170;
        final d = speed * Curves.easeOutCubic.transform(p);
        canvas.drawCircle(
          center + Offset(math.cos(angle) * d, math.sin(angle) * d),
          (3 + rnd.nextDouble() * 3.5) * (1 - 0.8 * p),
          Paint()
            ..color = _colors[i % _colors.length].withOpacity(1 - p),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}
