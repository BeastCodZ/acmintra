import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

// ════════════════════════════════════════════════════════════════════════
//  GAUGE RING — animated 270° arc gauge with a glowing tip + centred child
// ════════════════════════════════════════════════════════════════════════
class GaugeRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final List<Color> gradient;
  final Color track;
  final Widget? center;
  const GaugeRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 12,
    this.gradient = const [Color(0xFF3F6B33), Color(0xFF7BC950)],
    this.track = const Color(0x223F6B33),
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _GaugePainter(v, stroke, gradient, track),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double v;
  final double stroke;
  final List<Color> gradient;
  final Color track;
  _GaugePainter(this.v, this.stroke, this.gradient, this.track);

  static const _start = math.pi * 0.75; // 135°
  static const _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);

    // track
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (v <= 0) return;

    // value arc with gradient along the sweep
    final shader = SweepGradient(
      startAngle: _start,
      endAngle: _start + _sweep,
      colors: gradient,
    ).createShader(rect);
    canvas.drawArc(
      rect,
      _start,
      _sweep * v,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // glowing tip
    final tipA = _start + _sweep * v;
    final r = (size.width - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final tip = Offset(c.dx + math.cos(tipA) * r, c.dy + math.sin(tipA) * r);
    canvas.drawCircle(tip, stroke * 0.9,
        Paint()..color = gradient.last.withOpacity(0.30));
    canvas.drawCircle(tip, stroke * 0.42, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.v != v;
}

// ════════════════════════════════════════════════════════════════════════
//  TREND AREA CHART — animated smooth dual-series (income line + spend line)
// ════════════════════════════════════════════════════════════════════════
class TrendAreaChart extends StatelessWidget {
  final List<String> labels;
  final List<double> incomes;
  final List<double> spends;
  final double height;
  final Color lineColor;
  final Color spendColor;
  const TrendAreaChart({
    super.key,
    required this.labels,
    required this.incomes,
    required this.spends,
    this.height = 180,
    this.lineColor = CP.lavender,
    this.spendColor = const Color(0xFF7BC950),
  });

  @override
  Widget build(BuildContext context) {
    final n = incomes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${labels.join()}_$n'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, p, __) => CustomPaint(
              painter: _TrendPainter(incomes, spends, lineColor, spendColor, p),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(l,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CP.label(size: 10.5)),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> incomes;
  final List<double> spends;
  final Color lineColor;
  final Color spendColor;
  final double p; // 0..1 reveal
  _TrendPainter(this.incomes, this.spends, this.lineColor, this.spendColor, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final n = incomes.length;
    if (n == 0) return;

    const topPad = 14.0, botPad = 10.0, sidePad = 6.0;
    final usableH = size.height - topPad - botPad;
    final baseline = size.height - botPad;

    double maxV = 1;
    for (final v in incomes) maxV = math.max(maxV, v);
    for (final v in spends) maxV = math.max(maxV, v);

    double xAt(int i) =>
        n == 1 ? size.width / 2 : sidePad + (size.width - 2 * sidePad) * i / (n - 1);
    double yAt(double v) => baseline - (v / maxV) * usableH;

    // faint horizontal gridlines
    final grid = Paint()
      ..color = CP.stroke.withOpacity(0.6)
      ..strokeWidth = 1;
    for (int g = 0; g <= 2; g++) {
      final y = topPad + usableH * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final incomePts = [for (int i = 0; i < n; i++) Offset(xAt(i), yAt(incomes[i]))];
    final spendPts = [for (int i = 0; i < n; i++) Offset(xAt(i), yAt(spends[i]))];

    // reveal clip
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * p, size.height));

    if (n == 1) {
      _dot(canvas, incomePts.first, lineColor);
      _dot(canvas, spendPts.first, spendColor);
      canvas.restore();
      return;
    }

    // income: smooth line + gradient area fill
    final incomeLine = _smooth(incomePts);
    final fill = Path.from(incomeLine)
      ..lineTo(incomePts.last.dx, baseline)
      ..lineTo(incomePts.first.dx, baseline)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.34), lineColor.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(0, topPad, size.width, usableH)),
    );
    canvas.drawPath(
      incomeLine,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // spend: smooth line only
    canvas.drawPath(
      _smooth(spendPts),
      Paint()
        ..color = spendColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final pt in incomePts) _dot(canvas, pt, lineColor);
    for (final pt in spendPts) _dot(canvas, pt, spendColor);

    canvas.restore();
  }

  void _dot(Canvas c, Offset o, Color col) {
    c.drawCircle(o, 4.2, Paint()..color = CP.bg);
    c.drawCircle(o, 3.2, Paint()..color = col);
  }

  // Catmull-Rom → cubic smoothing
  Path _smooth(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.p != p || old.incomes != incomes || old.spends != spends;
}

// ════════════════════════════════════════════════════════════════════════
//  ANIMATED DONUT — draws on from the top with rounded segment caps
// ════════════════════════════════════════════════════════════════════════
class AnimatedDonut extends StatelessWidget {
  final List<double> values;
  final List<Color> colors;
  final double size;
  final double stroke;
  final Widget? center;
  const AnimatedDonut({
    super.key,
    required this.values,
    required this.colors,
    this.size = 150,
    this.stroke = 20,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(values.length),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, p, __) => CustomPaint(
          painter: _DonutPainter2(values, colors, stroke, p),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _DonutPainter2 extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double stroke;
  final double p;
  _DonutPainter2(this.values, this.colors, this.stroke, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);

    // faint full track
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = CP.card2
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    double start = -math.pi / 2; // top
    final reveal = 2 * math.pi * p;
    double drawn = 0;
    for (int i = 0; i < values.length; i++) {
      final full = values[i] / total * 2 * math.pi;
      final remaining = reveal - drawn;
      if (remaining <= 0) break;
      final sweep = math.min(full, remaining);
      canvas.drawArc(
        rect,
        start + 0.04,
        math.max(0, sweep - 0.08),
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      start += full;
      drawn += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter2 old) => old.p != p || old.values != values;
}
