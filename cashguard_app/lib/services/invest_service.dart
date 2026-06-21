import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset.dart';

/// Provides Invest-feature data. Stocks use realistic sample data (matching the
/// template); holdings are SIMULATED paper-trades persisted locally — no real
/// brokerage, no real money moves.
class InvestService {
  static const _key = 'sim_holdings';

  // ── Deterministic candle generator ──────────────────────────────────────
  // Builds believable OHLC data around a price with a given trend/volatility.
  static List<Candle> _genCandles({
    required double end,        // final close
    required double trend,      // overall drift (fraction, e.g. 0.08 = +8%)
    required double vol,        // per-candle volatility fraction
    int count = 26,
    int seed = 7,
  }) {
    final rnd = Random(seed);
    final start = end / (1 + trend);
    final candles = <Candle>[];
    double prevClose = start;
    for (int i = 0; i < count; i++) {
      final t = i / (count - 1);
      final base = start + (end - start) * t;
      final open = prevClose;
      final drift = (base - open) * 0.6;
      final noise = (rnd.nextDouble() - 0.5) * 2 * vol * base;
      double close = open + drift + noise;
      final hi = max(open, close) + rnd.nextDouble() * vol * base;
      final lo = min(open, close) - rnd.nextDouble() * vol * base;
      candles.add(Candle(open, hi, lo, close));
      prevClose = close;
    }
    return candles;
  }

  // ── Sample stocks (USD) ─────────────────────────────────────────────────
  static List<Asset> stocks() => [
        Asset(
          ticker: 'GOOGL',
          name: 'Alphabet Inc.',
          kind: AssetKind.stock,
          price: 188.32,
          change: 24.41,
          changePct: 8.08,
          volume: '\$320.46M',
          brandColor: const Color(0xFF4285F4),
          glyph: 'G',
          candles: _genCandles(end: 188.32, trend: 0.10, vol: 0.018, seed: 11),
          prevClose: 188.32,
          dayLow: 180.32, dayHigh: 191.24,
          weekLow: 171.54, weekHigh: 201.22,
          allLow: 51.24, allHigh: 353.52,
          about:
              'Alphabet Inc. is the parent company of Google, the world\'s largest search engine, and operates across advertising, cloud computing, YouTube, and other technology bets.',
        ),
        Asset(
          ticker: 'AAPL',
          name: 'Apple Inc.',
          kind: AssetKind.stock,
          price: 229.87,
          change: 3.12,
          changePct: 1.38,
          volume: '\$412.10M',
          brandColor: const Color(0xFFE8E8E8),
          glyph: '',
          candles: _genCandles(end: 229.87, trend: 0.04, vol: 0.012, seed: 3),
          prevClose: 226.75,
          dayLow: 225.10, dayHigh: 231.40,
          weekLow: 164.08, weekHigh: 237.49,
          allLow: 0.51, allHigh: 237.49,
          about:
              'Apple Inc. designs and sells iPhone, Mac, iPad, and wearables, complemented by a fast-growing services business spanning the App Store, iCloud, and Apple Pay.',
        ),
        Asset(
          ticker: 'TSLA',
          name: 'Tesla, Inc.',
          kind: AssetKind.stock,
          price: 248.50,
          change: -6.74,
          changePct: -2.64,
          volume: '\$598.23M',
          brandColor: const Color(0xFFE82127),
          glyph: 'T',
          candles: _genCandles(end: 248.50, trend: -0.05, vol: 0.025, seed: 19),
          prevClose: 255.24,
          dayLow: 244.10, dayHigh: 258.90,
          weekLow: 138.80, weekHigh: 299.29,
          allLow: 1.05, allHigh: 414.50,
          about:
              'Tesla designs and manufactures electric vehicles, battery energy storage, and solar products, and develops autonomous-driving and AI technology.',
        ),
        Asset(
          ticker: 'MSFT',
          name: 'Microsoft Corp.',
          kind: AssetKind.stock,
          price: 415.26,
          change: 5.88,
          changePct: 1.44,
          volume: '\$210.77M',
          brandColor: const Color(0xFF00A4EF),
          glyph: 'M',
          candles: _genCandles(end: 415.26, trend: 0.06, vol: 0.011, seed: 23),
          prevClose: 409.38,
          dayLow: 408.90, dayHigh: 417.20,
          weekLow: 309.45, weekHigh: 468.35,
          allLow: 0.06, allHigh: 468.35,
          about:
              'Microsoft builds software, cloud (Azure), productivity (Microsoft 365), Windows, gaming (Xbox), and is a leader in enterprise AI through its OpenAI partnership.',
        ),
        Asset(
          ticker: 'AMZN',
          name: 'Amazon.com Inc.',
          kind: AssetKind.stock,
          price: 201.45,
          change: 4.02,
          changePct: 2.04,
          volume: '\$355.91M',
          brandColor: const Color(0xFFFF9900),
          glyph: 'a',
          candles: _genCandles(end: 201.45, trend: 0.07, vol: 0.016, seed: 31),
          prevClose: 197.43,
          dayLow: 196.80, dayHigh: 203.10,
          weekLow: 118.35, weekHigh: 215.90,
          allLow: 0.07, allHigh: 215.90,
          about:
              'Amazon is a global leader in e-commerce, cloud infrastructure (AWS), digital advertising, and devices, serving hundreds of millions of customers worldwide.',
        ),
        Asset(
          ticker: 'NVDA',
          name: 'NVIDIA Corp.',
          kind: AssetKind.stock,
          price: 138.07,
          change: 9.31,
          changePct: 7.23,
          volume: '\$845.62M',
          brandColor: const Color(0xFF76B900),
          glyph: 'N',
          candles: _genCandles(end: 138.07, trend: 0.12, vol: 0.022, seed: 41),
          prevClose: 128.76,
          dayLow: 127.90, dayHigh: 140.20,
          weekLow: 47.32, weekHigh: 152.89,
          allLow: 0.03, allHigh: 152.89,
          about:
              'NVIDIA designs GPUs and AI accelerators powering data centers, gaming, and the global artificial-intelligence boom, alongside automotive and robotics platforms.',
        ),
      ];

