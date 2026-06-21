import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

final _inr = NumberFormat('#,##,##0.##');
const _green = Color(0xFF7BC950);

// India Virtual Digital Asset tax (Income Tax Act):
//   • Section 115BBH — flat 30% on gains, no deductions except cost,
//     no loss set-off or carry-forward.
//   • + 4% health & education cess  → effective 31.2%.
//   • Section 194S — 1% TDS on the sale consideration.
class CryptoTaxScreen extends StatefulWidget {
  const CryptoTaxScreen({super.key});

  @override
  State<CryptoTaxScreen> createState() => _CryptoTaxScreenState();
}

class _CryptoTaxScreenState extends State<CryptoTaxScreen> {
  final _buyCtrl = TextEditingController();
  final _sellCtrl = TextEditingController();

  double get _buy => double.tryParse(_buyCtrl.text.replaceAll(',', '')) ?? 0;
  double get _sell => double.tryParse(_sellCtrl.text.replaceAll(',', '')) ?? 0;

  double get _gain => _sell - _buy;
  double get _taxableGain => _gain > 0 ? _gain : 0;
  double get _tax => _taxableGain * 0.30;
  double get _cess => _tax * 0.04;
  double get _totalTax => _tax + _cess;
  double get _tds => _sell * 0.01;
  double get _takeHome => _sell - _totalTax;

  bool get _hasInput => _buy > 0 || _sell > 0;
  bool get _isLoss => _hasInput && _gain < 0;

  @override
  void dispose() {
    _buyCtrl.dispose();
    _sellCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: CP.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: CP.stroke)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: CP.text, size: 17),
                  ),
                ),
                const SizedBox(width: 14),
                Text('Crypto tax estimator',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Text('India · Section 115BBH + 194S',
                      style: CP.label(size: 13)),
                  const SizedBox(height: 16),

                  // ── Inputs ──────────────────────────────────────────────
                  Row(children: [
                    Expanded(
                        child: _inputBox(
                            'You bought for', _buyCtrl, Icons.south_west_rounded)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _inputBox('You sold for', _sellCtrl,
                            Icons.north_east_rounded)),
                  ]),

                  const SizedBox(height: 20),

                  // ── Hero result ─────────────────────────────────────────
                  _heroCard(),

                  const SizedBox(height: 14),

                  // ── Breakdown ───────────────────────────────────────────
                  _breakdownCard(),

                  const SizedBox(height: 14),

                  // ── Rules ───────────────────────────────────────────────
                  _rulesCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input field ───────────────────────────────────────────────────────
  Widget _inputBox(String label, TextEditingController ctrl, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: CP.sub, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis, style: CP.label(size: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('₹ ',
                style: TextStyle(
                    color: CP.sub, fontSize: 18, fontWeight: FontWeight.w600)),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: CP.display(size: 22),
                cursorColor: CP.lavender,
                decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Hero card — total tax ──────────────────────────────────────────────
  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CP.lavender,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated tax payable',
              style: TextStyle(
                  color: CP.lavenderDark.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('₹${_inr.format(_totalTax)}',
              style: CP.display(size: 44, color: CP.lavenderDark)),
          const SizedBox(height: 6),
          Text(
              _isLoss
                  ? 'No tax — sold at a loss'
                  : '31.2% of your ₹${_inr.format(_taxableGain)} gain',
              style: TextStyle(
                  color: CP.lavenderDark.withOpacity(0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          if (_hasInput) ...[
            const SizedBox(height: 18),
            _proportionBar(),
          ],
        ],
      ),
    );
  }

  // Take-home vs tax bar (proportion of sale value)
  Widget _proportionBar() {
    final keep = _takeHome.clamp(0, double.infinity);
    final tax = _totalTax;
    final total = (keep + tax);
    final keepFlex = total <= 0 ? 1 : (keep / total * 1000).round().clamp(1, 1000);
    final taxFlex = total <= 0 ? 0 : (tax / total * 1000).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Row(children: [
            Expanded(
              flex: keepFlex,
              child: Container(height: 10, color: CP.lavenderDark),
            ),
            if (taxFlex > 0) const SizedBox(width: 3),
            if (taxFlex > 0)
              Expanded(
                flex: taxFlex,
                child: Container(
                    height: 10, color: CP.lavenderDark.withOpacity(0.35)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _legendDot(CP.lavenderDark, 'You keep ₹${_inr.format(keep)}'),
          const SizedBox(width: 16),
          _legendDot(CP.lavenderDark.withOpacity(0.35),
              'Tax ₹${_inr.format(tax)}'),
        ]),
      ],
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: CP.lavenderDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      );

  // ── Breakdown card ─────────────────────────────────────────────────────
  Widget _breakdownCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        children: [
          _row('Capital gain', _gain,
              valueColor: _isLoss ? CP.red : CP.text, signed: true),
          _divider(),
          _row('Tax @ 30%', _tax),
          _row('Health & education cess @ 4%', _cess),
          _divider(),
          _row('Total tax payable', _totalTax, bold: true),
          _divider(),
          _row('1% TDS on sale (Sec 194S)', _tds,
              caption: 'Deducted by the exchange · adjustable against tax'),
          _divider(),
          _row('You keep after tax', _takeHome,
              bold: true, valueColor: _green),
        ],
      ),
    );
  }

  Widget _row(String label, double value,
      {bool bold = false,
      Color? valueColor,
      bool signed = false,
      String? caption}) {
    final prefix = signed && value < 0 ? '–₹' : '₹';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: bold ? CP.text : CP.sub,
                        fontSize: 14,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(caption, style: CP.label(size: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('$prefix${_inr.format(value.abs())}',
              style: TextStyle(
                  color: valueColor ?? CP.text,
                  fontSize: bold ? 17 : 15,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _divider() => Divider(color: CP.stroke, height: 1);

  // ── Rules / disclaimer ─────────────────────────────────────────────────
  Widget _rulesCard() {
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                      color: CP.lavender, shape: BoxShape.circle)),
            ),
            Expanded(
                child: Text(t,
                    style: CP.label(size: 12, color: CP.sub),
                    )),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded, color: CP.lavender, size: 16),
            const SizedBox(width: 8),
            Text('How India taxes crypto',
                style: TextStyle(
                    color: CP.text, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          bullet('Flat 30% tax on gains from Virtual Digital Assets — plus 4% cess (effective 31.2%).'),
          bullet('No deductions allowed except your cost of acquisition.'),
          bullet('Losses can’t be set off against other income or carried forward.'),
          bullet('1% TDS applies on the sale value and is adjustable against your final tax.'),
          const SizedBox(height: 6),
          Text('Estimate only — not tax advice. Consult a professional.',
              style: CP.label(size: 11, color: CP.sub.withOpacity(0.7))),
        ],
      ),
    );
  }
}
