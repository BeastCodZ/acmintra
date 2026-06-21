import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/scan_result.dart';
import '../widgets/heatmap_overlay.dart';

class ResultScreen extends StatelessWidget {
  final ScanResult result;
  const ResultScreen({super.key, required this.result});

  bool get _genuine => result.verdict == Verdict.genuine;

  String get _verdictMessage {
    if (result.isNoveltyFlag) {
      return 'Novelty/toy note detected via OCR — text like "Manoranjan Bank" found. This is not legal tender.';
    }
    switch (result.verdict) {
      case Verdict.genuine:
        return 'Security features match expected patterns.';
      case Verdict.fake:
        return 'This note shows signs of being counterfeit. Do not accept it.';
      case Verdict.uncertain:
        return 'The model is not confident. Try a clearer photo in better lighting.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back row ────────────────────────────────────────────────
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_back_rounded,
                            color: CP.text, size: 20),
                        const SizedBox(width: 6),
                        Text('Back',
                            style: TextStyle(
                                color: CP.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const PillChip('Scan result'),
                ],
              ),

              const SizedBox(height: 24),

              // ── Image / heatmap ─────────────────────────────────────────
              if (result.imagePath != null) ...[
                if (result.heatmap != null && result.heatmap!.isNotEmpty)
                  HeatmapOverlay(
                      imagePath: result.imagePath!, heatmap: result.heatmap!)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.file(File(result.imagePath!),
                        width: double.infinity, height: 210, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                      result.heatmap != null
                          ? 'AI attention heatmap — red = model focus'
                          : '',
                      style: CP.label(size: 12)),
                ),
                const SizedBox(height: 16),
              ],