  // ── Sample crypto (USD) ─────────────────────────────────────────────────
  static List<Asset> crypto() => [
        Asset(
          ticker: 'BTC',
          name: 'Bitcoin',
          kind: AssetKind.crypto,
          price: 67432.10,
          change: 1843.22,
          changePct: 2.81,
          volume: '\$28.4B',
          brandColor: const Color(0xFFF7931A),
          glyph: '₿',
          candles: _genCandles(end: 67432.10, trend: 0.08, vol: 0.02, seed: 5),
          prevClose: 65588.88,
          dayLow: 64900, dayHigh: 68100,
          weekLow: 49200, weekHigh: 73750,
          allLow: 67.81, allHigh: 73750,
          about:
              'Bitcoin is the first and largest decentralized cryptocurrency, a peer-to-peer digital store of value secured by a global proof-of-work network.',
        ),
        Asset(
          ticker: 'ETH',
          name: 'Ethereum',
          kind: AssetKind.crypto,
          price: 3287.65,
          change: -42.10,
          changePct: -1.26,
          volume: '\$14.1B',
          brandColor: const Color(0xFF627EEA),
          glyph: 'Ξ',
          candles: _genCandles(end: 3287.65, trend: -0.03, vol: 0.022, seed: 13),
          prevClose: 3329.75,
          dayLow: 3240, dayHigh: 3360,
          weekLow: 2110, weekHigh: 4090,
          allLow: 0.43, allHigh: 4878,
          about:
              'Ethereum is a programmable blockchain powering smart contracts, DeFi, NFTs, and thousands of decentralized applications, secured by proof-of-stake.',
        ),
        Asset(
          ticker: 'SOL',
          name: 'Solana',
          kind: AssetKind.crypto,
          price: 178.43,
          change: 12.55,
          changePct: 7.57,
          volume: '\$4.8B',
          brandColor: const Color(0xFF14F195),
          glyph: 'S',
          candles: _genCandles(end: 178.43, trend: 0.11, vol: 0.03, seed: 29),
          prevClose: 165.88,
          dayLow: 162.10, dayHigh: 182.40,
          weekLow: 88.20, weekHigh: 210.50,
          allLow: 0.50, allHigh: 260.06,
          about:
              'Solana is a high-throughput blockchain known for fast, low-cost transactions, popular for DeFi, NFTs, and consumer crypto applications.',
        ),
        Asset(
          ticker: 'BNB',
          name: 'BNB',
          kind: AssetKind.crypto,
          price: 612.78,
          change: 8.90,
          changePct: 1.47,
          volume: '\$1.9B',
          brandColor: const Color(0xFFF3BA2F),
          glyph: 'B',
          candles: _genCandles(end: 612.78, trend: 0.05, vol: 0.018, seed: 37),
          prevClose: 603.88,
          dayLow: 599.20, dayHigh: 618.40,
          weekLow: 401.10, weekHigh: 720.90,
          allLow: 0.10, allHigh: 720.90,
          about:
              'BNB is the native token of the BNB Chain ecosystem, used for transaction fees, trading-fee discounts, and a wide range of on-chain applications.',
        ),
      ];

  // ── Simulated holdings (local only) ─────────────────────────────────────
  Future<List<Holding>> getHoldings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) {
          try {
            return Holding.fromMap(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Holding>()
        .toList()
        .reversed
        .toList();
  }

  Future<void> addHolding(Holding h) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(h.toMap()));
    await prefs.setStringList(_key, raw);
  }
}
