import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/asset.dart';
import '../services/invest_service.dart';

final _money = NumberFormat('#,##0.##');

const _accounts = ['Santander', 'HDFC Bank', 'Cash wallet'];
const _available = 21241.0;

/// Buy screen — giant amount entry with custom numeric keypad.
/// Simulated paper-trade: "Preview order" records a local holding only.
class BuyScreen extends StatefulWidget {
  final Asset asset;
  const BuyScreen({super.key, required this.asset});

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  String _amount = '142';
  String _account = _accounts.first;
  final _svc = InvestService();

  double get _value => double.tryParse(_amount) ?? 0;
  double get _shares => widget.asset.price == 0 ? 0 : _value / widget.asset.price;

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '<') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
        if (_amount.isEmpty) _amount = '0';
      } else if (k == '.') {
        if (!_amount.contains('.')) _amount += '.';
      } else {
        if (_amount == '0') {
          _amount = k;
        } else {
          // limit length & 2 decimals
          if (_amount.contains('.')) {
            final dec = _amount.split('.')[1];
            if (dec.length >= 2) return;
          }
          if (_amount.replaceAll('.', '').length >= 7) return;
          _amount += k;
        }
      }
    });
  }

  void _preview() {
    if (_value <= 0) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _previewSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(children: [
                      const Icon(Icons.arrow_back_ios_new_rounded,
                          color: CP.text, size: 18),
                      const SizedBox(width: 8),
                      Text('Buy ${a.name}',
                          style: TextStyle(
                              color: CP.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const Spacer(),
                  const PillChip('Market order', trailing: Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),

            const SizedBox(height: 26),

            // ── Account selector ─────────────────────────────────────────
            GestureDetector(
              onTap: _pickAccount,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color: a.brandColor, shape: BoxShape.circle),
                    child: const Icon(Icons.account_balance_rounded,
                        color: Colors.white, size: 13),
                  ),
                  const SizedBox(width: 8),
                  Text(_account,
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: CP.sub, size: 20),
                ],
              ),
            ),

            const Spacer(),

            // ── Amount ───────────────────────────────────────────────────
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text('\$',
                        style: TextStyle(
                            color: CP.text,
                            fontSize: 56,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text(_amount,
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 92,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -2)),
                  // blinking cursor
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Container(width: 3, height: 64, color: CP.lavender),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            Text('~${_shares.toStringAsFixed(_shares < 1 ? 2 : 3)} shares  ·  1 ${a.ticker}=\$${_money.format(a.price)}',
                style: TextStyle(color: CP.sub, fontSize: 14)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('\$${_money.format(_available)} available',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('  ·  ', style: TextStyle(color: CP.sub)),
                GestureDetector(
                  onTap: () => setState(() => _amount = _available.toStringAsFixed(0)),
                  child: Text('Buy max',
                      style: TextStyle(
                          color: CP.lavender,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),

            const Spacer(),

            // ── Keypad ───────────────────────────────────────────────────
            _keypad(),

            const SizedBox(height: 14),

            // ── Preview order ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: GestureDetector(
                onTap: _preview,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _value > 0 ? CP.lavender : CP.card2,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Center(
                    child: Text('Preview order',
                        style: TextStyle(
                            color: _value > 0 ? CP.lavenderDark : CP.sub,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Keypad grid ───────────────────────────────────────────────────────
  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '<'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.9,
        children: keys.map((k) {
          return GestureDetector(
            onTap: () => _tap(k),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: k == '<'
                  ? const Icon(Icons.backspace_outlined, color: CP.text, size: 24)
                  : Text(k,
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _pickAccount() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: CP.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: CP.stroke, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            ..._accounts.map((acc) => ListTile(
                  leading: const Icon(Icons.account_balance_rounded,
                      color: CP.lavender),
                  title: Text(acc, style: const TextStyle(color: CP.text)),
                  trailing: acc == _account
                      ? const Icon(Icons.check_rounded, color: CP.lavender)
                      : null,
                  onTap: () {
                    setState(() => _account = acc);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Order confirmation sheet ──────────────────────────────────────────
  Widget _previewSheet() {
    final a = widget.asset;
    return Container(
      decoration: const BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: CP.stroke, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 20),
          Text('Review order', style: CP.display(size: 24)),
          const SizedBox(height: 4),
          Text('Simulated paper-trade · no real money moves',
              style: CP.label(size: 12)),
          const SizedBox(height: 20),
          _row('Asset', '${a.name} (${a.ticker})'),
          _row('Order type', 'Market order'),
          _row('Account', _account),
          _row('Amount', '\$${_money.format(_value)}'),
          _row('Est. shares', '~${_shares.toStringAsFixed(_shares < 1 ? 4 : 3)}'),
          _row('Price', '\$${_money.format(a.price)}'),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () async {
              await _svc.addHolding(Holding(
                ticker: a.ticker,
                name: a.name,
                amountUsd: _value,
                shares: _shares,
                priceAtBuy: a.price,
                boughtAt: DateTime.now(),
                account: _account,
              ));
              if (!mounted) return;
              Navigator.pop(context); // sheet
              Navigator.pop(context); // buy screen
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: CP.lavender,
                content: Text('Order placed · ${a.ticker} added to portfolio',
                    style: const TextStyle(
                        color: CP.lavenderDark, fontWeight: FontWeight.w700)),
              ));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                  color: CP.lavender, borderRadius: BorderRadius.circular(100)),
              child: const Center(
                child: Text('Confirm order',
                    style: TextStyle(
                        color: CP.lavenderDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Text(l, style: TextStyle(color: CP.sub, fontSize: 14)),
            const Spacer(),
            Text(v,
                style: const TextStyle(
                    color: CP.text, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
