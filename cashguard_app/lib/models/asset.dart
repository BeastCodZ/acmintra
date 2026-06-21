import 'package:flutter/material.dart';

/// One OHLC candle for the candlestick chart.
class Candle {
  final double open;
  final double high;
  final double low;
  final double close;
  const Candle(this.open, this.high, this.low, this.close);

  bool get up => close >= open;
}

enum AssetKind { stock, crypto }

/// A tradeable asset (stock or crypto) shown in the Invest feature.
class Asset {
  final String ticker;        // GOOGL
  final String name;          // Alphabet Inc.
  final AssetKind kind;
  final double price;         // current price (USD)
  final double change;        // absolute change
  final double changePct;     // % change
  final String volume;        // "$320.46M"
  final Color brandColor;     // logo tint
  final String glyph;         // short logo glyph e.g. "G", "₿"
  final List<Candle> candles; // chart data

  // Market stats
  final double prevClose;
  final double dayLow, dayHigh;
  final double weekLow, weekHigh;     // 52-week
  final double allLow, allHigh;       // all-time
  final String about;

  const Asset({
    required this.ticker,
    required this.name,
    required this.kind,
    required this.price,
    required this.change,
    required this.changePct,
    required this.volume,
    required this.brandColor,
    required this.glyph,
    required this.candles,
    required this.prevClose,
    required this.dayLow,
    required this.dayHigh,
    required this.weekLow,
    required this.weekHigh,
    required this.allLow,
    required this.allHigh,
    required this.about,
  });

  bool get up => change >= 0;
}

/// A simulated (paper-trading) holding stored locally.
class Holding {
  final String ticker;
  final String name;
  final double amountUsd;     // money put in
  final double shares;        // shares bought
  final double priceAtBuy;
  final DateTime boughtAt;
  final String account;

  const Holding({
    required this.ticker,
    required this.name,
    required this.amountUsd,
    required this.shares,
    required this.priceAtBuy,
    required this.boughtAt,
    required this.account,
  });

  Map<String, dynamic> toMap() => {
        'ticker': ticker,
        'name': name,
        'amountUsd': amountUsd,
        'shares': shares,
        'priceAtBuy': priceAtBuy,
        'boughtAt': boughtAt.toIso8601String(),
        'account': account,
      };

  factory Holding.fromMap(Map<String, dynamic> m) => Holding(
        ticker: m['ticker'],
        name: m['name'],
        amountUsd: (m['amountUsd'] as num).toDouble(),
        shares: (m['shares'] as num).toDouble(),
        priceAtBuy: (m['priceAtBuy'] as num).toDouble(),
        boughtAt: DateTime.parse(m['boughtAt']),
        account: m['account'] ?? 'Santander',
      );
}
