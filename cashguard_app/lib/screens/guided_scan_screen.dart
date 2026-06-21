import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';
import '../theme.dart';

class GuidedScanScreen extends StatefulWidget {
  final void Function(String imagePath) onCapture;
  const GuidedScanScreen({super.key, required this.onCapture});

  @override
  State<GuidedScanScreen> createState() => _GuidedScanScreenState();
}

class _GuidedScanScreenState extends State<GuidedScanScreen>
    with TickerProviderStateMixin {
  CameraController? _ctrl;
  bool _ready = false;
  bool _capturing = false;
  String? _error;
  FlashMode _flash = FlashMode.off;

  // Store screen metrics for crop math
  double _sw = 0, _sh = 0, _topPad = 0, _botPad = 0;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _cornerCtrl;
  late final Animation<double> _cornerAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _cornerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _cornerAnim =
        CurvedAnimation(parent: _cornerCtrl, curve: Curves.easeOutCubic);

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera');
        return;
      }
      final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      final ctrl = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      final minZoom = await ctrl.getMinZoomLevel();
      await ctrl.setZoomLevel(minZoom);
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
          _ready = true;
        });
        _cornerCtrl.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable');
    }
  }

  // Frame geometry (recalculated each build but stable)
  Rect _frameRect() {
    final frameW = _sw * 0.84;
    final frameH = frameW / 1.75;
    final usableH = _sh - _topPad - _botPad;
    final frameTop = _topPad + usableH * 0.30;
    return Rect.fromLTWH((_sw - frameW) / 2, frameTop, frameW, frameH);
  }

  Future<void> _toggleFlash() async {
    if (_ctrl == null) return;
    final next = _flash == FlashMode.off
        ? FlashMode.torch
        : _flash == FlashMode.torch
            ? FlashMode.auto
            : FlashMode.off;
    await _ctrl!.setFlashMode(next);
    HapticFeedback.selectionClick();
    setState(() => _flash = next);
  }

  Future<void> _capture() async {
    if (_capturing || _ctrl == null || !_ready) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      final xFile = await _ctrl!.takePicture();
      // Crop to the frame before sending to inference
      final croppedPath = await _cropToFrame(xFile.path);
      if (mounted) {
        Navigator.pop(context);
        widget.onCapture(croppedPath);
      }
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<String> _cropToFrame(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      // decodeImage applies EXIF rotation automatically
      final decoded = img_lib.decodeImage(bytes);
      if (decoded == null) return sourcePath;

      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();

      // How preview fills the screen (same logic as _FillPreview)
      final screenAspect = _sw / _sh;
      final imageAspect = imgW / imgH;

      double scale, xOff, yOff;
      if (screenAspect > imageAspect) {
        // Screen wider → fit width
        scale = _sw / imgW;
        xOff = 0;
        yOff = (_sh - imgH * scale) / 2;
      } else {
        // Screen taller → fit height
        scale = _sh / imgH;
        xOff = (_sw - imgW * scale) / 2;
        yOff = 0;
      }

      // Map screen frame rect → image coordinates
      final frame = _frameRect();
      final left = ((frame.left - xOff) / scale).clamp(0, imgW - 2).round();
      final top = ((frame.top - yOff) / scale).clamp(0, imgH - 2).round();
      final width =
          (frame.width / scale).clamp(1, imgW - left.toDouble()).round();
      final height =
          (frame.height / scale).clamp(1, imgH - top.toDouble()).round();

      final cropped = img_lib.copyCrop(decoded,
          x: left, y: top, width: width, height: height);

      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath)
          .writeAsBytes(img_lib.encodeJpg(cropped, quality: 95));
      return outPath;
    } catch (_) {
      return sourcePath; // fallback: send full image
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _cornerCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _sw = mq.size.width;
    _sh = mq.size.height;
    _topPad = mq.padding.top;
    _botPad = mq.padding.bottom;

    final frame = _frameRect();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Camera preview (fills full screen) ──────────────────────
            if (_ready && _ctrl != null)
              _FillPreview(controller: _ctrl!)
            else if (_error != null)
              Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.white70)))
            else
              const Center(
                  child: CircularProgressIndicator(
                      color: CP.lavender, strokeWidth: 2)),

            // ── Dim + viewfinder frame ───────────────────────────────────
            if (_ready)
              AnimatedBuilder(
                animation: Listenable.merge([_pulseAnim, _cornerAnim]),
                builder: (_, __) => CustomPaint(
                  painter: _ViewfinderPainter(
                    frameRect: frame,
                    pulse: _pulseAnim.value,
                    corners: _cornerAnim.value,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),

            // ── Top bar ──────────────────────────────────────────────────
            Positioned(
              top: _topPad + 12,
              left: 20,
              right: 20,
              child: Row(children: [
                _GlassBtn(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 17),
                ),
                const Spacer(),
                if (_ready) ...[
                  _FlashBtn(mode: _flash, onTap: _toggleFlash),
                  const SizedBox(width: 10),
                ],
                _GlassPill(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_rounded,
                        color: CP.lavender, size: 13),
                    const SizedBox(width: 6),
                    Text('On-device AI',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),

            // ── Hint above frame ─────────────────────────────────────────
            if (_ready)
              Positioned(
                top: frame.top - 36,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _cornerAnim.value,
                  duration: Duration.zero,
                  child: const Text(
                    'Place the note flat inside the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),

            // ── Shutter button ───────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: _botPad + 44,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: _capture,
                  child: AnimatedScale(
                    scale: _capturing ? 0.86 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Stack(alignment: Alignment.center, children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2.5)),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: _capturing ? 52 : 62,
                        height: _capturing ? 52 : 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                                color: CP.lavender.withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Tap to capture',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35), fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// Full-bleed camera preview — no black bars
class _FillPreview extends StatelessWidget {
  final CameraController controller;
  const _FillPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Scale so the shorter dimension fills the screen
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _GlassBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black38,
              border: Border.all(color: Colors.white24)),
          child: Center(child: child),
        ),
      );
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white24)),
        child: child,
      );
}

