enum Verdict { genuine, fake, uncertain }

class ScanResult {
  final Verdict verdict;
  final double confidence;
  final int latencyMs;
  final DateTime scannedAt;
  final String? imagePath;
  final String? ocrText;
  final bool isNoveltyFlag;
  final List<double>? heatmap; // 20×20 = 400 values

  // Fused model scores
  final double? visualScore;   // raw ONNX model output [0, 1]
  final double? textureScore;  // GLCM texture genuineness [0, 1]
  final double? fusedScore;    // weighted combination [0, 1]
  final Map<String, double>? glcmFeatures; // 6 Haralick features

  ScanResult({
    required this.verdict,
    required this.confidence,
    required this.latencyMs,
    required this.scannedAt,
    this.imagePath,
    this.ocrText,
    this.isNoveltyFlag = false,
    this.heatmap,
    this.visualScore,
    this.textureScore,
    this.fusedScore,
    this.glcmFeatures,
  });

  String get verdictLabel {
    switch (verdict) {
      case Verdict.genuine: return 'Genuine';
      case Verdict.fake:    return 'Fake';
      case Verdict.uncertain: return 'Uncertain';
    }
  }

  String get verdictEmoji {
    switch (verdict) {
      case Verdict.genuine: return '✅';
      case Verdict.fake:    return '❌';
      case Verdict.uncertain: return '⚠️';
    }
  }

  Map<String, dynamic> toMap() => {
    'verdict': verdict.name,
    'confidence': confidence,
    'latencyMs': latencyMs,
    'scannedAt': scannedAt.toIso8601String(),
    'imagePath': imagePath,
    'ocrText': ocrText,
    'isNoveltyFlag': isNoveltyFlag,
    'visualScore': visualScore,
    'textureScore': textureScore,
    'fusedScore': fusedScore,
    'glcmFeatures': glcmFeatures,
  };

  factory ScanResult.fromMap(Map<String, dynamic> map) => ScanResult(
    verdict: Verdict.values.firstWhere((v) => v.name == map['verdict']),
    confidence: (map['confidence'] as num).toDouble(),
    latencyMs: map['latencyMs'],
    scannedAt: DateTime.parse(map['scannedAt']),
    imagePath: map['imagePath'],
    ocrText: map['ocrText'],
    isNoveltyFlag: map['isNoveltyFlag'] ?? false,
    visualScore: (map['visualScore'] as num?)?.toDouble(),
    textureScore: (map['textureScore'] as num?)?.toDouble(),
    fusedScore: (map['fusedScore'] as num?)?.toDouble(),
    glcmFeatures: map['glcmFeatures'] != null
        ? (map['glcmFeatures'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble()))
        : null,
  );
}
