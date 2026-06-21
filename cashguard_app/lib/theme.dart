import 'package:flutter/material.dart';

// ── CashPilot palette ─────────────────────────────────────────────────────
class CP {
  static const bg = Color(0xFF0D0D0F); // near-black
  static const card = Color(0xFF1A1A1C); // dark card
  static const card2 = Color(0xFF242426); // lighter card / chart bars
  static const stroke = Color(0xFF2E2E30);

  static const lime = Color(0xFFD7EBBE); // pastel green card
  static const limeDark = Color(0xFF17280F); // text on lime
  static const lavender = Color(0xFFC9A9F5); // purple accent
  static const lavenderDark = Color(0xFF241A33); // text on lavender

  static const red = Color(0xFFFF4D2E); // risk badge
  static const text = Color(0xFFF4F4F2);
  static const sub = Color(0xFF8E8E93);

  // Serif for big numbers & card titles (Georgia ships on iOS)
  static const serif = 'Georgia';

  static TextStyle display(
          {double size = 34,
          Color color = text,
          FontWeight weight = FontWeight.w500}) =>
      TextStyle(
          fontFamily: serif,
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: -0.5,
          height: 1.1);

  static TextStyle label(
          {double size = 13,
          Color color = sub,
          FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontSize: size, color: color, fontWeight: weight);
}

// ── Reusable: outlined pill chip (e.g. "Monthly ⌄", "MAX") ───────────────
class PillChip extends StatelessWidget {
  final String text;
  final bool filled;
  final IconData? trailing;
  final VoidCallback? onTap;
  const PillChip(this.text,
      {super.key, this.filled = false, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? CP.lavender : Colors.transparent,
          border: Border.all(
              color: filled ? CP.lavender : Colors.white.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: TextStyle(
                    color: filled ? CP.lavenderDark : CP.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing,
                  size: 15, color: filled ? CP.lavenderDark : CP.text),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Reusable: round outlined icon button (the "+" in the corner) ─────────
class RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const RoundIconBtn(this.icon, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Icon(icon, color: CP.text, size: 20),
      ),
    );
  }
}

// ── Risk meter: vertical coloured ticks, green → orange (CashPilot) ───────
class RiskMeter extends StatelessWidget {
  final double value; // 0..1 — how far the meter is filled
  final double height;
  const RiskMeter({super.key, required this.value, this.height = 36});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _RiskMeterPainter(value)),
    );
  }
}

class _RiskMeterPainter extends CustomPainter {
  final double value;
  _RiskMeterPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const tickW = 3.0, gap = 4.0;
    final count = (size.width / (tickW + gap)).floor();
    final lit = (count * value.clamp(0.0, 1.0)).round();
    for (int i = 0; i < count; i++) {
      final t = i / count;
      final Color color;
      if (i >= lit) {
        color = const Color(0xFF3A3A3C);
      } else if (t < 0.45) {
        color = const Color(0xFF7BC950);
      } else if (t < 0.7) {
        color = const Color(0xFFE8C547);
      } else {
        color = const Color(0xFFF2994A);
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = tickW
        ..strokeCap = StrokeCap.round;
      final x = i * (tickW + gap) + tickW / 2;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), paint);
    }
  }

  @override
  bool shouldRepaint(_RiskMeterPainter old) => old.value != value;
}

// ── Donut chart ───────────────────────────────────────────────────────────
class DonutChart extends StatelessWidget {
  final List<double> values;
  final List<Color> colors;
  final double size;
  final Widget? center;
  const DonutChart(
      {super.key,
      required this.values,
      required this.colors,
      this.size = 150,
      this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(values, colors),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter(this.values, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(11, 11, size.width - 22, size.height - 22);
    double start = -1.5708; // top
    for (int i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 6.2832;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start + 0.03, sweep - 0.06, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}

// ── Diagonal hatch pattern (chart column backgrounds) ─────────────────────
class HatchPainter extends CustomPainter {
  final Color color;
  HatchPainter({this.color = const Color(0xFF2A2A2C)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double d = -size.height; d < size.width; d += 6) {
      canvas.drawLine(
          Offset(d, size.height), Offset(d + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