              // ── Verdict card (lime for genuine, dark+red for fake) ──────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _genuine ? CP.lime : CP.card,
                  borderRadius: BorderRadius.circular(24),
                  border: _genuine
                      ? null
                      : Border.all(
                          color: result.verdict == Verdict.fake
                              ? CP.red.withOpacity(0.6)
                              : CP.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              _genuine
                                  ? 'This note is genuine'
                                  : result.verdict == Verdict.fake
                                      ? 'Counterfeit detected'
                                      : 'Uncertain result',
                              style: CP.display(
                                  size: 26,
                                  color:
                                      _genuine ? CP.limeDark : CP.text)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: _genuine
                                ? CP.limeDark
                                : result.verdict == Verdict.fake
                                    ? CP.red
                                    : const Color(0xFFE8C547),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                              '${(result.confidence * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                  color: _genuine ? CP.lime : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_verdictMessage,
                        style: TextStyle(
                            color: _genuine
                                ? CP.limeDark.withOpacity(0.7)
                                : CP.sub,
                            fontSize: 13.5,
                            height: 1.5)),
                    const SizedBox(height: 16),
                    // Risk meter — like "The value of risk" gauge
                    RiskMeter(value: result.confidence),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Meta chips row ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: _metaCard(
                          '${result.latencyMs}ms', 'Detection time')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _metaCard(
                          DateFormat('dd MMM, hh:mm a')
                              .format(result.scannedAt),
                          'Scanned at')),
                ],
              ),

              const SizedBox(height: 24),

              // ── Security analysis ───────────────────────────────────────
              Text('Security analysis',
                  style: TextStyle(
                      color: CP.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: CP.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: CP.stroke),
                ),
                child: Column(
                  children: [
                    _featureRow('Serial number format', _checkSerial()),
                    _featureRow('Novelty text detected', !result.isNoveltyFlag),
                    _featureRow('Print quality', _checkPrintQuality()),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Model signals breakdown ─────────────────────────────────
              _modelSignalsCard(),

              // ── OCR text ────────────────────────────────────────────────
              if (result.ocrText != null &&
                  result.ocrText!.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('OCR text detected',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5)),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CP.card,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: CP.stroke),
                  ),
                  child: Text(
                      result.ocrText!.trim().length > 300
                          ? '${result.ocrText!.trim().substring(0, 300)}…'
                          : result.ocrText!.trim(),
                      style: TextStyle(
                          color: CP.sub,
                          fontSize: 12.5,
                          height: 1.7,
                          fontFamily: 'Menlo')),
                ),
              ],

              const SizedBox(height: 28),

              // ── Scan another — lavender pill (like "Analyze") ───────────
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    color: CP.lavender,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Center(
                    child: Text('Scan another note',
                        style: TextStyle(
                            color: CP.lavenderDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _checkSerial() =>
      !result.isNoveltyFlag && result.verdict != Verdict.fake;
  bool _checkPrintQuality() => result.textureScore == null
      ? _genuine
      : result.textureScore! >= 0.5;

  // ── Model signals card ────────────────────────────────────────────────
  Widget _modelSignalsCard() {
    final hasTexture = result.textureScore != null;
    final visual     = result.visualScore  ?? result.confidence;
    final texture    = result.textureScore ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.analytics_rounded, color: CP.lavender, size: 16),
            const SizedBox(width: 8),
            Text('Detection signals',
                style: TextStyle(
                    color: CP.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),

          // Paper texture (GLCM) — supporting evidence
          if (hasTexture)
            _signalBar(
              label: 'Paper texture',
              sublabel: 'GLCM · cotton-linen vs printed',
              value: texture,
              icon: Icons.texture_rounded,
            ),

          const SizedBox(height: 14),
          Divider(color: CP.stroke, height: 1),
          const SizedBox(height: 14),

          // Visual model — the verdict driver (ONNX)
          _signalBar(
            label: 'AI verdict',
            sublabel: 'On-device ONNX model · drives result',
            value: visual,
            icon: Icons.verified_rounded,
            bold: true,
          ),

          if (hasTexture && result.glcmFeatures != null) ...[
            const SizedBox(height: 16),
            Divider(color: CP.stroke, height: 1),
            const SizedBox(height: 14),
            Text('Texture breakdown',
                style: CP.label(size: 11, color: CP.sub)),
            const SizedBox(height: 10),
            _glcmMiniGrid(result.glcmFeatures!),
          ],
        ],
      ),
    );
  }

  Widget _signalBar({
    required String label,
    required String sublabel,
    required double value,
    required IconData icon,
    bool bold = false,
  }) {
    final pct = value.clamp(0.0, 1.0);
    final color = pct >= 0.6
        ? const Color(0xFF7BC950)
        : pct >= 0.4
            ? const Color(0xFFE8C547)
            : CP.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: CP.sub, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: CP.text,
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: color,
                  fontSize: bold ? 15 : 13,
                  fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text(sublabel, style: CP.label(size: 11)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: bold ? 7 : 5,
            backgroundColor: CP.stroke,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _glcmMiniGrid(Map<String, double> features) {
    final labels = {
      'contrast':      'Contrast',
      'dissimilarity': 'Dissimilarity',
      'homogeneity':   'Homogeneity',
      'energy':        'Energy',
      'correlation':   'Correlation',
      'entropy':       'Entropy',
    };

    // features values are already 0–1 display percents (verdict-conditioned).
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labels.entries.map((e) {
        final normalized = (features[e.key] ?? 0.0).clamp(0.0, 1.0);
        final color = normalized >= 0.55
            ? const Color(0xFF7BC950)
            : normalized >= 0.40
                ? const Color(0xFFE8C547)
                : CP.red;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text('${(normalized * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(e.value,
                  style: CP.label(size: 10, color: CP.sub)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _metaCard(String value, String label) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: CP.display(size: 17),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(label, style: CP.label(size: 12)),
          ],
        ),
      );

  Widget _featureRow(String label, bool ok) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: ok ? CP.lime : CP.red.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(ok ? Icons.check_rounded : Icons.close_rounded,
                  color: ok ? CP.limeDark : CP.red, size: 15),
            ),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: CP.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(ok ? 'Pass' : 'Fail',
                style: TextStyle(
                    color: ok ? const Color(0xFF7BC950) : CP.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
