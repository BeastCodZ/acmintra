import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/history_service.dart';
import '../models/scan_result.dart';
import 'result_screen.dart';

enum _Filter { all, genuine, flagged }

const _green = Color(0xFF7BC950);
const _amber = Color(0xFFE8C547);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _history = HistoryService();
  List<ScanResult> _results = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await _history.getHistory();
    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    await _history.clearHistory();
    setState(() => _results = []);
  }

  Future<void> _delete(ScanResult r) async {
    await _history.deleteResult(r);
    setState(() => _results.remove(r));
  }

  // ── Verdict helpers ────────────────────────────────────────────────────
  Color _color(Verdict v) => v == Verdict.genuine
      ? _green
      : v == Verdict.fake
          ? CP.red
          : _amber;

  IconData _icon(Verdict v) => v == Verdict.genuine
      ? Icons.verified_rounded
      : v == Verdict.fake
          ? Icons.gpp_bad_rounded
          : Icons.help_rounded;

  int get _genuine =>
      _results.where((r) => r.verdict == Verdict.genuine).length;
  int get _flagged =>
      _results.where((r) => r.verdict != Verdict.genuine).length;

  List<ScanResult> get _filtered {
    switch (_filter) {
      case _Filter.genuine:
        return _results.where((r) => r.verdict == Verdict.genuine).toList();
      case _Filter.flagged:
        return _results.where((r) => r.verdict != Verdict.genuine).toList();
      case _Filter.all:
        return _results;
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              children: [
                Text('Wallet history',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4)),
                const Spacer(),
                if (_results.isNotEmpty) PillChip('Clear', onTap: _clear),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: CP.lavender))
                : _results.isEmpty
                    ? _emptyState()
                    : _content(),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final items = <Widget>[];
    String? lastDay;
    for (final r in _filtered) {
      final day = _dayLabel(r.scannedAt);
      if (day != lastDay) {
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(4, lastDay == null ? 4 : 18, 4, 10),
          child: Text(day,
              style: TextStyle(
                  color: CP.sub,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
        ));
        lastDay = day;
      }
      items.add(_tile(r));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 130),
      children: [
        _summary(),
        const SizedBox(height: 16),
        _filterChips(),
        const SizedBox(height: 4),
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
                child: Text('Nothing here', style: CP.label(size: 14))),
          )
        else
          ...items,
      ],
    );
  }

  // ── Summary strip ────────────────────────────────────────────────────
  Widget _summary() {
    Widget cell(String value, String label, Color dot) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: CP.display(size: 24)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label, style: CP.label(size: 11)),
              ]),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CP.stroke),
      ),
      child: Row(
        children: [
          cell('${_results.length}', 'Total scans', CP.lavender),
          cell('$_genuine', 'Genuine', _green),
          cell('$_flagged', 'Flagged', CP.red),
        ],
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────
  Widget _filterChips() {
    Widget chip(String label, _Filter f) {
      final active = _filter == f;
      return GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? CP.lavender : CP.card,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: active ? CP.lavender : CP.stroke),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? CP.lavenderDark : CP.sub,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      );
    }

    return Row(children: [
      chip('All', _Filter.all),
      chip('Genuine', _Filter.genuine),
      chip('Flagged', _Filter.flagged),
    ]);
  }

  // ── Row ────────────────────────────────────────────────────────────────
  Widget _tile(ScanResult r) {
    final color = _color(r.verdict);
    final hasImg = r.imagePath != null && File(r.imagePath!).existsSync();

    return Dismissible(
      key: ValueKey(r.scannedAt.toIso8601String()),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(r),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
            color: CP.red.withOpacity(0.18),
            borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete_rounded, color: CP.red),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ResultScreen(result: r))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: CP.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CP.stroke),
          ),
          child: Row(
            children: [
              // Thumbnail or verdict badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: hasImg
                        ? Image.file(File(r.imagePath!),
                            width: 52, height: 52, fit: BoxFit.cover)
                        : Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(12)),
                            child:
                                Icon(_icon(r.verdict), color: color, size: 24),
                          ),
                  ),
                  if (hasImg)
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: CP.card, shape: BoxShape.circle),
                        child: Icon(_icon(r.verdict), color: color, size: 13),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Verdict + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.verdictLabel,
                        style: TextStyle(
                            color: CP.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(DateFormat('hh:mm a').format(r.scannedAt),
                        style: CP.label(size: 12)),
                  ],
                ),
              ),
              // Confidence pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(100)),
                child: Text('${(r.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: CP.sub, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wallet_rounded,
                color: CP.sub.withOpacity(0.4), size: 56),
            const SizedBox(height: 16),
            Text('No scans yet', style: CP.display(size: 20)),
            const SizedBox(height: 6),
            Text('Tap ✛ to scan your first note', style: CP.label()),
          ],
        ),
      );
}
