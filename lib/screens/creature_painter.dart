import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Hand-drawn creature scene, rendered entirely in code (no image assets).
///
/// The sky follows the real time of day, the creature blinks, hops when
/// tapped, follows your finger with its eyes, sleeps at night and looks
/// hungry in the evening when tasks are still open.
class CreaturePainter extends CustomPainter {
  final int stage; // 0-4
  final int energy;
  final double t; // 0..1 looping animation value (drives all motion)

  final double hour; // 0..24 local time (default 0 = night, as before)
  final double blink; // 0 open .. 1 closed
  final double hop; // 0..1 progress of a tap-hop
  final double giggle; // 0..1 progress of the hearts; 1 = finished
  final Offset look; // -1..1 where the eyes look (0,0 = default)
  final bool sleeping;
  final bool hungry;
  final double glow; // 0..1 white aura (evolution scene)
  final bool showScene; // false = draw only the creature (evolution scene)

  CreaturePainter({
    required this.stage,
    required this.energy,
    required this.t,
    this.hour = 0,
    this.blink = 0,
    this.hop = 0,
    this.giggle = 1,
    this.look = Offset.zero,
    this.sleeping = false,
    this.hungry = false,
    this.glow = 0,
    this.showScene = true,
  });

  bool get starving => energy < 15;
  bool get happy => energy >= 40;
  bool get thriving => energy >= 70;

  static double _clamp01(double v) => math.max(0.0, math.min(1.0, v));
  static double _ramp(double x, double a, double b) =>
      _clamp01((x - a) / (b - a));

  /// 0 at night, 1 in full daylight, smooth ramps at dawn and dusk.
  static double daylightFor(double hour) {
    final up = _ramp(hour, 5.5, 8.0);
    final down = 1 - _ramp(hour, 16.5, 19.0);
    return math.min(up, down);
  }

