import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_result.dart';

class HistoryService {
  static const _key = 'scan_history';

  Future<List<ScanResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) {
          try {
            return ScanResult.fromMap(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<ScanResult>()
        .toList()
        .reversed
        .toList();
  }

  Future<void> addResult(ScanResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(result.toMap()));
    // Keep last 100 scans
    if (raw.length > 100) raw.removeAt(0);
    await prefs.setStringList(_key, raw);
  }

  Future<void> deleteResult(ScanResult r) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final iso = r.scannedAt.toIso8601String();
    raw.removeWhere((e) {
      try {
        return (jsonDecode(e) as Map<String, dynamic>)['scannedAt'] == iso;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
