import 'dart:convert';
import 'package:http/http.dart' as http;

class CryptoRate {
  final String id;
  final String symbol;
  final String name;
  final String emoji;
  final double priceInr;
  final double change24h;

  const CryptoRate({
    required this.id,
    required this.symbol,
    required this.name,
    required this.emoji,
    required this.priceInr,
    required this.change24h,
  });
}

class CryptoService {
  static const _coins = ['bitcoin', 'ethereum', 'tether', 'solana', 'binancecoin'];
  static const _emojis = {'bitcoin': '₿', 'ethereum': 'Ξ', 'tether': '₮', 'solana': '◎', 'binancecoin': 'B'};
  static const _names = {'bitcoin': 'Bitcoin', 'ethereum': 'Ethereum', 'tether': 'USDT', 'solana': 'Solana', 'binancecoin': 'BNB'};
  static const _symbols = {'bitcoin': 'BTC', 'ethereum': 'ETH', 'tether': 'USDT', 'solana': 'SOL', 'binancecoin': 'BNB'};

  Future<List<CryptoRate>> fetchRates() async {
    final ids = _coins.join(',');
    final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=$ids&vs_currencies=inr&include_24hr_change=true');
    final res = await http.get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('CoinGecko error ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return _coins.map((id) {
      final data = json[id] as Map<String, dynamic>? ?? {};
      return CryptoRate(
        id: id,
        symbol: _symbols[id]!,
        name: _names[id]!,
        emoji: _emojis[id]!,
        priceInr: (data['inr'] as num?)?.toDouble() ?? 0,
        change24h: (data['inr_24h_change'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }
}
