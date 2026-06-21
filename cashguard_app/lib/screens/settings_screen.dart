import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../services/profile_service.dart';
import '../services/history_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileSvc = ProfileService();

  ProfileData? _profile;
  String _backendUrl = 'http://192.168.29.129:8000';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _profileSvc.load();
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('backend_url') ?? 'http://192.168.29.129:8000';
    if (mounted) {
      setState(() {
        _profile = p;
        _backendUrl = url;
      });
    }
  }

  Future<void> _setNotifications(bool val) async {
    final updated = _profile!.copyWith(notificationsEnabled: val);
    await _profileSvc.save(updated);
    setState(() => _profile = updated);
  }

  Future<void> _editBackendUrl() async {
    final ctrl = TextEditingController(text: _backendUrl);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CP.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Backend URL',
            style: TextStyle(color: CP.text, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: CP.text),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'http://192.168.x.x:8000',
            hintStyle: CP.label(),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: CP.stroke)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: CP.lavender)),
            filled: true,
            fillColor: CP.card2,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: CP.sub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: CP.lavender,
                foregroundColor: CP.lavenderDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('backend_url', ctrl.text.trim());
              if (mounted) setState(() => _backendUrl = ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await _confirm(
      'Clear scan history?',
      'This will permanently delete all scan records from this device.',
      destructive: true,
    );
    if (!confirmed) return;
    await HistoryService().clearHistory();
    if (mounted) _showSnack('Scan history cleared');
  }

  Future<void> _clearAllData() async {
    final confirmed = await _confirm(
      'Delete all data?',
      'Resets the entire app to factory defaults. Cannot be undone.',
      destructive: true,
    );
    if (!confirmed) return;
    await _profileSvc.clearAllData();
    if (mounted) _showSnack('All data cleared. Restart the app.');
  }

  Future<bool> _confirm(String title, String body,
      {bool destructive = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CP.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title:
            Text(title, style: TextStyle(color: CP.text, fontWeight: FontWeight.w700)),
        content: Text(body, style: CP.label(size: 14, color: CP.sub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: CP.sub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: destructive ? CP.red : CP.lavender,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(destructive ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: CP.card2));
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const Scaffold(
        backgroundColor: CP.bg,
        body: Center(child: CircularProgressIndicator(color: CP.lavender)),
      );
    }
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top bar ──────────────────────────────────────────────
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.2))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: CP.sub, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Settings',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                ],
              ),

              const SizedBox(height: 28),

              // ── Notifications ─────────────────────────────────────────
              _sectionHeader('Notifications'),
              _settingsCard([
                _toggleRow(
                  Icons.notifications_rounded,
                  'Daily summary',
                  'Morning digest of your finance health',
                  CP.lavender,
                  _profile!.notificationsEnabled,
                  _setNotifications,
                ),
              ]),

              const SizedBox(height: 20),

              // ── Privacy ───────────────────────────────────────────────
              _sectionHeader('Privacy'),
              _settingsCard([
                _infoRow(
                  Icons.lock_outline_rounded,
                  'Data encryption',
                  'All local data is encrypted by iOS Secure Enclave',
                  CP.lime,
                  trailing: _chip('Active', CP.lime),
                ),
                _infoRow(
                  Icons.cloud_off_rounded,
                  'No cloud sync',
                  'Nothing leaves your device',
                  CP.sub,
                  trailing: _chip('Local only', CP.sub),
                ),
                _infoRow(
                  Icons.fingerprint_rounded,
                  'Biometric lock',
                  'Face ID / Touch ID support coming soon',
                  CP.lavender,
                  trailing: _chip('Soon', CP.lavender),
                ),
              ]),

              const SizedBox(height: 20),

              // ── Backend ───────────────────────────────────────────────
              _sectionHeader('Backend (Finance AI)'),
              _settingsCard([
                _tapRow(
                  Icons.dns_rounded,
                  'Server URL',
                  _backendUrl,
                  CP.lavender,
                  _editBackendUrl,
                ),
                _infoRow(
                  Icons.info_outline_rounded,
                  'Required for PDF analysis',
                  'Currency detection works fully offline',
                  CP.sub,
                ),
              ]),

              const SizedBox(height: 20),

              // ── About ─────────────────────────────────────────────────
              _sectionHeader('About'),
              _settingsCard([
                _infoRow(Icons.shield_rounded, 'CashGuard', 'v1.0.0', CP.lime),
                _infoRow(Icons.gavel_rounded, 'Compliance',
                    'DPDP Act 2023 · RBI guidelines', CP.sub),
                _infoRow(Icons.psychology_rounded, 'AI Model',
                    'EfficientNetB0 — on-device ONNX', CP.lavender),
              ]),

              const SizedBox(height: 20),

              // ── Data management ───────────────────────────────────────
              _sectionHeader('Data management'),
              _settingsCard([
                _tapRow(
                  Icons.history_rounded,
                  'Clear scan history',
                  'Remove all scan records',
                  CP.sub,
                  _clearHistory,
                  trailing: _chip('Irreversible', CP.red),
                ),
                _tapRow(
                  Icons.delete_forever_rounded,
                  'Delete all data',
                  'Factory reset the app',
                  CP.red,
                  _clearAllData,
                  trailing: _chip('Danger', CP.red),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: TextStyle(
                color: CP.sub,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _settingsCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          children: rows.asMap().entries.map((e) {
            final isLast = e.key == rows.length - 1;
            return Column(
              children: [
                e.value,
                if (!isLast)
                  Divider(
                      height: 1, color: CP.stroke, indent: 56, endIndent: 0),
              ],
            );
          }).toList(),
        ),
      );

  Widget _toggleRow(IconData icon, String title, String sub, Color iconColor,
      bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: CP.label(size: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: CP.lavender,
            activeTrackColor: CP.lavenderDark,
            inactiveTrackColor: CP.card2,
            inactiveThumbColor: CP.sub,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String sub, Color iconColor,
      {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: CP.label(size: 12)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _tapRow(IconData icon, String title, String sub, Color iconColor,
      VoidCallback onTap, {Widget? trailing}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style: CP.label(size: 12),
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right_rounded, color: CP.sub, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    final isLime = color == CP.lime;
    final isLavender = color == CP.lavender;
    final bg = isLime
        ? CP.limeDark.withOpacity(0.7)
        : isLavender
            ? CP.lavenderDark
            : CP.card2;
    return Container(
      width: 38, height: 38,
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 19),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
