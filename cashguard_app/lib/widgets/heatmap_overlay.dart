import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class HeatmapOverlay extends StatelessWidget {
  final String imagePath;
  final List<double> heatmap; // 20×20 normalized values
  const HeatmapOverlay({super.key, required this.imagePath, required this.heatmap});

  // Jet colormap: blue → cyan → green → yellow → red
  Color _jetColor(double t) {
    t = t.clamp(0.0, 1.0);
    double r, g, b;
    if (t < 0.25) {
      r = 0; g = t * 4; b = 1;
    } else if (t < 0.5) {
      r = 0; g = 1; b = 1 - (t - 0.25) * 4;
    } else if (t < 0.75) {
      r = (t - 0.5) * 4; g = 1; b = 0;
    } else {
      r = 1; g = 1 - (t - 0.75) * 4; b = 0;
    }
    return Color.fromARGB(
      180,
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base image
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(imagePath),
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
          ),
        ),
        // Heatmap overlay
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: 220,
            child: CustomPaint(
              painter: _HeatmapPainter(heatmap: heatmap, jetColor: _jetColor),
            ),
          ),
        ),
        // Legend
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Low', style: TextStyle(color: Colors.white54, fontSize: 10)),
                const SizedBox(width: 4),
                Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0000FF), Color(0xFF00FFFF), Color(0xFF00FF00), Color(0xFFFFFF00), Color(0xFFFF0000)],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('High', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<double> heatmap;
  final Color Function(double) jetColor;
  const _HeatmapPainter({required this.heatmap, required this.jetColor});

  @override
  void paint(Canvas canvas, Size size) {
    const gridSize = 20;
    final cellW = size.width / gridSize;
    final cellH = size.height / gridSize;

    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        final val = heatmap[y * gridSize + x];
        final color = jetColor(val);
        final paint = Paint()..color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