  static double _bump(double x, double center, double halfWidth) =>
      math.max(0.0, 1 - (x - center).abs() / halfWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final daylight = daylightFor(hour);

    if (showScene) _drawScene(canvas, w, h, daylight);

    final cx = w / 2;
    final bob = math.sin(t * 2 * math.pi) * (sleeping ? 3.0 : 8.0);
    final hopLift = math.sin(hop * math.pi) * h * 0.13;
    final cy = h * 0.60 + bob - hopLift;
    final breathe = 1 + 0.02 * math.sin(t * 2 * math.pi);

    // Soft shadow on the ground that shrinks while the creature hops.
    if (showScene) {
      final k = math.sin(hop * math.pi);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, h * 0.84),
            width: h * 0.32 * (1 - 0.3 * k),
            height: h * 0.035),
        Paint()..color = Colors.black.withOpacity(0.25 * (1 - 0.5 * k)),
      );
    }

    // White aura used by the evolution scene
    if (glow > 0) {
      canvas.drawCircle(
        Offset(cx, cy),
        h * (0.18 + 0.22 * glow),
        Paint()
          ..color = Colors.white.withOpacity(0.55 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
      );
    }

    // Aura when thriving
    if (thriving) {
      final aura = Paint()
        ..color = const Color(0xFF4DB6AC).withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
      canvas.drawCircle(Offset(cx, cy), h * 0.24, aura);
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(breathe);
    canvas.translate(-cx, -cy);
    switch (stage) {
      case 0:
        _egg(canvas, cx, cy, h);
        break;
      case 1:
        _hatch(canvas, cx, cy, h);
        break;
      case 2:
        _fledgling(canvas, cx, cy, h);
        break;
      case 3:
        _soaring(canvas, cx, cy, h);
        break;
      default:
        _dragon(canvas, cx, cy, h);
    }
    canvas.restore();

    _drawHearts(canvas, cx, cy, h);
    if (sleeping) _drawZzz(canvas, cx, cy, h);
    if (hungry && !sleeping) _drawHungryBubble(canvas, cx, cy, h);
  }

  // ---------------------------------------------------------------- scene

  void _drawScene(Canvas canvas, double w, double h, double daylight) {
    final e = (energy / 100).clamp(0.0, 1.0).toDouble();

    final nightTop = starving
        ? const Color(0xFF241E33)
        : Color.lerp(const Color(0xFF1B3A5B), const Color(0xFF0A2E2E), e)!;
    final dayTop = starving
        ? const Color(0xFF4F4A66)
        : Color.lerp(const Color(0xFF3D7CA8), const Color(0xFF3A9C94), e)!;
    final nightBottom =
        thriving ? const Color(0xFF1E5F52) : const Color(0xFF11453F);
    final dayBottom =
        thriving ? const Color(0xFF4DB39C) : const Color(0xFF2E8576);

    // Warm tint around sunrise (6:30) and sunset (18:30)
    final golden =
        math.max(_bump(hour, 6.5, 1.5), _bump(hour, 18.5, 1.5)) * 0.35;
    final warm = const Color(0xFFD98A5B);

    final top = Color.lerp(
        Color.lerp(nightTop, dayTop, daylight)!, warm, golden)!;
    final bottom = Color.lerp(
        Color.lerp(nightBottom, dayBottom, daylight)!, warm, golden * 0.4)!;

    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sky);

    final night = 1 - daylight;

    // Drifting aurora bands (decent energy, mostly at night)
    if (energy >= 40 && night > 0.3) {
      final band = Paint()
        ..color = const Color(0xFF4DB6AC)
            .withOpacity((0.07 + 0.05 * energy / 100) * night)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      for (var i = 0; i < 3; i++) {
        final yBase = h * (0.12 + i * 0.10);
        final drift = math.sin((t + i * 0.33) * 2 * math.pi) * w * 0.15;
        final path = Path()
          ..moveTo(-w * 0.2 + drift, yBase + h * 0.05)
          ..quadraticBezierTo(
              w * 0.3 + drift, yBase - h * 0.08, w * 0.7 + drift, yBase)
          ..quadraticBezierTo(w * 1.0 + drift, yBase + h * 0.06,
              w * 1.3 + drift, yBase - h * 0.03)
          ..lineTo(w * 1.3 + drift, yBase + h * 0.25)
          ..quadraticBezierTo(w * 0.6 + drift, yBase + h * 0.35,
              -w * 0.2 + drift, yBase + h * 0.22)
          ..close();
        canvas.drawPath(path, band);
      }
    }

    // Twinkling stars (fade out in daylight, freeze out when starving)
    final rnd = math.Random(42);
    final starBase = (starving ? 0.12 : 0.5) * night;
    if (starBase > 0.01) {
      for (var i = 0; i < 30; i++) {
        final sx = rnd.nextDouble() * w;
        final sy = rnd.nextDouble() * h * 0.5;
        final phase = rnd.nextDouble();
        final tw = 0.5 + 0.5 * math.sin((t * 2 + phase) * 2 * math.pi);
        final star = Paint()
          ..color = Colors.white.withOpacity(starBase * (0.35 + 0.65 * tw));
        canvas.drawCircle(Offset(sx, sy), 0.9 + rnd.nextDouble() * 1.2, star);
      }
    }

    // Shooting star at night when thriving
    if (thriving && night > 0.5 && (t % 1.0) < 0.12) {
      final k = (t % 1.0) / 0.12;
      final sx = w * (1.1 - k * 0.9);
      final sy = h * (0.08 + k * 0.15);
      final streak = Paint()
        ..color = Colors.white.withOpacity(0.8 * (1 - k))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(sx + 30, sy - 8), Offset(sx, sy), streak);
      canvas.drawCircle(Offset(sx, sy), 2.2,
          Paint()..color = Colors.white.withOpacity(1 - k));
    }

    // Sun by day, moon by night, both travelling along an arc
    final isDay = hour >= 6 && hour < 18;
    final hh = isDay ? hour - 6 : (hour >= 18 ? hour - 18 : hour + 6);
    final p = _clamp01(hh / 12);
    final bx = w * (0.12 + 0.76 * p);
    final by = h * (0.34 - 0.24 * math.sin(p * math.pi)) +
        math.sin(t * 2 * math.pi) * 3;
    if (isDay) {
      canvas.drawCircle(
          Offset(bx, by),
          h * 0.075,
          Paint()
            ..color = const Color(0xFFFFE082).withOpacity(0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      canvas.drawCircle(
          Offset(bx, by), h * 0.045, Paint()..color = const Color(0xFFFFE082));
    } else {
      canvas.drawCircle(Offset(bx, by), h * 0.045,
          Paint()..color = const Color(0xFFF5F3CE));
      canvas.drawCircle(Offset(bx - h * 0.02, by - h * 0.01), h * 0.04,
          Paint()..color = top);
    }

    // Floating clouds (more visible by day)
    final cloud = Paint()
      ..color = Colors.white.withOpacity(0.05 + 0.13 * daylight);
    for (var i = 0; i < 3; i++) {
      final cx = ((t * (0.04 + i * 0.02) + i * 0.37) % 1.3 - 0.15) * w;
      final cy = h * (0.18 + i * 0.12);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy), width: w * 0.3, height: h * 0.05),
          cloud);
    }

    // Ground
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w / 2, h * 0.96), width: w * 1.5, height: h * 0.32),
      Paint()
        ..color = Color.lerp(
            const Color(0xFF1B3527), const Color(0xFF2C5B3E), daylight)!,
    );
  }

  // ------------------------------------------------------------ overlays

  void _drawText(Canvas c, String s, Offset center, double size, double opacity,
      {FontWeight weight = FontWeight.normal, Color color = Colors.white}) {
    if (opacity <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final off = center - Offset(tp.width / 2, tp.height / 2);
    if (opacity >= 0.99) {
      tp.paint(c, off);
      return;
    }
    c.saveLayer(
      Rect.fromLTWH(off.dx - 4, off.dy - 4, tp.width + 8, tp.height + 8),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    tp.paint(c, off);
    c.restore();
  }

  void _drawHearts(Canvas c, double cx, double cy, double h) {
    if (giggle >= 1.0) return;
    final rnd = math.Random(5);
    for (var i = 0; i < 5; i++) {
      final dx = (rnd.nextDouble() - 0.5) * h * 0.45;
      final size = 14 + rnd.nextDouble() * 8;
      final delay = i * 0.08;
      final k = _clamp01((giggle - delay) / (1 - delay));
      if (k <= 0) continue;
      final y = cy - h * 0.2 - k * h * 0.22;
      _drawText(c, '❤️', Offset(cx + dx, y), size, 1 - k);
    }
  }

  void _drawZzz(Canvas c, double cx, double cy, double h) {
    for (var i = 0; i < 3; i++) {
      final phase = (t * 2 + i / 3.0) % 1.0;
      final up = phase * h * 0.12;
      final opacity = math.sin(phase * math.pi);
      _drawText(
        c,
        i == 2 ? 'Z' : 'z',
        Offset(cx + h * 0.13 + i * 8, cy - h * 0.16 - up),
        12.0 + i * 4,
        opacity,
        weight: FontWeight.bold,
        color: Colors.white70,
      );
    }
  }

  void _drawHungryBubble(Canvas c, double cx, double cy, double h) {
    final pulse = 0.65 + 0.35 * math.sin(t * 4 * math.pi);
    final center = Offset(cx + h * 0.17, cy - h * 0.22);
    c.drawCircle(center, 18, Paint()..color = Colors.white.withOpacity(0.16));
    _drawText(c, '🍽️', center, 18, pulse);
  }

  // ----------------------------------------------------------- creatures

  void _egg(Canvas c, double cx, double cy, double h) {
    final r = h * 0.14;
    c.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + r * 0.2), width: r * 1.6, height: r * 2.2),
      Paint()..color = const Color(0xFFF1E4C3),
    );
    final spot = Paint()..color = const Color(0xFF7FB3A3);
    c.drawCircle(Offset(cx - r * 0.4, cy - r * 0.3), r * 0.18, spot);
    c.drawCircle(Offset(cx + r * 0.45, cy + r * 0.15), r * 0.14, spot);
    c.drawCircle(Offset(cx - r * 0.1, cy + r * 0.65), r * 0.12, spot);
    if (starving) {
      final crack = Paint()
        ..color = const Color(0xFF4A3F2A)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final p = Path()
        ..moveTo(cx - r * 0.5, cy)
        ..lineTo(cx - r * 0.2, cy + r * 0.25)
        ..lineTo(cx + r * 0.1, cy - r * 0.05)
        ..lineTo(cx + r * 0.5, cy + r * 0.3);
      c.drawPath(p, crack);
    }
  }

  void _hatch(Canvas c, double cx, double cy, double h) {
    final r = h * 0.10;
    c.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 0, math.pi,
        true, Paint()..color = Colors.white);
    c.drawCircle(Offset(cx, cy - r * 0.15), r * 0.9,
        Paint()..color = const Color(0xFFF7D774));
    final beak = Path()
      ..moveTo(cx - r * 0.1, cy - r * 0.25)
      ..lineTo(cx + r * 0.28, cy - r * 0.12)
      ..lineTo(cx - r * 0.1, cy)
      ..close();
    c.drawPath(beak, Paint()..color = const Color(0xFFF5A13D));
    _eyes(c, cx - r * 0.32, cy - r * 0.35, r * 0.5);
  }

  void _fledgling(Canvas c, double cx, double cy, double h) {
    final r = h * 0.12;
    final wing = Paint()..color = const Color(0xFFE09B2D);
    // gentle wing flap (a happy hop flaps harder)
    final flap = math.sin(t * 2 * math.pi) * 0.18 +
        math.sin(hop * math.pi) * 0.5;
    for (final s in [-1.0, 1.0]) {
      c.save();
      c.translate(cx + s * r * 0.85, cy);
      c.rotate(s * (0.55 + flap));
      c.drawOval(
        Rect.fromCenter(
            center: Offset(s * r * 0.4, 0), width: r * 0.95, height: r * 0.5),
        wing,
      );
      c.restore();
    }
    final tail = Path()
      ..moveTo(cx - r * 0.95, cy + r * 0.25)
      ..lineTo(cx - r * 1.4, cy + r * 0.75)
      ..lineTo(cx - r * 0.75, cy + r * 0.65)
      ..close();
    c.drawPath(tail, wing);
    final leg = Paint()
      ..color = const Color(0xFFD98E2B)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(cx - r * 0.25, cy + r * 0.9),
        Offset(cx - r * 0.25, cy + r * 1.3), leg);
    c.drawLine(Offset(cx + r * 0.25, cy + r * 0.9),
        Offset(cx + r * 0.25, cy + r * 1.3), leg);
    c.drawCircle(
        Offset(cx, cy), r, Paint()..color = const Color(0xFFF5B94A));
    _eyes(c, cx, cy - r * 0.15, r);
  }

  void _soaring(Canvas c, double cx, double cy, double h) {
    final r = h * 0.11;
    final wingP = Paint()..color = const Color(0xFF5FB3AD);
    final flap = math.sin(t * 2 * math.pi) * 0.22 +
        math.sin(hop * math.pi) * 0.5;
    for (final s in [-1.0, 1.0]) {
      final lift = s * flap * r;
      final p = Path()
        ..moveTo(cx + s * r * 0.4, cy)
        ..quadraticBezierTo(cx + s * r * 1.8, cy - r * 1.5 + lift,
            cx + s * r * 2.4, cy - r * 0.4 + lift)
        ..quadraticBezierTo(
            cx + s * r * 1.4, cy - r * 0.2, cx + s * r * 0.6, cy + r * 0.35)
        ..close();
      c.drawPath(p, wingP);
    }
    final body = Paint()..color = const Color(0xFF7EC8C3);
    c.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 1.9, height: r * 1.1),
        body);
    c.drawCircle(Offset(cx + r * 0.85, cy - r * 0.45), r * 0.5, body);
    final beak = Path()
      ..moveTo(cx + r * 1.3, cy - r * 0.55)
      ..lineTo(cx + r * 1.78, cy - r * 0.15)
      ..lineTo(cx + r * 1.28, cy - r * 0.15)
      ..close();
    c.drawPath(beak, Paint()..color = const Color(0xFFF5B94A));
    _eyes(c, cx + r * 0.85, cy - r * 0.55, r * 0.5);
  }

  void _dragon(Canvas c, double cx, double cy, double h) {
    final r = h * 0.13;
    final body = Paint()..color = const Color(0xFF9B7ED9);
    final tail = Path()
      ..moveTo(cx - r * 0.9, cy + r * 0.3)
      ..quadraticBezierTo(
          cx - r * 2.1, cy + r * 0.9, cx - r * 2.0, cy - r * 0.1)
      ..lineTo(cx - r * 1.85, cy + r * 0.15)
      ..quadraticBezierTo(
          cx - r * 1.6, cy + r * 0.55, cx - r * 0.75, cy - r * 0.05)
      ..close();
    c.drawPath(tail, body);
    final wingP = Paint()..color = const Color(0xFF7A5FC0);
    final flap = math.sin(t * 2 * math.pi) * 0.16 +
        math.sin(hop * math.pi) * 0.5;
    for (final s in [-1.0, 1.0]) {
      final lift = s * flap * r;
      final p = Path()
        ..moveTo(cx + s * r * 0.3, cy - r * 0.4)
        ..quadraticBezierTo(cx + s * r * 1.9, cy - r * 2.0 + lift,
            cx + s * r * 2.3, cy - r * 0.6 + lift)
        ..quadraticBezierTo(cx + s * r * 1.7, cy - r * 0.7, cx + s * r * 1.5,
            cy + r * 0.1)
        ..quadraticBezierTo(cx + s * r * 1.1, cy - r * 0.2, cx + s * r * 0.8,
            cy + r * 0.25)
        ..close();
      c.drawPath(p, wingP);
    }
    c.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy + r * 0.1), width: r * 1.9, height: r * 1.5),
        body);
    c.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy + r * 0.35),
            width: r * 1.0,
            height: r * 0.9),
        Paint()..color = const Color(0xFFBCA6E8));
    c.drawCircle(Offset(cx + r * 0.7, cy - r * 0.75), r * 0.55, body);
    final horn = Paint()..color = const Color(0xFFE8D44D);
    for (final s in [-1.0, 1.0]) {
      final p = Path()
        ..moveTo(cx + r * 0.7 + s * r * 0.18, cy - r * 1.25)
        ..lineTo(cx + r * 0.7 + s * r * 0.42, cy - r * 1.78)
        ..lineTo(cx + r * 0.7 + s * r * 0.5, cy - r * 1.2)
        ..close();
      c.drawPath(p, horn);
    }
    _eyes(c, cx + r * 0.7, cy - r * 0.85, r * 0.55);
    if (thriving && !sleeping) {
      final flicker = 1 + 0.15 * math.sin(t * 6 * math.pi);
      c.drawCircle(Offset(cx + r * 1.4, cy - r * 0.6), r * 0.28 * flicker,
          Paint()..color = const Color(0xFFFF9D2E).withOpacity(0.85));
      c.drawCircle(Offset(cx + r * 1.4, cy - r * 0.6), r * 0.15 * flicker,
          Paint()..color = const Color(0xFFFFD54F));
    }
  }

  void _eyes(Canvas c, double cx, double cy, double r) {
    final dark = Paint()
      ..color = const Color(0xFF2B2B2B)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    if (starving) {
      for (final s in [-1.0, 1.0]) {
        final ex = cx + s * r * 0.38;
        c.drawLine(Offset(ex - 3, cy - 3), Offset(ex + 3, cy + 3), dark);
        c.drawLine(Offset(ex - 3, cy + 3), Offset(ex + 3, cy - 3), dark);
      }
      return;
    }

    // Asleep, or mid-blink: closed, smiling eyes
    if (sleeping || blink > 0.85) {
      final closed = Paint()
        ..color = const Color(0xFF2B2B2B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (final s in [-1.0, 1.0]) {
        final ex = cx + s * r * 0.38;
        c.drawArc(
          Rect.fromCenter(
              center: Offset(ex, cy), width: r * 0.42, height: r * 0.3),
          0.15,
          math.pi - 0.3,
          false,
          closed,
        );
      }
      return;
    }

    final white = Paint()..color = Colors.white;
    final pupil = Paint()..color = const Color(0xFF22313A);
    final er = r * 0.2; // eye radius
    final open = math.max(0.15, 1 - blink);

    final looking = look.distance > 0.05;
    final baseDx = happy ? 1.0 : -1.0;
    final baseDy = hungry ? 2.4 : (happy ? -0.5 : 1.2);
    final pdx = looking ? look.dx * er * 0.45 : baseDx;
    final pdy = looking ? look.dy * er * 0.45 : baseDy;

    for (final s in [-1.0, 1.0]) {
      final ex = cx + s * r * 0.38;
      c.drawOval(
        Rect.fromCenter(
            center: Offset(ex, cy), width: er * 2, height: er * 2 * open),
        white,
      );
      if (open > 0.4) {
        c.drawCircle(Offset(ex + pdx, cy + pdy * open), r * 0.1, pupil);
      }
    }
  }

  @override
  bool shouldRepaint(CreaturePainter oldDelegate) => true;
}