class _FlashBtn extends StatelessWidget {
  final FlashMode mode;
  final VoidCallback onTap;
  const _FlashBtn({required this.mode, required this.onTap});

  IconData get _icon => switch (mode) {
        FlashMode.torch => Icons.flash_on_rounded,
        FlashMode.auto  => Icons.flash_auto_rounded,
        _               => Icons.flash_off_rounded,
      };

  Color get _color => switch (mode) {
        FlashMode.torch => const Color(0xFFFFD60A), // yellow when on
        FlashMode.auto  => CP.lavender,
        _               => Colors.white,
      };

  String get _label => switch (mode) {
        FlashMode.torch => 'On',
        FlashMode.auto  => 'Auto',
        _               => 'Off',
      };

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mode == FlashMode.torch
                ? const Color(0xFFFFD60A).withOpacity(0.2)
                : Colors.black38,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: mode == FlashMode.off ? Colors.white24 : _color.withOpacity(0.6),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_icon, color: _color, size: 15),
            const SizedBox(width: 5),
            Text(_label,
                style: TextStyle(
                    color: _color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _ViewfinderPainter extends CustomPainter {
  final Rect frameRect;
  final double pulse;
  final double corners;
  const _ViewfinderPainter(
      {required this.frameRect, required this.pulse, required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(14);

    // Dim outside frame
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(frameRect, r)),
      ),
      Paint()..color = Colors.black.withOpacity(0.70),
    );

    // Pulsing glow on frame border
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, r),
      Paint()
        ..color = CP.lavender.withOpacity(0.3 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Animated corner brackets
    final len = 28.0 * corners;
    final cp = Paint()
      ..color = CP.lavender
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    void corner(Offset o, Offset h, Offset v) {
      canvas.drawLine(o, h, cp);
      canvas.drawLine(o, v, cp);
    }

    corner(frameRect.topLeft.translate(1, 1),
        frameRect.topLeft.translate(len, 1), frameRect.topLeft.translate(1, len));
    corner(frameRect.topRight.translate(-1, 1),
        frameRect.topRight.translate(-len, 1), frameRect.topRight.translate(-1, len));
    corner(frameRect.bottomLeft.translate(1, -1),
        frameRect.bottomLeft.translate(len, -1), frameRect.bottomLeft.translate(1, -len));
    corner(frameRect.bottomRight.translate(-1, -1),
        frameRect.bottomRight.translate(-len, -1), frameRect.bottomRight.translate(-1, -len));
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.pulse != pulse || old.corners != corners;
}
