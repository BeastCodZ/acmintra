import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

final _inr = NumberFormat('#,##,###');

class _Denom {
  final int value;
  final Color c1; // gradient start
  final Color c2; // gradient end
  final bool isCoin;
  const _Denom(this.value, this.c1, this.c2, {this.isCoin = false});
}

// Indian currency — colours approximate the real notes/coins
const _denoms = <_Denom>[
  _Denom(500, Color(0xFFA89F8E), Color(0xFF7C7464)),
  _Denom(200, Color(0xFFF0B44A), Color(0xFFD9912B)),
  _Denom(100, Color(0xFFB9A2E0), Color(0xFF8C6FC4)),
  _Denom(50, Color(0xFF5FBBD0), Color(0xFF3E96AC)),
  _Denom(20, Color(0xFFCBBC5A), Color(0xFFA89B3F)),
  _Denom(10, Color(0xFFBE8C66), Color(0xFF9A6A47)),
  _Denom(5, Color(0xFFD9BB6A), Color(0xFFB8923F), isCoin: true),
  _Denom(2, Color(0xFFD9BB6A), Color(0xFFB8923F), isCoin: true),
  _Denom(1, Color(0xFFD9BB6A), Color(0xFFB8923F), isCoin: true),
];

class CashCalculatorScreen extends StatefulWidget {
  const CashCalculatorScreen({super.key});

  @override
  State<CashCalculatorScreen> createState() => _CashCalculatorScreenState();
}

class _CashCalculatorScreenState extends State<CashCalculatorScreen> {
  String _entry = '';

  int get _amount => int.tryParse(_entry) ?? 0;

  // Greedy breakdown — canonical Indian denominations give the minimum count
  Map<int, int> get _breakdown {
    final map = <int, int>{};
    var rem = _amount;
    for (final d in _denoms) {
      if (rem >= d.value) {
        map[d.value] = rem ~/ d.value;
        rem %= d.value;
      }
    }
    return map;
  }

  int get _totalPieces =>
      _breakdown.values.fold(0, (s, v) => s + v);

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_entry.isNotEmpty) _entry = _entry.substring(0, _entry.length - 1);
      } else {
        final next = _entry + k;
        // cap at 10,00,000 and strip leading zeros
        final parsed = int.tryParse(next) ?? 0;
        if (parsed <= 1000000) _entry = parsed == 0 ? '' : parsed.toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _breakdown.entries.toList();
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: CP.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: CP.stroke)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: CP.text, size: 17),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Cash calculator',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_entry.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _entry = ''),
                      child: Text('Clear',
                          style: TextStyle(
                              color: CP.lavender,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),

            // ── Amount display ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Column(
                children: [
                  Text('Enter amount to break down', style: CP.label(size: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('₹',
                            style: CP.display(size: 32, color: CP.sub)),
                      ),
                      const SizedBox(width: 4),
                      Text(_entry.isEmpty ? '0' : _inr.format(_amount),
                          style: CP.display(size: 52)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_totalPieces > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: CP.lavender.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(100)),
                      child: Text('$_totalPieces piece${_totalPieces == 1 ? '' : 's'} total',
                          style: TextStyle(
                              color: CP.lavender,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),

            // ── Breakdown (the wallet) ───────────────────────────────────
            Expanded(
              child: _amount == 0
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final d = _denoms
                            .firstWhere((x) => x.value == entries[i].key);
                        return _NoteRow(denom: d, count: entries[i].value);
                      },
                    ),
            ),

            // ── Keypad ───────────────────────────────────────────────────
            _Keypad(onTap: _tap),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stacked-notes graphic
          SizedBox(
            width: 120, height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (int i = 0; i < 3; i++)
                  Transform.translate(
                    offset: Offset(0, i * -10.0),
                    child: Transform.rotate(
                      angle: (i - 1) * 0.06,
                      child: Container(
                        width: 110, height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            _denoms[i].c1.withOpacity(0.5),
                            _denoms[i].c2.withOpacity(0.5),
                          ]),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Type an amount to see the notes',
              style: CP.label(size: 14)),
          const SizedBox(height: 4),
          Text('e.g. ₹4,300 → 8×₹500 + 1×₹200 + 1×₹100',
              style: CP.label(size: 12, color: CP.sub.withOpacity(0.7))),
        ],
      ),
    );
  }
}

// ── A single denomination row — looks like a real note / coin ───────────────
class _NoteRow extends StatelessWidget {
  final _Denom denom;
  final int count;
  const _NoteRow({required this.denom, required this.count});

  @override
  Widget build(BuildContext context) {
    final subtotal = denom.value * count;
    return Row(
      children: [
        // The note / coin graphic
        denom.isCoin
            ? Container(
                width: 78, height: 54,
                alignment: Alignment.center,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [denom.c1, denom.c2]),
                    border: Border.all(color: Colors.white.withOpacity(0.25), width: 2),
                  ),
                  child: Center(
                    child: Text('₹${denom.value}',
                        style: const TextStyle(
                            color: Color(0xFF3A2E12),
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              )
            : Container(
                width: 78, height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [denom.c1, denom.c2]),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                        color: denom.c2.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Stack(
                  children: [
                    // faint corner value + RBI-ish line for realism
                    Positioned(
                      top: 5, left: 7,
                      child: Text('${denom.value}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    Center(
                      child: Text('₹${denom.value}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                    ),
                    Positioned(
                      bottom: 6, right: 7,
                      child: Container(
                        width: 18, height: 3,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
                ),
              ),
        const SizedBox(width: 14),
        // Count + math
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(denom.isCoin ? '₹${denom.value} coin' : '₹${denom.value} note',
                  style: TextStyle(
                      color: CP.text, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('$count × ₹${denom.value}', style: CP.label(size: 12)),
            ],
          ),
        ),
        // Count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
              color: CP.card2, borderRadius: BorderRadius.circular(100)),
          child: Text('×$count',
              style: TextStyle(
                  color: CP.text, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text('₹${_inr.format(subtotal)}',
              textAlign: TextAlign.right,
              style: CP.display(size: 17)),
        ),
      ],
    );
  }
}

// ── Numeric keypad ──────────────────────────────────────────────────────────
class _Keypad extends StatelessWidget {
  final void Function(String) onTap;
  const _Keypad({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', '⌫'],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in keys)
            Row(
              children: [
                for (final k in row) _key(k),
              ],
            ),
        ],
      ),
    );
  }

  Widget _key(String k) {
    final isBack = k == '⌫';
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: () => onTap(k),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isBack ? CP.card2 : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: isBack
                ? const Icon(Icons.backspace_rounded, color: CP.text, size: 22)
                : Text(k,
                    style: CP.display(size: 26, color: CP.text)),
          ),
        ),
      ),
    );
  }
}
