import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// CashPilot-style staged loading screen: pulsing lavender core + rotating
/// orbit at the top, and a checklist below that ticks off each step in turn
/// (pending → spinner → green check). When the final step completes it calls
/// [onComplete] so the parent can reveal the result.
class AnalysingView extends StatefulWidget {
  final String title;
  final List<String> steps;
  final IconData icon;

  /// How long each step stays "in progress" before it's marked done.
  /// Total runtime ≈ steps.length × stepDuration + a short final pause.
  final Duration stepDuration;

  /// Called once every step has been completed.
  final VoidCallback? onComplete;

  const AnalysingView({
    super.key,
    required this.title,
    required this.steps,
    this.icon = Icons.center_focus_strong_rounded,
    this.stepDuration = const Duration(milliseconds: 700),
    this.onComplete,
  });

  @override
  State<AnalysingView> createState() => _AnalysingViewState();
}

class _AnalysingViewState extends State<AnalysingView>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  int _completed = 0; // number of steps fully done

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _runSteps();
  }

  Future<void> _runSteps() async {
    for (int i = 0; i < widget.steps.length; i++) {
      await Future.delayed(widget.stepDuration);
      if (!mounted) return;
      setState(() => _completed = i + 1);
    }
    // Let the final checkmark land before revealing the result.
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // soft glow
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    width: 150 + _pulse.value * 16,
                    height: 150 + _pulse.value * 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        CP.lavender.withOpacity(0.22),
                        CP.lavender.withOpacity(0),
                      ]),
                    ),
                  ),
                ),
                // rotating dashed orbit
                RotationTransition(
                  turns: _spin,
                  child: CustomPaint(
                    size: const Size(140, 140),
                    painter: _OrbitPainter(),
                  ),
                ),
                // counter-rotating inner arc
                RotationTransition(
                  turns: ReverseAnimation(_spin),
                  child: CustomPaint(
                    size: const Size(108, 108),
                    painter: _ArcPainter(),
                  ),
                ),
                // pulsing core
                ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.06).animate(
                      CurvedAnimation(
                          parent: _pulse, curve: Curves.easeInOut)),
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: const BoxDecoration(
                        color: CP.lavender, shape: BoxShape.circle),
                    child: Icon(widget.icon,
                        color: CP.lavenderDark, size: 34),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(widget.title, style: CP.display(size: 22)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: CP.sub, size: 12),
              const SizedBox(width: 5),
              Text('Processing on-device', style: CP.label(size: 12.5)),
            ],
          ),
          const SizedBox(height: 28),
          // staged checklist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < widget.steps.length; i++) ...[
                  _stepRow(i),
                  if (i != widget.steps.length - 1)
                    const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(int i) {
    final done = i < _completed;
    final active = i == _completed;
    final reached = done || active;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: reached ? 1 : 0.45,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: done
                ? Container(
                    decoration: const BoxDecoration(
                        color: CP.lavender, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: CP.lavenderDark, size: 15),
                  )
                : active
                    ? const Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: CP.lavender),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: CP.sub.withOpacity(0.4), width: 1.5),
                        ),
                      ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.steps[i],
              style: TextStyle(
                color: reached ? CP.text : CP.sub,
                fontSize: 14.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CP.lavender.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    // dashed circle: 18 dashes
    const dashes = 18;
    for (int i = 0; i < dashes; i++) {
      final start = i / dashes * 2 * math.pi;
      canvas.drawArc(rect, start, 0.16, false, paint);
    }
    // satellite dot
    final dotPaint = Paint()..color = CP.lime;
    canvas.drawCircle(
        Offset(size.width / 2, 2), 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CP.text.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawArc(rect, 0, 1.9, false, paint);
    canvas.drawArc(rect, math.pi, 1.2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
