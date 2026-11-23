import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Flies a glowing orb from [from] (a screen position, usually the task you
/// just checked) to the Creature tab in the bottom bar, then bursts there.
void flyEnergyOrb(BuildContext context, {required Offset from, Offset? to}) {
  final media = MediaQuery.of(context);
  if (media.disableAnimations) {
    HapticFeedback.lightImpact();
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // The Creature tab is the 2nd of the 4 equal bottom-bar items, so its
  // centre sits 3/8 of the way across the screen.
  final target = to ??
      Offset(media.size.width * 3 / 8,
          media.size.height - media.viewPadding.bottom - 52);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(
        child: _OrbFlight(
          from: from,
          to: target,
          onDone: () {
            entry.remove();
            HapticFeedback.lightImpact();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _OrbFlight extends StatefulWidget {
  final Offset from;
  final Offset to;
  final VoidCallback onDone;
  const _OrbFlight(
      {required this.from, required this.to, required this.onDone});

  @override
  State<_OrbFlight> createState() => _OrbFlightState();
}

class _OrbFlightState extends State<_OrbFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.infinite,
        painter: _OrbPainter(from: widget.from, to: widget.to, t: _c.value),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double t; // 0..1 over the whole animation

  _OrbPainter({required this.from, required this.to, required this.t});

  static const _flightEnd = 0.8;

  Offset _pos(double k) {
    final eased = Curves.easeInOutCubic.transform(k.clamp(0.0, 1.0).toDouble());
    final control = Offset(
      (from.dx + to.dx) / 2,
      math.min(from.dy, to.dy) - 140,
    );
    final a = (1 - eased) * (1 - eased);
    final b = 2 * (1 - eased) * eased;
    final c = eased * eased;
    return Offset(
      a * from.dx + b * control.dx + c * to.dx,
      a * from.dy + b * control.dy + c * to.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    const teal = Color(0xFF64FFDA);

    if (t < _flightEnd) {
      final p = t / _flightEnd;

      // fading trail
      for (var i = 7; i >= 1; i--) {
        final k = p - i * 0.035;
        if (k <= 0) continue;
        final fade = 1 - i / 8;
        canvas.drawCircle(
          _pos(k),
          10 * fade + 2,
          Paint()..color = teal.withOpacity(0.35 * fade),
        );
      }

      final head = _pos(p);
      final radius = 12 * (1 - 0.35 * p);
      canvas.drawCircle(
        head,
        radius * 2.1,
        Paint()
          ..color = teal.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(head, radius, Paint()..color = Colors.white);
      canvas.drawCircle(head, radius * 0.65, Paint()..color = teal);
    } else {
      // arrival: expanding ring and a few sparks
      final q = (t - _flightEnd) / (1 - _flightEnd);
      canvas.drawCircle(
        to,
        14 + 36 * q,
        Paint()
          ..color = teal.withOpacity(0.9 * (1 - q))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final d = 10 + 40 * Curves.easeOut.transform(q);
        canvas.drawCircle(
          to + Offset(math.cos(angle) * d, math.sin(angle) * d),
          3 * (1 - q),
          Paint()..color = Colors.white.withOpacity(1 - q),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
