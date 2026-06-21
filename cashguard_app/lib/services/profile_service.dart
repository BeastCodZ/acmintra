import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/history_service.dart';

class ProfileData {
  final String displayName;
  final String? avatarEmoji;
  final DateTime joinedAt;
  final bool biometricEnabled;
  final bool notificationsEnabled;
  final bool dataBackupEnabled;

  const ProfileData({
    required this.displayName,
    this.avatarEmoji,
    required this.joinedAt,
    this.biometricEnabled = false,
    this.notificationsEnabled = true,
    this.dataBackupEnabled = false,
  });

  ProfileData copyWith({
    String? displayName,
    String? avatarEmoji,
    bool? biometricEnabled,
    bool? notificationsEnabled,
    bool? dataBackupEnabled,
  }) =>
      ProfileData(
        displayName: displayName ?? this.displayName,
        avatarEmoji: avatarEmoji ?? this.avatarEmoji,
        joinedAt: joinedAt,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        dataBackupEnabled: dataBackupEnabled ?? this.dataBackupEnabled,
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'avatarEmoji': avatarEmoji,
        'joinedAt': joinedAt.toIso8601String(),
        'biometricEnabled': biometricEnabled,
        'notificationsEnabled': notificationsEnabled,
        'dataBackupEnabled': dataBackupEnabled,
      };

  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        displayName: j['displayName'] as String? ?? 'CashGuard User',
        avatarEmoji: j['avatarEmoji'] as String?,
        joinedAt: DateTime.tryParse(j['joinedAt'] as String? ?? '') ?? DateTime.now(),
        biometricEnabled: j['biometricEnabled'] as bool? ?? false,
        notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
        dataBackupEnabled: j['dataBackupEnabled'] as bool? ?? false,
      );

  factory ProfileData.fresh() => ProfileData(
        displayName: 'CashGuard User',
        avatarEmoji: '🛡️',
        joinedAt: DateTime.now(),
      );
}

class ScanStats {
  final int total;
  final int genuine;
  final int fake;
  final int uncertain;
  final double avgConfidence;

  const ScanStats({
    required this.total,
    required this.genuine,
    required this.fake,
    required this.uncertain,
    required this.avgConfidence,
  });

  int get fakesCaught => fake;
  double get accuracyRate => total == 0 ? 0 : (genuine + fake) / total;
}

class ProfileService {
  static const _key = 'profile_data';

  Future<ProfileData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final fresh = ProfileData.fresh();
      await save(fresh);
      return fresh;
    }
    return ProfileData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(ProfileData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  Future<ScanStats> loadStats() async {
    final history = await HistoryService().getHistory();
    if (history.isEmpty) {
      return const ScanStats(total: 0, genuine: 0, fake: 0, uncertain: 0, avgConfidence: 0);
    }
    int genuine = 0, fake = 0, uncertain = 0;
    double confSum = 0;
    for (final r in history) {
      switch (r.verdict.name) {
        case 'genuine':
          genuine++;
          break;
        case 'fake':
          fake++;
          break;
        default:
          uncertain++;
      }
      confSum += r.confidence;
    }
    return ScanStats(
      total: history.length,
      genuine: genuine,
      fake: fake,
      uncertain: uncertain,
      avgConfidence: confSum / history.length,
    );
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
