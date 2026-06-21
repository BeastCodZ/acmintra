import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/asset.dart';
import '../services/invest_service.dart';
import '../widgets/candlestick_chart.dart';
import 'asset_detail_screen.dart';
import 'buy_screen.dart';

final _money = NumberFormat('#,##0.##');
const _green = Color(0xFF9FE870); // vivid accent green from the template

/// "Investment tips and advice" — carousels of shares + crypto.
class InvestScreen extends StatefulWidget {
  const InvestScreen({super.key});

  @override
  State<InvestScreen> createState() => _InvestScreenState();
}

class _InvestScreenState extends State<InvestScreen> {
  final _stocks = InvestService.stocks();
  final _crypto = InvestService.crypto();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Row(children: [
                  const Icon(Icons.arrow_back_ios_new_rounded,
                      color: CP.text, size: 18),
                  const SizedBox(width: 8),
                  Text('Back',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),

            const SizedBox(height: 18),

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: CP.display(size: 38, weight: FontWeight.w600),
                      children: [
                        const TextSpan(text: 'Investment\n'),
                        TextSpan(
                            text: 'tips and advice',
                            style: TextStyle(color: _green)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                      'Check out the offers that will help you invest and increase your savings faster',
                      style: TextStyle(
                          color: CP.sub, fontSize: 14.5, height: 1.5)),
                ],
              ),
            ),

            const SizedBox(height: 26),

            // ── Shares ────────────────────────────────────────────────────
            _sectionHeader('Shares', _stocks.length),
            const SizedBox(height: 14),
            SizedBox(
              height: 320,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _stocks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _assetCard(_stocks[i]),
              ),
            ),

            const SizedBox(height: 28),

            // ── Crypto ────────────────────────────────────────────────────
            _sectionHeader('Crypto investment', _crypto.length),
            const SizedBox(height: 14),
            SizedBox(
              height: 320,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _crypto.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _assetCard(_crypto[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    color: CP.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            const SizedBox(width: 8),
            Text('$count', style: CP.label(size: 16)),
          ],
        ),
      );

  // ── Asset card ──────────────────────────────────────────────────────────
  Widget _assetCard(Asset a) {
    // pick a marker candle near the middle for the price bubble
    final markerIdx = (a.candles.length * 0.45).round();
    final markerPrice = a.candles[markerIdx].high;

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AssetDetailScreen(asset: a))),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: logo, name, price
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CP.card2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _logo(a, 34),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          style: const TextStyle(
                              color: CP.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(a.ticker, style: CP.label(size: 12)),
                    ],
                  ),
                  const Spacer(),
                  Text('\$${_money.format(a.price)}',
                      style: const TextStyle(
                          color: CP.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Text('Price',
                    style: const TextStyle(
                        color: CP.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const PillChip('Data type',
                    trailing: Icons.keyboard_arrow_down_rounded),
              ],
            ),
            const SizedBox(height: 8),

            // Mini chart with marker bubble
            CandlestickChart(
              candles: a.candles,
              height: 130,
              markerIndex: markerIdx,
              markerLabel: '\$${markerPrice.toStringAsFixed(0)}',
              xLabels: const ['11:00', '13:00', '15:00', '17:00'],
            ),

            const SizedBox(height: 14),

            // Buy + arrow
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => BuyScreen(asset: a))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: CP.lavender,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Center(
                        child: Text('Buy',
                            style: TextStyle(
                                color: CP.lavenderDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => AssetDetailScreen(asset: a))),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                        color: _green, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_outward_rounded,
                        color: Color(0xFF17280F), size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
