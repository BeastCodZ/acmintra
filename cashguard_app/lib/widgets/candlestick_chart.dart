import 'package:flutter/material.dart';
import '../models/asset.dart';

const _green = Color(0xFF7BC950);
const _red = Color(0xFFFF4D2E);

/// Candlestick chart matching the investment template.
/// Optionally shows a price marker bubble + vertical guide line at [markerIndex].
class CandlestickChart extends StatelessWidget {
  final List<Candle> candles;
  final double height;
  final int? markerIndex;        // which candle gets the "$180" bubble
  final String? markerLabel;     // text in the bubble
  final bool showGrid;
  final List<String>? xLabels;   // optional time labels under the chart

  const CandlestickChart({
    super.key,
    required this.candles,
    this.height = 200,
    this.markerIndex,
    this.markerLabel,
    this.showGrid = false,
    this.xLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _CandlePainter(
              candles: candles,
              markerIndex: markerIndex,
              markerLabel: markerLabel,
              showGrid: showGrid,
            ),
          ),
        ),
        if (xLabels != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: xLabels!
                .map((l) => Text(l,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 11)))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  final int? markerIndex;
  final String? markerLabel;
  final bool showGrid;

  _CandlePainter({
    required this.candles,
    this.markerIndex,
    this.markerLabel,
    this.showGrid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    // Vertical headroom so the marker bubble has space at the top.
    final topPad = markerIndex != null ? 28.0 : 6.0;
    const botPad = 6.0;
    final chartH = size.height - topPad - botPad;

    double maxP = candles.first.high;
    double minP = candles.first.low;
    for (final c in candles) {
      if (c.high > maxP) maxP = c.high;
      if (c.low < minP) minP = c.low;
    }
    final range = (maxP - minP) == 0 ? 1 : (maxP - minP);

    double y(double price) => topPad + (maxP - price) / range * chartH;

    // ── Dashed horizontal grid lines ──────────────────────────────────────
    if (showGrid) {
      final gridPaint = Paint()
        ..color = const Color(0xFF2A2A2C)
        ..strokeWidth = 1;
      for (int i = 0; i <= 4; i++) {
        final gy = topPad + chartH * i / 4;
        _dashedLine(canvas, Offset(0, gy), Offset(size.width, gy), gridPaint);
      }
    }

    final slot = size.width / candles.length;
    final bodyW = slot * 0.55;

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = slot * i + slot / 2;
      final color = c.up ? _green : _red;

      final wick = Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx, y(c.high)), Offset(cx, y(c.low)), wick);

      // Body
      final top = y(c.up ? c.close : c.open);
      final bot = y(c.up ? c.open : c.close);
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2, (bot - top).abs() < 1.5 ? top + 1.5 : bot),
        const Radius.circular(2),
      );
      canvas.drawRRect(bodyRect, Paint()..color = color);
    }

    // ── Price marker bubble + guide line ──────────────────────────────────
    if (markerIndex != null && markerLabel != null &&
        markerIndex! >= 0 && markerIndex! < candles.length) {
      final cx = slot * markerIndex! + slot / 2;
      final markY = y(candles[markerIndex!].high);

      // Vertical dotted guide
      final guide = Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..strokeWidth = 1;
      _dashedLine(canvas, Offset(cx, markY), Offset(cx, size.height - botPad), guide,
          dash: 3, gap: 3);

      // Bubble
      final tp = TextPainter(
        text: TextSpan(
            text: markerLabel,
            style: const TextStyle(
                color: Color(0xFF0D0D0F),
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();

      final bw = tp.width + 18;
      const bh = 24.0;
      double bx = cx - bw / 2;
      bx = bx.clamp(0.0, size.width - bw);
      final by = markY - bh - 6;
      final bubble = RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, by < 0 ? 0 : by, bw, bh),
          const Radius.circular(12));
      canvas.drawRRect(bubble, Paint()..color = Colors.white);
      tp.paint(canvas, Offset(bx + 9, (by < 0 ? 0 : by) + (bh - tp.height) / 2));

      // Dot on the candle
      canvas.drawCircle(Offset(cx, markY), 3.5, Paint()..color = Colors.white);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 4, double gap = 4}) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    double drawn = 0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dash).clamp(0, total).toDouble();
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles || old.markerIndex != markerIndex;
}
