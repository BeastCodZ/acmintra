import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme.dart';
import '../services/inference_service.dart';
import '../services/history_service.dart';
import '../models/scan_result.dart';
import '../widgets/analysing_view.dart';
import 'result_screen.dart';
import 'guided_scan_screen.dart';
import 'cash_calculator_screen.dart';
import '../services/statement_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenFinance;
  const HomeScreen({super.key, this.onOpenFinance});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _inference = InferenceService();
  final _history = HistoryService();
  final _picker = ImagePicker();

  bool _modelLoading = true;
  bool _analysing = false;
  List<ScanResult> _all = [];

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadRecent();
  }

  Future<void> _loadModel() async {
    try {
      await _inference.loadModel();
    } catch (e) {
      debugPrint('loadModel error: $e');
    }
    if (mounted) setState(() => _modelLoading = false);
  }

  Future<void> _loadRecent() async {
    try {
      final all = await _history.getHistory();
      if (mounted) setState(() => _all = all);
    } catch (e) {
      debugPrint('loadRecent error: $e');
    }
  }

  // ── Cash Trust Score ──────────────────────────────────────────────────
  // Weighted 0–100: genuine notes contribute their confidence, uncertain
  // contribute 60%, fakes drag the score to 0.
  double get _trustScore {
    if (_all.isEmpty) return 0;
    double sum = 0;
    for (final r in _all) {
      switch (r.verdict) {
        case Verdict.genuine:
          sum += r.confidence;
          break;
        case Verdict.uncertain:
          sum += r.confidence * 0.6;
          break;
        case Verdict.fake:
          sum += 0;
          break;
      }
    }
    return (sum / _all.length * 100).clamp(0, 100);
  }

  // Confidence trail for the sparkline (oldest → newest, max 12)
  List<double> get _confTrail {
    final list = _all.reversed.toList(); // oldest first
    final tail = list.length > 12 ? list.sublist(list.length - 12) : list;
    return tail.map((r) => r.confidence).toList();
  }

  String get _trustLabel {
    final s = _trustScore;
    if (s >= 80) return 'Your cash looks trustworthy';
    if (s >= 60) return 'Mostly clean — stay alert';
    if (s >= 40) return 'Some notes need a closer look';
    return 'High risk — verify carefully';
  }

  Color get _trustColor {
    final s = _trustScore;
    if (s >= 80) return const Color(0xFF7BC950);
    if (s >= 60) return CP.lime;
    if (s >= 40) return const Color(0xFFE8C547);
    return CP.red;
  }

  void scanWithCamera() => _openGuidedScan();

  void _openGuidedScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GuidedScanScreen(
          onCapture: (path) => _runFromPath(path),
        ),
      ),
    );
  }

  // Copy a (possibly temp) capture into permanent app storage so the
  // thumbnail survives — iOS clears the temp directory.
  Future<String> _persistImage(List<int> bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/scans');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest =
        '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(dest).writeAsBytes(bytes);
    return dest;
  }

  Future<void> _runFromPath(String path) async {
    if (_modelLoading) return;
    setState(() => _analysing = true);
    try {
      final bytes = await File(path).readAsBytes();
      final permPath = await _persistImage(bytes);
      final result = await _inference.runInference(bytes, permPath);
      await _history.addResult(result);
      _loadRecent();
      if (mounted) {
        setState(() => _analysing = false);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ResultScreen(result: result)));
      }
    } catch (e) {
      setState(() => _analysing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Analysis failed: $e')));
      }
    }
  }

  Future<void> _pickAndScan(ImageSource source) async {
    if (_modelLoading || _analysing) return;
    final file = await _picker.pickImage(
        source: source, imageQuality: 95, maxWidth: 1024, maxHeight: 1024);
    if (file == null) return;
    await _runFromPath(file.path);
  }

  @override
  void dispose() {
    _inference.dispose();
    super.dispose();
  }

  int get _genuineCount =>
      _all.where((r) => r.verdict == Verdict.genuine).length;

  int get _fakeCount => _all
      .where((r) => r.verdict == Verdict.fake || r.verdict == Verdict.uncertain)
      .length;

  int get _avgConfidence => _all.isEmpty
      ? 0
      : (_all.map((r) => r.confidence).reduce((a, b) => a + b) /
              _all.length *
              100)
          .round();

  @override
  Widget build(BuildContext context) {
    if (_modelLoading || _analysing) return _loading();

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ─────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: CP.lime,
                      borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.add_rounded,
                      color: CP.limeDark, size: 20),
                ),
                const SizedBox(width: 10),
                Text('CashGuard',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                RoundIconBtn(Icons.add_rounded, onTap: _openGuidedScan),
              ],
            ),

            const SizedBox(height: 30),

            // ── Header ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your cash, verified', style: CP.label()),
                      const SizedBox(height: 4),
                      Text('${_all.length} note${_all.length == 1 ? '' : 's'} scanned',
                          style: CP.display(size: 26)),
                    ],
                  ),
                ),
                const PillChip('All time',
                    trailing: Icons.keyboard_arrow_down_rounded),
              ],
            ),

            const SizedBox(height: 18),

            // ── Stats strip ──────────────────────────────────────────────
            Row(
              children: [
                _statCard(Icons.verified_rounded, '$_genuineCount', 'Genuine',
                    const Color(0xFF7BC950)),
                const SizedBox(width: 10),
                _statCard(Icons.flag_rounded, '$_fakeCount', 'Flagged', CP.red),
                const SizedBox(width: 10),
                _statCard(Icons.insights_rounded,
                    _all.isEmpty ? '—' : '$_avgConfidence%', 'Avg conf.',
                    CP.lavender),
              ],
            ),

            const SizedBox(height: 28),

            // ── Hero scan card (lime, like "Buy a house") ───────────────
            GestureDetector(
              onTap: _openGuidedScan,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CP.lime,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.center_focus_strong_rounded,
                              color: CP.limeDark, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Scan a note',
                                  style: CP.display(
                                      size: 22, color: CP.limeDark)),
                              const SizedBox(height: 2),
                              Text('Camera  ·  Counterfeit check',
                                  style: TextStyle(
                                      color: CP.limeDark.withOpacity(0.65),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: CP.limeDark),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // progress-style bar like the goal card
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: 0.946,
                        minHeight: 4,
                        backgroundColor: CP.limeDark.withOpacity(0.15),
                        valueColor:
                            const AlwaysStoppedAnimation(CP.limeDark),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('94.6% accuracy',
                            style: TextStyle(
                                color: CP.limeDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text('on-device AI',
                            style: TextStyle(
                                color: CP.limeDark.withOpacity(0.6),
                                fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Gallery card (dark, like secondary goal cards) ───────────
            GestureDetector(
              onTap: () => _pickAndScan(ImageSource.gallery),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CP.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: CP.stroke),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: CP.card2,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.photo_library_rounded,
                          color: CP.text, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Upload from gallery',
                              style: CP.display(size: 20)),
                          const SizedBox(height: 2),
                          Text('Photos  ·  Existing image',
                              style: CP.label()),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: CP.sub),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Cash calculator entry ────────────────────────────────────
            _cashCalcCard(),

            const SizedBox(height: 30),

            // ── Cash Trust Score ─────────────────────────────────────────
            _trustScoreCard(),

            const SizedBox(height: 14),

            // ── Where's my cash going? (Finance teaser) ──────────────────
            _financeTeaser(),
          ],
        ),
      ),
    );
  }

  Widget _cashCalcCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CashCalculatorScreen())),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CP.stroke),
        ),
        child: Row(
          children: [
            // Stacked notes mini-graphic
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (int i = 0; i < 3; i++)
                    Transform.translate(
                      offset: Offset((i - 1) * 3.0, (i - 1) * -4.0),
                      child: Transform.rotate(
                        angle: (i - 1) * 0.12,
                        child: Container(
                          width: 44,
                          height: 26,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              [CP.lavender, const Color(0xFFF0B44A), const Color(0xFF5FBBD0)][i],
                              [const Color(0xFF8C6FC4), const Color(0xFFD9912B), const Color(0xFF3E96AC)][i],
                            ]),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.18)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cash calculator', style: CP.display(size: 20)),
                  const SizedBox(height: 2),
                  Text('Break any amount into notes & coins',
                      style: CP.label()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CP.sub),
          ],
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge with soft accent glow
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: 14),
            Text(value, style: CP.display(size: 24)),
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  width: 5, height: 5,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: CP.label(size: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── #6 Cash Trust Score gauge + sparkline ─────────────────────────────
  Widget _trustScoreCard() {
    final hasData = _all.isNotEmpty;
    final score = _trustScore.round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: CP.lavender, size: 18),
              const SizedBox(width: 8),
              Text('Cash Trust Score',
                  style: TextStyle(
                      color: CP.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_all.length} scan${_all.length == 1 ? '' : 's'}',
                  style: CP.label(size: 12)),
            ],
          ),
          const SizedBox(height: 18),
          if (!hasData)
            SizedBox(
              height: 96,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded,
                        color: CP.sub.withOpacity(0.5), size: 30),
                    const SizedBox(height: 8),
                    Text('Scan your first note to build a score',
                        style: CP.label(size: 13)),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                // Circular gauge
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CustomPaint(
                    painter: _GaugePainter(
                        value: score / 100, color: _trustColor),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$score',
                              style: CP.display(size: 30, color: CP.text)),
                          Text('/ 100', style: CP.label(size: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_trustLabel,
                          style: TextStyle(
                              color: CP.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.25)),
                      const SizedBox(height: 12),
                      // Sparkline
                      SizedBox(
                        height: 34,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _SparklinePainter(
                              values: _confTrail, color: _trustColor),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Confidence trend',
                          style: CP.label(size: 11)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── #4 Where's my cash going? ─────────────────────────────────────────
  Widget _financeTeaser() {
    const data = StatementAnalysis.demo;
    final insight = data.insights.isNotEmpty
        ? data.insights.first
        : 'Upload a statement to see where your money goes.';
    final scoreColor = data.healthScore >= 70
        ? const Color(0xFF7BC950)
        : data.healthScore >= 50
            ? const Color(0xFFE8C547)
            : CP.red;
    return GestureDetector(
      onTap: widget.onOpenFinance,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: CP.lime, size: 18),
                const SizedBox(width: 8),
                Text("Where's my cash going?",
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: CP.sub),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                // Health score ring
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _GaugePainter(
                        value: data.healthScore / 100,
                        color: scoreColor,
                        stroke: 5),
                    child: Center(
                      child: Text('${data.healthScore}',
                          style: CP.display(size: 19, color: CP.text)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Financial health',
                          style: TextStyle(
                              color: CP.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(insight,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CP.label(size: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Top categories mini-bar
            Row(
              children: [
                for (int i = 0; i < data.categories.take(3).length; i++) ...[
                  Expanded(
                    flex: data.categories[i].pct.round().clamp(1, 100),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: chartColors[i % chartColors.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (i != 2) const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (int i = 0; i < data.categories.take(3).length; i++) ...[
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: chartColors[i % chartColors.length],
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(data.categories[i].name, style: CP.label(size: 11)),
                  if (i != 2) const SizedBox(width: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() {
    return _modelLoading
        ? const AnalysingView(
            title: 'Waking up the AI',
            icon: Icons.bolt_rounded,
            steps: [
              'Loading neural network',
              'Preparing ONNX runtime',
              'Almost ready',
            ],
          )
        : const AnalysingView(
            title: 'Analysing Bank Note',
            steps: [
              'Preprocessing image',
              'Reading text with OCR',
              'Running neural network',
              'Building attention heatmap',
            ],
          );
  }
}

// ── Circular gauge (arc filled by [value] 0..1) ─────────────────────────────
class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final double stroke;
  _GaugePainter({required this.value, required this.color, this.stroke = 7});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track
    canvas.drawArc(
      rect, -1.5708, 6.2832, false,
      Paint()
        ..color = CP.card2
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    // Value arc
    canvas.drawArc(
      rect, -1.5708, 6.2832 * value.clamp(0.0, 1.0), false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

// ── Sparkline (filled area line of confidence values) ───────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    if (values.length == 1) {
      final y = size.height * (1 - values.first.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(size.width / 2, y), 3, Paint()..color = color);
      return;
    }
    final dx = size.width / (values.length - 1);
    final pts = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(i * dx, size.height * (1 - values[i].clamp(0.0, 1.0)))
    ];

    // Filled area
    final fill = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(pts.last.dx, size.height);
    fill.close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(0.30), color.withOpacity(0.0)],
          ).createShader(Offset.zero & size));

    // Line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    // Last point dot
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}
