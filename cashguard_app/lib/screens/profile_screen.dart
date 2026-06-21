import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/profile_service.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _svc = ProfileService();
  ProfileData? _profile;
  ScanStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _svc.load();
    final s = await _svc.loadStats();
    if (mounted) setState(() { _profile = p; _stats = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CP.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: CP.lavender))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final p = _profile!;
    final s = _stats!;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      color: CP.lime, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.shield_rounded, color: CP.limeDark, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Profile', style: TextStyle(color: CP.text, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _load()),
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2))),
                    child: const Icon(Icons.settings_rounded, color: CP.sub, size: 20),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Avatar + name hero ────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: CP.stroke),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _editName,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 80, height: 80,
                          decoration: const BoxDecoration(
                              color: CP.lavenderDark, shape: BoxShape.circle),
                          child: Center(
                            child: Text(p.avatarEmoji ?? '🛡️',
                                style: const TextStyle(fontSize: 36)),
                          ),
                        ),
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                              color: CP.lavender, shape: BoxShape.circle),
                          child: const Icon(Icons.edit_rounded,
                              color: CP.lavenderDark, size: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(p.displayName, style: CP.display(size: 22)),
                  const SizedBox(height: 4),
                  Text('Member since ${_formatDate(p.joinedAt)}',
                      style: CP.label(size: 13)),
                  const SizedBox(height: 18),
                  // Privacy badge row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _badge(Icons.lock_rounded, 'Local only', CP.lime, CP.limeDark),
                      const SizedBox(width: 8),
                      _badge(Icons.shield_rounded, 'No tracking', CP.lavender, CP.lavenderDark),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Stats row ─────────────────────────────────────────────
            Text('Your activity', style: TextStyle(
                color: CP.text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _statCard('${s.total}', 'Total scans', Icons.document_scanner_rounded, CP.card)),
                const SizedBox(width: 12),
                Expanded(child: _statCard('${s.genuine}', 'Genuine', Icons.check_circle_rounded, CP.lime, textColor: CP.limeDark)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statCard('${s.fake}', 'Fakes caught', Icons.gpp_bad_rounded, CP.red.withOpacity(0.12))),
                const SizedBox(width: 12),
                Expanded(child: _statCard(
                    s.total == 0 ? '—' : '${(s.avgConfidence * 100).toStringAsFixed(0)}%',
                    'Avg confidence', Icons.analytics_rounded, CP.card2)),
              ],
            ),

            const SizedBox(height: 28),

            // ── Achievements ──────────────────────────────────────────
            Text('Achievements', style: TextStyle(
                color: CP.text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 14),

            _achievement('First scan', 'Completed your first currency check',
                Icons.qr_code_scanner_rounded, s.total >= 1),
            _achievement('Hawk Eye', 'Caught 3 or more fake notes',
                Icons.gpp_bad_rounded, s.fake >= 3),
            _achievement('Trusted Verifier', 'Scanned 10+ notes',
                Icons.verified_rounded, s.total >= 10),
            _achievement('Guardian', 'Scanned 50+ notes',
                Icons.shield_moon_rounded, s.total >= 50),
            _achievement('Currency Pro', '95%+ average confidence',
                Icons.star_rounded, s.avgConfidence >= 0.95 && s.total > 0),

            const SizedBox(height: 28),

            // ── Privacy notice ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CP.limeDark.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CP.lime.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.privacy_tip_rounded, color: CP.lime, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('100% Private', style: TextStyle(
                            color: CP.lime, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('All scan data is stored on-device only. '
                            'No images, results, or personal data are sent to any server. '
                            'Compliant with DPDP Act 2023.',
                            style: CP.label(size: 12, color: CP.lime.withOpacity(0.7))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: bg.withOpacity(0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: bg.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: bg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: bg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color bg,
      {Color textColor = CP.text}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20),
          border: bg == CP.card || bg == CP.card2
              ? Border.all(color: CP.stroke)
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor.withOpacity(0.7), size: 20),
          const SizedBox(height: 10),
          Text(value, style: CP.display(size: 26, color: textColor)),
          const SizedBox(height: 2),
          Text(label, style: CP.label(size: 12,
              color: textColor == CP.limeDark ? CP.limeDark.withOpacity(0.6) : CP.sub)),
        ],
      ),
    );
  }

  Widget _achievement(String title, String desc, IconData icon, bool unlocked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unlocked ? CP.lavenderDark.withOpacity(0.6) : CP.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: unlocked ? CP.lavender.withOpacity(0.4) : CP.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: unlocked ? CP.lavender.withOpacity(0.2) : CP.card2,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon,
                color: unlocked ? CP.lavender : CP.sub, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    color: unlocked ? CP.text : CP.sub,
                    fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(desc, style: CP.label(size: 12)),
              ],
            ),
          ),
          Icon(unlocked ? Icons.verified_rounded : Icons.lock_rounded,
              color: unlocked ? CP.lavender : CP.sub.withOpacity(0.4), size: 20),
        ],
      ),
    );
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _profile?.displayName);
    final emojis = ['🛡️', '💰', '🔍', '👁️', '🏦', '💎', '🔐', '⚡'];
    String selected = _profile?.avatarEmoji ?? '🛡️';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: CP.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Edit Profile', style: TextStyle(color: CP.text, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // emoji picker
              Wrap(
                spacing: 10, runSpacing: 10,
                children: emojis.map((e) => GestureDetector(
                  onTap: () => setS(() => selected = e),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: selected == e ? CP.lavender.withOpacity(0.2) : CP.card2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected == e ? CP.lavender : Colors.transparent,
                          width: 2),
                    ),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: ctrl,
                style: TextStyle(color: CP.text),
                decoration: InputDecoration(
                  labelText: 'Display name',
                  labelStyle: CP.label(),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: CP.sub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: CP.lavender,
                  foregroundColor: CP.lavenderDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final updated = _profile!.copyWith(
                  displayName: ctrl.text.trim().isEmpty ? _profile!.displayName : ctrl.text.trim(),
                  avatarEmoji: selected,
                );
                await _svc.save(updated);
                if (mounted) setState(() => _profile = updated);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];
}
