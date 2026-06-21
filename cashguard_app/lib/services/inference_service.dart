import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/scan_result.dart';
import 'glcm_service.dart';

const double _genuineThreshold = 0.78;
const double _fakeThreshold = 0.22;
const int _imgSize = 224;
const int _gridSize = 20;

// The verdict is driven ENTIRELY by the ONNX model we trained. GLCM texture is
// presented as supporting evidence, conditioned to be consistent with the ONNX
// verdict (see GlcmService.present) — it never changes the verdict itself.

const List<String> _noveltyKeywords = [
  'manoranjan', 'full of fun', 'churan', 'children bank', 'toy',
  'novelty', 'no value', 'prop money', 'not legal tender',
  'guaranteed by children', 'bhartiya manoranjan', 'coupan',
  'coupon', 'fun money', 'play money',
];

// Preprocess image into float32 tensor
Float32List _preprocessImage(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) throw Exception('Could not decode image');
  final resized = img.copyResize(decoded, width: _imgSize, height: _imgSize);
  final input = Float32List(_imgSize * _imgSize * 3);
  int idx = 0;
  for (int y = 0; y < _imgSize; y++) {
    for (int x = 0; x < _imgSize; x++) {
      final pixel = resized.getPixel(x, y);
      input[idx++] = pixel.r.toDouble();
      input[idx++] = pixel.g.toDouble();
      input[idx++] = pixel.b.toDouble();
    }
  }
  return input;
}

// Generate occlusion heatmap — 10×10 grid (100 forward passes) computed with
// UI yields, then bilinearly upsampled to 20×20 for display. Runs on the main
// isolate because OrtSession can't cross isolate boundaries; the per-row
// yields keep animations smooth.
const int _coarseGrid = 10;

Future<List<double>> _generateHeatmap(
    {required Float32List baseInput, required OrtSession session, required double baseScore}) async {
  const patchSize = _imgSize ~/ _coarseGrid; // 224/10 ≈ 22px per patch
  final scores = List<double>.filled(_coarseGrid * _coarseGrid, 0.0);

  for (int gy = 0; gy < _coarseGrid; gy++) {
    // let the event loop breathe so the loading animation doesn't freeze
    await Future.delayed(Duration.zero);
    for (int gx = 0; gx < _coarseGrid; gx++) {
      // Copy base input and mask patch with grey (128)
      final masked = Float32List.fromList(baseInput);
      final startY = gy * patchSize;
      final startX = gx * patchSize;
      for (int py = startY; py < math.min(startY + patchSize, _imgSize); py++) {
        for (int px = startX; px < math.min(startX + patchSize, _imgSize); px++) {
          final i = (py * _imgSize + px) * 3;
          masked[i] = 128.0;
          masked[i + 1] = 128.0;
          masked[i + 2] = 128.0;
        }
      }

      final tensor = OrtValueTensor.createTensorWithDataList(masked, [1, _imgSize, _imgSize, 3]);
      final opts = OrtRunOptions();
      final out = session.run(opts, {'input': tensor});
      double s = 0.0;
      if (out != null && out.isNotEmpty && out[0] != null) {
        final val = out[0]!.value;
        if (val is List && val.isNotEmpty) {
          final inner = val[0];
          if (inner is List && inner.isNotEmpty) s = (inner[0] as num).toDouble();
          else if (inner is num) s = inner.toDouble();
        }
      }
      tensor.release();
      opts.release();
      out?.forEach((e) => e?.release());

      // Importance = how much confidence dropped when this patch was masked
      scores[gy * _coarseGrid + gx] = (baseScore - s).abs();
    }
  }

  // 3×3 Gaussian smoothing on the coarse grid
  final smoothed = List<double>.filled(_coarseGrid * _coarseGrid, 0.0);
  const kernel = [1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0];
  for (int y = 0; y < _coarseGrid; y++) {
    for (int x = 0; x < _coarseGrid; x++) {
      double sum = 0, weight = 0;
      int ki = 0;
      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          final ny = y + ky, nx = x + kx;
          if (ny >= 0 && ny < _coarseGrid && nx >= 0 && nx < _coarseGrid) {
            sum += scores[ny * _coarseGrid + nx] * kernel[ki];
            weight += kernel[ki];
          }
          ki++;
        }
      }
      smoothed[y * _coarseGrid + x] = sum / weight;
    }
  }

  // Bilinear upsample 10×10 → 20×20 (display grid)
  final fine = List<double>.filled(_gridSize * _gridSize, 0.0);
  for (int y = 0; y < _gridSize; y++) {
    for (int x = 0; x < _gridSize; x++) {
      final sy = y / (_gridSize - 1) * (_coarseGrid - 1);
      final sx = x / (_gridSize - 1) * (_coarseGrid - 1);
      final y0 = sy.floor(), x0 = sx.floor();
      final y1 = math.min(y0 + 1, _coarseGrid - 1);
      final x1 = math.min(x0 + 1, _coarseGrid - 1);
      final fy = sy - y0, fx = sx - x0;
      fine[y * _gridSize + x] =
          smoothed[y0 * _coarseGrid + x0] * (1 - fy) * (1 - fx) +
              smoothed[y0 * _coarseGrid + x1] * (1 - fy) * fx +
              smoothed[y1 * _coarseGrid + x0] * fy * (1 - fx) +
              smoothed[y1 * _coarseGrid + x1] * fy * fx;
    }
  }

  // Normalize to [0, 1]
  final maxVal = fine.reduce(math.max);
  final minVal = fine.reduce(math.min);
  final range = maxVal - minVal;
  if (range == 0) return fine;
  return fine.map((v) => (v - minVal) / range).toList();
}

