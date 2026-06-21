import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/asset.dart';
import '../widgets/candlestick_chart.dart';
import 'buy_screen.dart';

final _money = NumberFormat('#,##0.##');
const _green = Color(0xFF7BC950);

class AssetDetailScreen extends StatefulWidget {
  final Asset asset;
  const AssetDetailScreen({super.key, required this.asset});

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  int _range = 0; // 1D index
  int _tab = 0;   // About / News / Orders

  static const _ranges = ['1D', '1W', '1M', 'YTD', 'MAX'];
  static const _tabs = ['About', 'News', 'Orders'];

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: CP.text, size: 18),
                  ),
                  const SizedBox(width: 12),
                  _logo(a, 30),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          style: const TextStyle(
                              color: CP.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(a.ticker, style: CP.label(size: 12)),
                    ],
                  ),
                  const Spacer(),
                  PillChip('Buy',
                      filled: true,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => BuyScreen(asset: a)))),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                children: [
                  // ── Price + change + volume ─────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('\$ ${_money.format(a.price)}',
                          style: CP.display(size: 40)),
                      const Spacer(),
                      Text('Vol: ${a.volume}', style: CP.label(size: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(a.up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                        color: a.up ? _green : CP.red, size: 22),
                    Text(
                        '${a.up ? '+' : '-'}\$${_money.format(a.change.abs())} (${a.changePct.abs().toStringAsFixed(2)}%)',
                        style: TextStyle(
                            color: a.up ? _green : CP.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ]),

                  const SizedBox(height: 18),

                  // ── Chart ───────────────────────────────────────────────
                  CandlestickChart(
                    candles: a.candles,
                    height: 220,
                    showGrid: true,
                  ),

                  const SizedBox(height: 16),

                  // ── Range selector ──────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_ranges.length, (i) {
                      final active = _range == i;
                      return GestureDetector(
                        onTap: () => setState(() => _range = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? CP.card2 : Colors.transparent,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(_ranges[i],
                              style: TextStyle(
                                  color: active ? CP.text : CP.sub,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 22),

                  // ── Segmented tabs ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: CP.card,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: CP.stroke),
                    ),
                    child: Row(
                      children: List.generate(_tabs.length, (i) {
                        final active = _tab == i;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _tab = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: active ? CP.lavender : Colors.transparent,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Center(
                                child: Text(_tabs[i],
                                    style: TextStyle(
                                        color: active ? CP.lavenderDark : CP.sub,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── Tab content ─────────────────────────────────────────
                  if (_tab == 0) _aboutTab(a),
                  if (_tab == 1) _newsTab(a),
                  if (_tab == 2) _ordersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── About: market stats ──────────────────────────────────────────────
  Widget _aboutTab(Asset a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Market stats',
            style: TextStyle(
                color: CP.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4)),
        const SizedBox(height: 14),
        _statRow('Previously close', '\$${_money.format(a.prevClose)}'),
        _statRow('Day range',
            '\$${_money.format(a.dayLow)} – \$${_money.format(a.dayHigh)}'),
        _statRow('52-Week range',
            '\$${_money.format(a.weekLow)} – \$${_money.format(a.weekHigh)}'),
        _statRow('All time range',
            '\$${_money.format(a.allLow)} – \$${_money.format(a.allHigh)}'),
        const SizedBox(height: 22),
        Text('About', style: CP.display(size: 20)),
        const SizedBox(height: 10),
        Text(a.about,
            style: TextStyle(color: CP.sub, fontSize: 14, height: 1.6)),
      ],
    );
  }

  Widget _statRow(String l, String v) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(l, style: TextStyle(color: CP.sub, fontSize: 14)),
            const Spacer(),
            Text(v,
                style: const TextStyle(
                    color: CP.text, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _newsTab(Asset a) {
    final items = [
      ('${a.name} beats quarterly earnings estimates', '2h ago · Reuters'),
      ('Analysts raise ${a.ticker} price target on strong outlook', '5h ago · Bloomberg'),
      ('What\'s driving ${a.ticker} momentum this week', '1d ago · CNBC'),
    ];
    return Column(
      children: items
          .map((n) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: CP.card, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.$1,
                              style: const TextStyle(
                                  color: CP.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3)),
                          const SizedBox(height: 6),
                          Text(n.$2, style: CP.label(size: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: CP.sub),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _ordersTab() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.receipt_long_rounded,
                color: CP.sub.withOpacity(0.4), size: 48),
            const SizedBox(height: 12),
            Text('No orders yet', style: CP.display(size: 18)),
            const SizedBox(height: 6),
            Text('Your simulated orders will appear here',
                style: CP.label(size: 13)),
          ],
        ),
      );

  Widget _logo(Asset a, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: a.brandColor, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(a.glyph,
            style: TextStyle(
                color: a.brandColor.computeLuminance() > 0.6
                    ? Colors.black
                    : Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w800)),
      );
}
