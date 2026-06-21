import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/statement_service.dart';
import '../services/crypto_service.dart';
import '../widgets/analysing_view.dart';
import '../widgets/anim.dart';
import '../widgets/charts.dart';
import 'crypto_tax_screen.dart';
import 'invest_screen.dart';

final _inr = NumberFormat('#,##,###');
final _inrP = NumberFormat('#,##,##0.00');

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final _service = StatementService();
  final _cryptoService = CryptoService();
  StatementAnalysis _data = StatementAnalysis.demo; // placeholder until a real upload
  StatementAnalysis? _pending; // parsed result held while the loader animates
  bool _hasData = false; // becomes true only after a successful statement upload
  bool _analysing = false;
  int _segment = 0;
  bool _weekly = true;

  // Crypto state
  List<CryptoRate> _rates = [];
  bool _cryptoLoading = true;
  String? _cryptoError;
  final _cashCtrl = TextEditingController(text: '500');
  int _selectedCoin = 0;

  @override
  void initState() {
    super.initState();
    _fetchCrypto();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCrypto() async {
    setState(() { _cryptoLoading = true; _cryptoError = null; });
    try {
      final rates = await _cryptoService.fetchRates();
      if (mounted) setState(() { _rates = rates; _cryptoLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _cryptoError = 'No internet'; _cryptoLoading = false; });
    }
  }

  Future<void> _uploadStatement() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'html', 'htm'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;

    // Parse up-front (it's fast) so we can surface any error BEFORE showing
    // the loading screen. On success we hold the result and let the staged
    // loader animate for a few seconds, then reveal it via _revealAnalysis.
    StatementAnalysis result;
    try {
      result = _service.analyze(file.bytes!, file.name);
      if (result.txnCount == 0) {
        throw Exception('No transactions found. Make sure this is a bank/UPI statement.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: CP.card2,
          duration: const Duration(seconds: 5),
          content: Text(
              e.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(color: CP.text)),
        ));
      }
      return;
    }

    _pending = result;
    if (mounted) setState(() => _analysing = true);
  }

  // Called by the staged loader once all its steps have completed.
  void _revealAnalysis() {
    if (!mounted || _pending == null) return;
    setState(() {
      _data = _pending!;
      _pending = null;
      _hasData = true;
      _analysing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_analysing) return _loadingView();

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            const SizedBox(height: 24),

            // ════ EMPTY STATE — no statement uploaded yet ════════════════
            if (!_hasData) ...[
              FadeSlideIn(child: _emptyState()),
              const SizedBox(height: 20),
              FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: _cryptoSection()),
            ] else
              FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            // ════ 1. FINANCIAL SCORE HERO ════════════════════════════════
            _scoreHero(),
            const SizedBox(height: 14),

            // ════ 1b. CASH FLOW SUMMARY ══════════════════════════════════
            _cashflowCard(),
            const SizedBox(height: 20),

            // ════ 2. STAT GRID ═══════════════════════════════════════════
            Row(children: [
              _statCard('Transactions', '${_data.txnCount}',
                  Icons.receipt_long_rounded),
              const SizedBox(width: 12),
              _statCard('Avg transaction',
                  '₹${_inr.format(_data.avgTransaction.round())}',
                  Icons.bar_chart_rounded),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _statCard('Person transfers',
                  '₹${_inr.format(_data.personTransfers.round())}',
                  Icons.swap_horiz_rounded),
              const SizedBox(width: 12),
              _statCard('Merchant spend',
                  '₹${_inr.format(_data.merchantSpend.round())}',
                  Icons.storefront_rounded),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _statCard('Daily avg spend',
                  '₹${_inr.format(_data.dailyAvgSpend.round())}',
                  Icons.today_rounded),
              const SizedBox(width: 12),
              _statCard('Largest expense',
                  '₹${_inr.format(_data.largestExpenseAmount.round())}',
                  Icons.north_east_rounded),
            ]),

            const SizedBox(height: 26),

            // ════ 3. TOTAL SAVING CHART (CashPilot columns) ═══════════════
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total saving', style: CP.label(size: 14)),
                    const SizedBox(height: 4),
                    Text('₹ ${_inr.format(_data.totalSaving.round())}',
                        style: CP.display(size: 36)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PillChip(_weekly ? 'Weekly' : 'Monthly',
                        trailing: Icons.keyboard_arrow_down_rounded,
                        onTap: () => setState(() => _weekly = !_weekly)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _legendDot(CP.lavender, 'Income'),
                      const SizedBox(width: 10),
                      _legendDot(const Color(0xFF7BC950), 'Spend'),
                    ]),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
              decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: CP.stroke),
              ),
              child: TrendAreaChart(
                labels: _trend.map((m) => m.name).toList(),
                incomes: _trend.map((m) => m.income).toList(),
                spends: _trend.map((m) => m.spend).toList(),
                height: 170,
              ),
            ),

            const SizedBox(height: 28),

            // ════ 4. SPEND BREAKDOWN DONUT ═══════════════════════════════
            Text('Spend breakdown',
                style: TextStyle(
                    color: CP.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: CP.stroke),
              ),
              child: Row(
                children: [
                  AnimatedDonut(
                    size: 140,
                    stroke: 22,
                    values:
                        _data.categories.map((c) => c.amount).toList(),
                    colors: chartColors,
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹${_inr.format(_data.totalSpend.round())}',
                            style: CP.display(size: 17)),
                        Text('spent', style: CP.label(size: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0;
                            i < _data.categories.length;
                            i++) ...[
                          Row(
                            children: [
                              Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                      color: chartColors[
                                          i % chartColors.length],
                                      borderRadius:
                                          BorderRadius.circular(3))),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_data.categories[i].name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: CP.text,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500)),
                              ),
                              Text(
                                  '${_data.categories[i].pct.round()}%',
                                  style: CP.label(size: 12)),
                            ],
                          ),
                          if (i != _data.categories.length - 1)
                            const SizedBox(height: 9),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            // ════ 4b. RECURRING PAYMENTS ═════════════════════════════════
            if (_data.recurringPayments.isNotEmpty) ...[
              _recurringCard(),
              const SizedBox(height: 26),
            ],

            // ════ 5. RISK FLAGS ══════════════════════════════════════════
            if (_data.riskFlags.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: CP.lime,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Risk to savings',
                            style: TextStyle(
                                color: CP.limeDark,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                              color: CP.red, shape: BoxShape.circle),
                          child: Center(
                            child: Text('${_data.riskFlags.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._data.riskFlags.take(4).map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  color: CP.limeDark.withOpacity(0.8),
                                  size: 15),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(f,
                                    style: TextStyle(
                                        color:
                                            CP.limeDark.withOpacity(0.85),
                                        fontSize: 13,
                                        height: 1.4)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 26),
            ],

            // ════ 6. SEGMENTED: Categories / Ledger / People ═════════════
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: CP.stroke),
              ),
              child: Row(children: [
                _segBtn('Categories', 0),
                _segBtn('Ledger', 1),
                _segBtn('People', 2),
              ]),
            ),
            const SizedBox(height: 18),

            if (_segment == 0)
              for (int i = 0; i < _data.categories.length; i++)
                _categoryRow(_data.categories[i], i)
            else if (_segment == 1)
              ..._data.ledger.take(15).map(_ledgerRow)
            else
              ..._topRecipientRows(),

            // ════ 7. INSIGHTS ════════════════════════════════════════════
            if (_data.insights.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('AI insights',
                  style: TextStyle(
                      color: CP.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
              const SizedBox(height: 14),
              ..._data.insights.take(4).map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CP.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: CP.stroke),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: CP.lavender, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(i,
                                style: TextStyle(
                                    color: CP.text,
                                    fontSize: 13,
                                    height: 1.5)),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],

            // ════ 8. MARKETS & TOOLS (crypto, invest, tax) ═══════════════
            const SizedBox(height: 30),
            Container(height: 1, color: CP.stroke),
            const SizedBox(height: 22),
            _cryptoSection(),
                  ],
                ),
              ), // end of "has data" branch
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  Widget _topBar() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: (_hasData && _data.accountHolder.isNotEmpty)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_greeting()},', style: CP.label(size: 13)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(_data.accountHolder,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: CP.text,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6)),
                          ),
                          const SizedBox(width: 6),
                          const Text('👋', style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ],
                  )
                : Text('Finance',
                    style: TextStyle(
                        color: CP.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          // Only offer "Re-upload" once data exists; the empty state has its
          // own primary upload button.
          if (_hasData)
            PillChip('Re-upload',
                filled: true,
                trailing: Icons.upload_file_rounded,
                onTap: _uploadStatement),
        ],
      );

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Cash-flow summary: money in vs out, animated bar, net result ───────
  Widget _cashflowCard() {
    final inAmt = _data.totalIncome;
    final outAmt = _data.totalSpend;
    final net = inAmt - outAmt;
    final total = (inAmt + outAmt) <= 0 ? 1.0 : (inAmt + outAmt);
    final inFrac = (inAmt / total).clamp(0.04, 0.96);
    final netGood = net >= 0;
    final netColor = netGood ? const Color(0xFF7BC950) : CP.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CP.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CP.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Cash flow',
                style: TextStyle(
                    color: CP.text, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                  color: netColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(100)),
              child: Text(
                  '${netGood ? '+' : '-'}₹${_inr.format(net.abs().round())} ${netGood ? 'saved' : 'over'}',
                  style: TextStyle(
                      color: netColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 18),
          // dual-tone bar (in vs out)
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: inFrac.toDouble()),
              duration: const Duration(milliseconds: 950),
              curve: Curves.easeOutCubic,
              builder: (_, f, __) {
                final inFlex = (f * 1000).round().clamp(1, 999);
                return Row(children: [
                  Expanded(
                    flex: inFlex,
                    child: Container(
                        height: 12, color: const Color(0xFF7BC950)),
                  ),
                  Expanded(
                    flex: (1000 - inFlex).clamp(1, 999),
                    child: Container(height: 12, color: CP.lavender),
                  ),
                ]);
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _flowLegend(const Color(0xFF7BC950), 'Money in', inAmt),
            const SizedBox(width: 14),
            _flowLegend(CP.lavender, 'Money out', outAmt),
          ]),
        ],
      ),
    );
  }

  Widget _flowLegend(Color c, String label, double amt) => Expanded(
        child: Row(
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: CP.label(size: 11.5)),
                  const SizedBox(height: 1),
                  CountUp(
                    value: amt,
                    builder: (v) => Text('₹${_inr.format(v.round())}',
                        style: TextStyle(
                            color: CP.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Recurring payments / subscriptions ─────────────────────────────────
  Widget _recurringCard() => Container(
        width: double.infinity,
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: CP.lavender.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.autorenew_rounded,
                    color: CP.lavender, size: 18),
              ),
              const SizedBox(width: 12),
              Text('Recurring payments',
                  style: TextStyle(
                      color: CP.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${_data.recurringPayments.length}',
                  style: CP.display(size: 18)),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Text('Likely subscriptions — review what you still use',
                  style: CP.label(size: 11.5)),
            ),
            const SizedBox(height: 14),
            ..._data.recurringPayments.take(5).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.fiber_manual_record,
                        color: CP.lavender, size: 7),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(r,
                          style: TextStyle(
                              color: CP.sub, fontSize: 13, height: 1.3)),
                    ),
                  ]),
                )),
          ],
        ),
      );

  // Shown until the user uploads a statement — invites the upload and makes
  // the on-device privacy promise explicit (no demo numbers masquerading as
  // the user's own data).
  Widget _emptyState() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CP.stroke),
        ),
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: CP.lavender.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_rounded,
                  color: CP.lavender, size: 30),
            ),
            const SizedBox(height: 20),
            Text('See your financial health',
                style: TextStyle(
                    color: CP.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            const SizedBox(height: 8),
            Text(
              'Upload a bank or UPI statement (PDF) to get your health '
              'score, spending breakdown, risk flags and personalised insights.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CP.sub, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _uploadStatement,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: CP.lavender,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.upload_file_rounded,
                      color: CP.lavenderDark, size: 18),
                  const SizedBox(width: 8),
                  Text('Upload statement',
                      style: TextStyle(
                          color: CP.lavenderDark,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_rounded, color: CP.sub, size: 13),
              const SizedBox(width: 6),
              Text('100% on-device · nothing leaves your phone',
                  style: TextStyle(
                      color: CP.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      );

  Widget _scoreHero() {
    final score = _data.healthScore;
    final good = score >= 70;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CP.lime,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Financial health score',
                  style: TextStyle(
                      color: CP.limeDark.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                    color: good ? const Color(0xFF3F6B33) : CP.red,
                    borderRadius: BorderRadius.circular(100)),
                child: Text(good ? 'Healthy' : 'Needs work',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GaugeRing(
                value: score / 100,
                size: 132,
                stroke: 13,
                gradient: score >= 70
                    ? const [Color(0xFF3F6B33), Color(0xFF7BC950)]
                    : score >= 45
                        ? const [Color(0xFF8A6D1F), Color(0xFFE8C547)]
                        : const [Color(0xFF8A2A1A), Color(0xFFFF6A4D)],
                track: CP.limeDark.withOpacity(0.10),
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CountUp(
                      value: score.toDouble(),
                      builder: (v) => Text('${v.round()}',
                          style: CP.display(size: 40, color: CP.limeDark)),
                    ),
                    Text('/ 100',
                        style: TextStyle(
                            color: CP.limeDark.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroMetric(
                      'Savings rate',
                      CountUp(
                        value: _data.savingsRate * 100,
                        builder: (v) => Text('${v.toStringAsFixed(1)}%',
                            style: CP.display(size: 26, color: CP.limeDark)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _heroMetric(
                      'Net this period',
                      CountUp(
                        value: _data.totalSaving,
                        builder: (v) => Text(
                            '${v >= 0 ? '+' : '-'}₹${_inr.format(v.abs().round())}',
                            style: CP.display(size: 22, color: CP.limeDark)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_data.isDemo) ...[
            const SizedBox(height: 12),
            Text(_coverageLine(),
                style: TextStyle(
                    color: CP.limeDark.withOpacity(0.7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            if (_data.transfersExcluded > 0 || _data.investments > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(_exclusionLine(),
                    style: TextStyle(
                        color: CP.limeDark.withOpacity(0.6),
                        fontSize: 11)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _heroMetric(String label, Widget value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: CP.limeDark.withOpacity(0.6), fontSize: 12)),
          const SizedBox(height: 1),
          value,
        ],
      );

  String _coverageLine() {
    final span = _data.monthsCovered >= 2
        ? '${_data.monthsCovered} months'
        : '${_data.periodDays} day${_data.periodDays == 1 ? '' : 's'}';
    return 'Based on $span · ${_data.scoreConfidence}% data confidence';
  }

  String _exclusionLine() {
    final parts = <String>[];
    if (_data.investments > 0) {
      parts.add('₹${_inr.format(_data.investments.round())} invested (saved)');
    }
    if (_data.transfersExcluded > 0) {
      parts.add('₹${_inr.format(_data.transfersExcluded.round())} transfers excluded');
    }
    return parts.join('  ·  ');
  }

  Widget _statCard(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CP.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CP.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: CP.lavender, size: 18),
              const SizedBox(height: 10),
              Text(value,
                  style: CP.display(size: 19),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(label, style: CP.label(size: 11.5)),
            ],
          ),
        ),
      );

  Widget _legendDot(Color c, String label, {bool border = false}) => Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: border
                      ? Border.all(color: CP.sub, width: 1)
                      : null)),
          const SizedBox(width: 5),
          Text(label, style: CP.label(size: 12, color: CP.text)),
        ],
      );

  List<MonthTrend> get _trend {
    final list = _weekly ? _data.weeks : _data.months;
    return list.length > 6 ? list.sublist(list.length - 6) : list;
  }

  Widget _segBtn(String label, int i) {
    final active = _segment == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _segment = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? CP.lavender : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: active ? CP.lavenderDark : CP.sub,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _categoryRow(CategorySpend c, int i) {
    final color = chartColors[i % chartColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(categoryIcon(c.name), color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: TextStyle(
                            color: CP.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${c.txns} transaction${c.txns == 1 ? '' : 's'}',
                        style: CP.label(size: 12.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('-₹${_inrP.format(c.amount)}',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${c.pct.round()}%', style: CP.label(size: 12.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 11),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: GrowBar(
              fraction: (c.pct / 100).clamp(0.0, 1.0),
              color: color,
              trackColor: CP.card2,
              height: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledgerRow(TxnEntry t) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: t.isDebit
                      ? CP.card2
                      : CP.lime.withOpacity(0.2),
                  shape: BoxShape.circle),
              child: Icon(
                  t.isDebit
                      ? Icons.arrow_outward_rounded
                      : Icons.arrow_downward_rounded,
                  color: t.isDebit ? CP.text : const Color(0xFF7BC950),
                  size: 18),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${t.date}  ·  ${t.category}',
                      style: CP.label(size: 11.5)),
                ],
              ),
            ),
            Text(
                '${t.isDebit ? '-' : '+'}₹${_inrP.format(t.amount)}',
                style: TextStyle(
                    color: t.isDebit ? CP.text : const Color(0xFF7BC950),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  List<Widget> _topRecipientRows() {
    final maxTotal = _data.topRecipients.isEmpty
        ? 1.0
        : _data.topRecipients.first.total;
    return [
      for (int i = 0; i < _data.topRecipients.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${i + 1}',
                      style: CP.display(size: 16, color: CP.sub)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_data.topRecipients[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: CP.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text(
                      '₹${_inr.format(_data.topRecipients[i].total.round())}  ·  ${_data.topRecipients[i].count}×',
                      style: CP.label(size: 12.5, color: CP.text)),
                ],
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _data.topRecipients[i].total / maxTotal,
                    minHeight: 5,
                    backgroundColor: CP.card2,
                    valueColor: AlwaysStoppedAnimation(
                        chartColors[i % chartColors.length]),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _cryptoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text('Crypto rates',
                style: TextStyle(
                    color: CP.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
            const Spacer(),
            if (!_cryptoLoading)
              GestureDetector(
                onTap: _fetchCrypto,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: CP.stroke)),
                  child: const Icon(Icons.refresh_rounded, color: CP.sub, size: 18),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        if (_cryptoLoading)
          Container(
            height: 90,
            decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CP.stroke)),
            child: const Center(
                child: CircularProgressIndicator(color: CP.lavender, strokeWidth: 2)),
          )
        else if (_cryptoError != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: CP.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CP.stroke)),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded, color: CP.sub, size: 20),
              const SizedBox(width: 12),
              Text('Could not load rates — check connection',
                  style: CP.label(size: 13)),
              const Spacer(),
              GestureDetector(
                onTap: _fetchCrypto,
                child: Text('Retry', style: TextStyle(color: CP.lavender, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ]),
          )
        else ...[
          // Horizontal scrollable coin row
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _rates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => FadeSlideIn(
                delay: Duration(milliseconds: 60 * i),
                child: _coinCard(_rates[i], i),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Cash → Crypto converter
          Container(
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
                  const Icon(Icons.currency_exchange_rounded, color: CP.lavender, size: 16),
                  const SizedBox(width: 8),
                  Text('Cash → Crypto calculator',
                      style: TextStyle(color: CP.text, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // INR input
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: CP.card2,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Text('₹ ', style: TextStyle(color: CP.sub, fontSize: 15, fontWeight: FontWeight.w600)),
                          Expanded(
                            child: TextField(
                              controller: _cashCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: CP.text, fontSize: 15, fontWeight: FontWeight.w700),
                              decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, color: CP.sub, size: 20),
                    const SizedBox(width: 10),
                    // Result
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: CP.lavenderDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: CP.lavender.withOpacity(0.3))),
                        child: _buildConverterResult(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Coin selector chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < _rates.length; i++) ...[
                        GestureDetector(
                          onTap: () => setState(() => _selectedCoin = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedCoin == i ? CP.lavender : CP.card2,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(_rates[i].symbol,
                                style: TextStyle(
                                    color: _selectedCoin == i ? CP.lavenderDark : CP.sub,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        if (i != _rates.length - 1) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _investEntry(),
          const SizedBox(height: 12),
          _taxEstimatorEntry(),
        ],
      ],
    );
  }

  Widget _investEntry() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const InvestScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CP.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: const Color(0xFF9FE870).withOpacity(0.16),
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.trending_up_rounded,
                  color: Color(0xFF9FE870), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invest',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Stocks & crypto · tips and advice',
                      style: CP.label(size: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CP.sub),
          ],
        ),
      ),
    );
  }

  Widget _taxEstimatorEntry() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CryptoTaxScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CP.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: CP.lavender.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.receipt_long_rounded,
                  color: CP.lavender, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Crypto tax estimator',
                      style: TextStyle(
                          color: CP.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('India · 30% + 1% TDS', style: CP.label(size: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CP.sub),
          ],
        ),
      ),
    );
  }

  Widget _coinCard(CryptoRate r, int i) {
    final up = r.change24h >= 0;
    final isSelected = _selectedCoin == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedCoin = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 130,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? CP.lavenderDark : CP.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? CP.lavender.withOpacity(0.5) : CP.stroke,
              width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(r.emoji,
                  style: TextStyle(fontSize: 18, color: isSelected ? CP.lavender : CP.text)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: up ? const Color(0xFF7BC950).withOpacity(0.15) : CP.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(100)),
                child: Text('${up ? '+' : ''}${r.change24h.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: up ? const Color(0xFF7BC950) : CP.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const Spacer(),
            Text(r.symbol, style: CP.label(size: 11)),
            const SizedBox(height: 2),
            Text('₹${_formatCryptoPrice(r.priceInr)}',
                style: TextStyle(
                    color: isSelected ? CP.lavender : CP.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildConverterResult() {
    final inrText = _cashCtrl.text.trim();
    final inrVal = double.tryParse(inrText.replaceAll(',', '')) ?? 0;
    if (_rates.isEmpty || _selectedCoin >= _rates.length) {
      return Text('—', style: TextStyle(color: CP.sub));
    }
    final rate = _rates[_selectedCoin];
    final cryptoAmt = rate.priceInr > 0 ? inrVal / rate.priceInr : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${_formatCryptoAmt(cryptoAmt)} ${rate.symbol}',
            style: TextStyle(
                color: CP.lavender, fontSize: 14, fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis),
        Text(rate.name, style: CP.label(size: 11)),
      ],
    );
  }

  String _formatCryptoPrice(double p) {
    if (p >= 1000000) return '${(p / 100000).toStringAsFixed(1)}L';
    if (p >= 1000) return _inr.format(p.round());
    return p.toStringAsFixed(2);
  }

  String _formatCryptoAmt(double a) {
    if (a == 0) return '0';
    if (a >= 1) return a.toStringAsFixed(4);
    if (a >= 0.0001) return a.toStringAsFixed(6);
    return a.toStringAsExponential(3);
  }

  Widget _loadingView() => SafeArea(
        child: AnalysingView(
          title: 'Analysing statement',
          icon: Icons.description_rounded,
          stepDuration: const Duration(milliseconds: 650),
          onComplete: _revealAnalysis,
          steps: const [
            'Reading PDF & extracting text',
            'Identifying debits & credits',
            'Categorising transactions',
            'Detecting recurring & risk patterns',
            'Scoring financial health',
          ],
        ),
      );
}