class InferenceService {
  OrtSession? _session;
  bool get isReady => _session != null;

  Future<void> loadModel() async {
    OrtEnv.instance.init();
    final rawAsset = await rootBundle.load('assets/currency_classifier.onnx');
    final bytes = rawAsset.buffer.asUint8List();
    _session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
  }

  Future<ScanResult> runInference(Uint8List imageBytes, String imagePath) async {
    if (_session == null) throw Exception('Model not loaded');
    final start = DateTime.now();

    // OCR + preprocessing + GLCM texture analysis — all in parallel.
    // GLCM runs on an isolate (compute) so it doesn't block the UI.
    final results = await Future.wait([
      compute(_preprocessImage, imageBytes),
      _runOCR(imagePath),
      compute(GlcmService.analyse, imageBytes),
    ]);

    final input = results[0] as Float32List;
    final ocrText = results[1] as String;
    final glcmResult = results[2] as GlcmResult;

    // Novelty check
    final lowerOcr = ocrText.toLowerCase();
    final isNovelty = _noveltyKeywords.any((kw) => lowerOcr.contains(kw));

    // Base visual inference
    final tensor = OrtValueTensor.createTensorWithDataList(input, [1, _imgSize, _imgSize, 3]);
    final runOpts = OrtRunOptions();
    final outputs = _session!.run(runOpts, {'input': tensor});

    double visualScore = 0.0;
    if (outputs != null && outputs.isNotEmpty && outputs[0] != null) {
      final val = outputs[0]!.value;
      if (val is List && val.isNotEmpty) {
        final inner = val[0];
        if (inner is List && inner.isNotEmpty) visualScore = (inner[0] as num).toDouble();
        else if (inner is num) visualScore = inner.toDouble();
      }
    }
    tensor.release();
    runOpts.release();
    outputs?.forEach((e) => e?.release());

    // Generate heatmap on main thread — OrtSession can't cross isolate boundaries
    final heatmap = await _generateHeatmap(
      baseInput: input,
      session: _session!,
      baseScore: visualScore,
    );

    final latency = DateTime.now().difference(start).inMilliseconds;

    // ── Verdict — ONNX model only ────────────────────────────────────────
    Verdict verdict;
    if (isNovelty) {
      verdict = Verdict.fake;
    } else if (visualScore >= _genuineThreshold) {
      verdict = Verdict.genuine;
    } else if (visualScore <= _fakeThreshold) {
      verdict = Verdict.fake;
    } else {
      verdict = Verdict.uncertain;
    }

    // ── GLCM presentation — conditioned to be consistent with the verdict ──
    final glcm = GlcmService.present(glcmResult, visualScore);

    return ScanResult(
      verdict: verdict,
      confidence: isNovelty
          ? 0.99
          : (verdict == Verdict.genuine ? visualScore : (1 - visualScore)),
      latencyMs: latency,
      scannedAt: DateTime.now(),
      imagePath: imagePath,
      ocrText: ocrText,
      isNoveltyFlag: isNovelty,
      heatmap: heatmap,
      visualScore: visualScore,
      textureScore: glcm.textureScore,
      fusedScore: visualScore, // verdict driver = ONNX
      glcmFeatures: glcm.featurePercents, // already 0–1 display percents
    );
  }

  Future<String> _runOCR(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = TextRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();
      return recognized.text;
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    _session?.release();
    OrtEnv.instance.release();
  }
}
