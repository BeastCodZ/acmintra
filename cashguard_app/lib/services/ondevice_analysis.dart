import 'dart:math';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'statement_service.dart';

/// Full on-device financial statement analyser — zero backend dependency.
/// Pipeline: PDF → parse → enrich → categorise → aggregate → score → insights
class OnDeviceAnalysis {
  // ── 1. PDF TEXT EXTRACTION ──────────────────────────────────────────────
  static String extractTextFromPdf(Uint8List bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final text = extractor.extractText();
    doc.dispose();
    return text;
  }

  // ── 2. HTML TEXT EXTRACTION ─────────────────────────────────────────────
  static String extractTextFromHtml(String html) {
    // Strip HTML tags, decode entities, preserve table structure
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</tr>'), '\n')
        .replaceAll(RegExp(r'</td>'), '\t')
        .replaceAll(RegExp(r'</th>'), '\t')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&rupee;', '₹')
        .replaceAll('₹', '₹');
    return text;
  }

  // ── 3. FULL ANALYSIS PIPELINE ──────────────────────────────────────────
  static StatementAnalysis analyse(Uint8List fileBytes, String filename) {
    final isHtml = filename.toLowerCase().endsWith('.html') ||
        filename.toLowerCase().endsWith('.htm');

    final text = isHtml
        ? extractTextFromHtml(String.fromCharCodes(fileBytes))
        : extractTextFromPdf(fileBytes);

    final transactions = _parseTransactions(text);
    if (transactions.isEmpty) {
      throw Exception('Could not parse any transactions from this file');
    }

    final enriched = transactions.map(_enrichTransaction).toList();

    final accountHolder = _extractAccountHolder(text);
    return _buildAnalysis(enriched, accountHolder: accountHolder);
  }

  // ── 4. TRANSACTION PARSING ─────────────────────────────────────────────
  static List<_RawTxn> _parseTransactions(String text) {
    final txns = <_RawTxn>[];

    // Try BHIM UPI HTML format
    txns.addAll(_parseBhimUpi(text));
    if (txns.isNotEmpty) return txns;

    // Kotak (and similar banks) whose PDFs Syncfusion extracts cell-per-line:
    // each table cell is on its own line, so date / narration / amount / balance
    // all appear as separate lines within a single transaction block.
    if (text.contains('Withdrawal (Dr.)') || text.contains('Deposit (Cr.)')) {
      txns.addAll(_parseCellPerLine(text));
      if (txns.isNotEmpty) return txns;
    }

    // Try standard bank statement formats (date + amounts on same line)
    txns.addAll(_parseBankStatement(text));
    if (txns.isNotEmpty) return txns;

    // Fallback: line-by-line amount extraction
    txns.addAll(_parseGenericLines(text));
    return txns;
  }

  // ── Cell-per-line Format (Kotak via Syncfusion) ────────────────────────
  // Syncfusion extracts each PDF table cell as a separate line.
  // Transaction block structure:
  //   [serial]           e.g. "1"
  //   [date]             e.g. "01 Dec 2025"
  //   [narration line(s)]
  //   [ref number]       e.g. "UPI-533558112399"  (optional, all-caps alphanumeric)
  //   [txn amount]       e.g. "820.00"
  //   [running balance]  e.g. "50,846.07"
  //
  // Debit vs credit is determined by balance arithmetic (the only reliable
  // method when Dr / Cr columns are separate and text extraction loses position).
  static List<_RawTxn> _parseCellPerLine(String text) {
    // A line that is purely a decimal amount: "820.00" or "50,026.07"
    final amountLine = RegExp(r'^\d[\d,]*\.\d{1,2}$');
    // A transaction serial number: small integer on its own line
    final serialLine = RegExp(r'^\d{1,4}$');
    // Pure reference number line (all uppercase letters/digits/dashes, no spaces)
    final refLine = RegExp(r'^[A-Z0-9][A-Z0-9\-]{3,}$');

    final lines = text.split('\n').map((l) => l.trim()).toList();

    // ── Find opening balance ──
    double? runningBalance;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toUpperCase().contains('OPENING BALANCE')) {
        for (int j = i; j < min(i + 10, lines.length); j++) {
          if (amountLine.hasMatch(lines[j])) {
            runningBalance = _parseAmount(lines[j]);
            break;
          }
        }
        break;
      }
    }

    // ── Find where the transaction rows begin ──
    // Look for the last "Balance" that follows "Deposit (Cr.)" in the header.
    int start = 0;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i] == 'Balance' &&
          (lines[i - 1].contains('Deposit') || lines[i - 1].contains('(Cr.'))) {
        start = i + 1;
        break;
      }
    }

    final txns = <_RawTxn>[];
    int i = start;

    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) { i++; continue; }

      // Stop at footer markers
      if (line.contains('Statement Generated') ||
          line.contains('End of Statement') ||
          line.contains('Account Summary') ||
          line.contains('Important Information') ||
          line.contains('Commonly Used')) break;

      // Skip dashes and header-word lines from the opening-balance row
      if (line == '-' || line.toUpperCase() == 'OPENING BALANCE') { i++; continue; }

      // Each transaction starts with a serial number
      if (!serialLine.hasMatch(line)) { i++; continue; }

      i++; // consume serial

      // ── Date line ──
      DateTime? date;
      if (i < lines.length) {
        date = _parseDate(lines[i].trim());
        if (date != null) i++;
      }
      if (date == null) continue;

      // ── Collect narration and amounts until we have 2 amounts ──
      final narrationParts = <String>[];
      final amounts = <double>[];

      while (i < lines.length && amounts.length < 2) {
        final l = lines[i].trim();
        if (l.isEmpty) { i++; continue; }

        // Stop if we hit the next transaction's serial number
        if (serialLine.hasMatch(l) && !amountLine.hasMatch(l)) break;
        // Stop at footer
        if (l.contains('Statement Generated') || l.contains('Account Summary') ||
            l.contains('End of Statement')) break;
        // Skip stray dashes
        if (l == '-') { i++; continue; }

        if (amountLine.hasMatch(l)) {
          amounts.add(_parseAmount(l)!);
          i++;
        } else {
          // Exclude pure reference-number lines from narration display
          if (!refLine.hasMatch(l)) narrationParts.add(l);
          i++;
        }
      }

      if (amounts.length < 2) continue;

      final txnAmount = amounts[0];
      final newBalance = amounts[1];

      // ── Determine debit/credit via balance arithmetic ──
      bool isDebit;
      if (runningBalance != null) {
        final diffCredit = (newBalance - (runningBalance + txnAmount)).abs();
        final diffDebit  = (newBalance - (runningBalance - txnAmount)).abs();
        // Tie-break: fall back to keyword heuristic (very rare edge case)
        if ((diffCredit - diffDebit).abs() < 0.02) {
          isDebit = _isLikelyDebit(narrationParts.join(' '), '');
        } else {
          isDebit = diffDebit < diffCredit;
        }
        runningBalance = newBalance;
      } else {
        isDebit = _isLikelyDebit(narrationParts.join(' '), '');
      }

      var narration = narrationParts.join(' ').trim();
      if (narration.length > 100) narration = narration.substring(0, 100);

      if (narration.isNotEmpty && txnAmount > 0) {
        txns.add(_RawTxn(
          date: date,
          narration: narration,
          amount: txnAmount,
          isDebit: isDebit,
        ));
      }
    }

    return txns;
  }

  // ── BHIM UPI Format ────────────────────────────────────────────────────
  static List<_RawTxn> _parseBhimUpi(String text) {
    final txns = <_RawTxn>[];
    // BHIM: "date\tnarration\tUTR\tamount\tstatus\tDR/CR"
    // or similar tab/line separated
    final lines = text.split('\n');
    for (final line in lines) {
      final parts = line.split('\t').map((e) => e.trim()).toList();
      if (parts.length < 4) continue;

      DateTime? date;
      String narration = '';
      double? amount;
      bool? isDebit;

      for (final p in parts) {
        if (date == null) {
          date = _parseDate(p);
          if (date != null) continue;
        }
        if (amount == null) {
          final a = _parseAmount(p);
          if (a != null) {
            amount = a;
            continue;
          }
        }
        final upper = p.toUpperCase();
        if (upper == 'DR' || upper == 'DEBIT' || upper == 'PAID') {
          isDebit = true;
          continue;
        }
        if (upper == 'CR' || upper == 'CREDIT' || upper == 'RECEIVED') {
          isDebit = false;
          continue;
        }
        if (upper == 'SUCCESS' || upper == 'COMPLETED' || upper == 'FAILURE') {
          continue;
        }
        if (p.length > 3 && narration.isEmpty) narration = p;
      }

      if (amount != null && amount > 0) {
        txns.add(_RawTxn(
          date: date ?? DateTime.now(),
          narration: narration,
          amount: amount,
          // No explicit DR/CR token → fall back to keyword heuristic so a
          // "SALARY CREDIT" / "REFUND" row isn't wrongly counted as a debit.
          isDebit: isDebit ?? _isLikelyDebit(narration, line),
        ));
      }
    }
    return txns;
  }

  // ── Bank Statement Format ──────────────────────────────────────────────
  // Uses balance-column arithmetic to determine debit vs credit:
  //   new_balance = prev_balance + amount → credit
  //   new_balance = prev_balance - amount → debit
  // This is the only reliable method for banks (e.g. Kotak) that use
  // separate Dr/Cr columns — linear text extraction loses column position.
  static List<_RawTxn> _parseBankStatement(String text) {
    final txns = <_RawTxn>[];
    final lines = text.split('\n');

    // Step 1: Find opening balance
    double? runningBalance;
    for (final line in lines) {
      if (line.toUpperCase().contains('OPENING BALANCE')) {
        final amounts = _amountPattern.allMatches(line)
            .map((m) => _parseAmount(m.group(0)!))
            .whereType<double>()
            .where((a) => a > 0)
            .toList();
        if (amounts.isNotEmpty) {
          runningBalance = amounts.last;
          break;
        }
      }
    }

    // Step 2: Parse each transaction row
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final date = _parseDate(line);
      if (date == null) continue;

      // Collect this line plus continuation lines (no new date, no blank)
      final searchBlock = [line];
      for (int j = i + 1; j < min(i + 4, lines.length); j++) {
        final next = lines[j].trim();
        if (next.isEmpty) break;
        if (_parseDate(next) != null) break; // next txn started
        searchBlock.add(next);
      }
      final blockText = searchBlock.join(' ');

      // Skip header / summary rows
      final upper = blockText.toUpperCase();
      if (upper.contains('OPENING BALANCE') || upper.contains('CLOSING BALANCE') ||
          upper.contains('WITHDRAWAL') || upper.contains('DEPOSIT (CR')) continue;

      // Extract all amounts in this row
      final amounts = _amountPattern.allMatches(blockText)
          .map((m) => _parseAmount(m.group(0)!))
          .whereType<double>()
          .where((a) => a > 0)
          .toList();

      if (amounts.length < 2) continue; // need at least txn amount + balance

      // Last amount = running balance for this row
      final newBalance = amounts.last;
      final txnAmounts = amounts.sublist(0, amounts.length - 1);
      // Transaction amount is the largest non-balance figure on the row
      final amount = txnAmounts.reduce((a, b) => a > b ? a : b);

      // Determine direction via balance arithmetic (mathematically exact)
      bool isDebit;
      if (runningBalance != null) {
        final diffCredit = (newBalance - (runningBalance + amount)).abs();
        final diffDebit  = (newBalance - (runningBalance - amount)).abs();
        if (diffCredit < diffDebit) {
          isDebit = false; // money came in
        } else if (diffDebit < diffCredit) {
          isDebit = true;  // money went out
        } else {
          // Perfectly ambiguous (rare) — fall back to narration keywords
          final dateMatch = _datePattern.firstMatch(line);
          final narr = dateMatch != null ? line.substring(dateMatch.end) : line;
          isDebit = _isLikelyDebit(narr, blockText);
        }
        runningBalance = newBalance;
      } else {
        // No opening balance found — keyword heuristic
        final dateMatch = _datePattern.firstMatch(line);
        final narr = dateMatch != null ? line.substring(dateMatch.end) : line;
        isDebit = _isLikelyDebit(narr, blockText);
      }

      // Extract narration (text between date and first amount)
      final dateMatch = _datePattern.firstMatch(line);
      var narration = dateMatch != null ? line.substring(dateMatch.end).trim() : line;
      narration = narration
          .replaceAll(_amountPattern, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (narration.length > 80) narration = narration.substring(0, 80);

      txns.add(_RawTxn(
        date: date,
        narration: narration,
        amount: amount,
        isDebit: isDebit,
      ));
    }
    return txns;
  }

  // ── Generic Line Parser ────────────────────────────────────────────────
  static List<_RawTxn> _parseGenericLines(String text) {
    final txns = <_RawTxn>[];
    final lines = text.split('\n');

    for (final line in lines) {
      if (line.trim().length < 10) continue;
      final amountMatch = _amountPattern.firstMatch(line);
      if (amountMatch == null) continue;

      final amount = _parseAmount(amountMatch.group(0)!);
      if (amount == null || amount <= 0 || amount > 10000000) continue;

      final date = _parseDate(line) ?? DateTime.now();
      var narration = line
          .replaceAll(amountMatch.group(0)!, '')
          .replaceAll(_datePattern, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (narration.length > 80) narration = narration.substring(0, 80);

      txns.add(_RawTxn(
        date: date,
        narration: narration,
        amount: amount,
        isDebit: _isLikelyDebit(narration, line),
      ));
    }
    return txns;
  }

  // ── 5. ENRICHMENT ──────────────────────────────────────────────────────
  static _RawTxn _enrichTransaction(_RawTxn txn) {
    final n = txn.narration.toUpperCase();

    // Identify merchant from narration
    String merchant = txn.narration;
    for (final entry in _merchantPatterns.entries) {
      if (n.contains(entry.key)) {
        merchant = entry.value;
        break;
      }
    }

    // Determine budget flow first (income/refund/spend/transfer/investment)
    final flow = _classifyFlow(n, txn.isDebit);

    // Categorise with multi-pass — but honour the flow for non-spend items
    String category;
    switch (flow) {
      case _Flow.investment:
        category = 'Savings & Investments';
        break;
      case _Flow.transfer:
        category = 'Transfers (excluded)';
        break;
      case _Flow.refund:
        category = 'Refund';
        break;
      case _Flow.income:
        category = _categorise(n, txn.amount, false);
        break;
      case _Flow.spend:
        category = _categorise(n, txn.amount, true);
        break;
    }

    // Detect if person or merchant
    final isPerson = _isPersonTransfer(n);

    return _RawTxn(
      date: txn.date,
      narration: merchant,
      amount: txn.amount,
      isDebit: txn.isDebit,
      category: category,
      isPerson: isPerson,
      flow: flow,
    );
  }

  // ── 6. MULTI-PASS CATEGORISATION ───────────────────────────────────────
  static String _categorise(String narration, double amount, bool isDebit) {
    if (!isDebit) {
      if (narration.contains('SALARY') || narration.contains('SAL ')) {
        return 'Salary';
      }
      if (narration.contains('INTEREST')) return 'Interest';
      if (narration.contains('REFUND') || narration.contains('CASHBACK')) {
        return 'Refund';
      }
      return 'Income';
    }

    // Pass 1: exact merchant keyword
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (narration.contains(kw)) return entry.key;
      }
    }

    // Pass 2: UPI VPA patterns
    if (narration.contains('@')) {
      final vpa = narration.toLowerCase();
      if (vpa.contains('@ola') || vpa.contains('@uber')) return 'Transport';
      if (vpa.contains('@zomato') || vpa.contains('@swiggy')) return 'Food & Dining';
      if (vpa.contains('@paytm') || vpa.contains('@phonepe') || vpa.contains('@ybl')) {
        // Phone-number based VPA → person transfer
        if (RegExp(r'\d{10}@').hasMatch(vpa)) return 'Person Transfer';
        return 'Payments';
      }
      if (vpa.contains('@razorpay') || vpa.contains('@cashfree')) return 'Shopping';
    }

    // Pass 3: amount-based heuristics (for debits only)
    if (amount >= 5000 && amount <= 30000 && _isMonthlyPattern(narration)) {
      return 'Rent / EMI';
    }
    if (amount >= 50 && amount <= 999 && _isSubscriptionLike(narration)) {
      return 'Subscriptions';
    }

    return 'Other';
  }

  static bool _isMonthlyPattern(String n) =>
      n.contains('RENT') || n.contains('EMI') || n.contains('HOUSING') ||
      n.contains('FLAT') || n.contains('LANDLORD');

  static bool _isSubscriptionLike(String n) =>
      n.contains('NETFLIX') || n.contains('SPOTIFY') || n.contains('PRIME') ||
      n.contains('YOUTUBE') || n.contains('APPLE') || n.contains('GOOGLE') ||
      n.contains('AUTOPAY') || n.contains('SUBSCRIPTION') || n.contains('RECURRING');

  // ── 7. BUILD FULL ANALYSIS ─────────────────────────────────────────────
  static StatementAnalysis _buildAnalysis(List<_RawTxn> txns,
      {String accountHolder = ''}) {
    // Sort by date
    txns.sort((a, b) => a.date.compareTo(b.date));

    // Flow-separated totals — consumption vs everything else
    double income = 0;       // real income (excl. refunds & self-transfers)
    double spendGross = 0;   // consumption debits only
    double refunds = 0;      // credits that offset spend
    double investments = 0;  // money moved to savings/investments
    double transfersExcl = 0;// self-transfers / card-bill payments
    double personTransfers = 0, merchantSpend = 0;
    double largestExpenseAmount = 0;
    String largestExpenseLabel = '';

    final catAgg = <String, List<double>>{}; // cat → [amount, count]
    final recipientAgg = <String, List<double>>{}; // name → [amount, count]
    final ledger = <TxnEntry>[];
    final monthAgg = <String, List<double>>{}; // "YYYY-MM" → [income, spend]
    final weekAgg = <DateTime, List<double>>{}; // weekStart → [income, spend]
    final recurringCandidates = <String, List<_RawTxn>>{};

    for (final t in txns) {
      final dateStr = '${t.date.day.toString().padLeft(2, '0')}/'
          '${t.date.month.toString().padLeft(2, '0')}/'
          '${t.date.year}';

      ledger.add(TxnEntry(
        t.narration.isEmpty ? 'Unknown' : t.narration,
        dateStr,
        t.amount,
        t.isDebit,
        t.category,
      ));

      switch (t.flow) {
        case _Flow.income:
          income += t.amount;
          break;
        case _Flow.refund:
          refunds += t.amount;
          break;
        case _Flow.investment:
          investments += t.amount;
          break;
        case _Flow.transfer:
          transfersExcl += t.amount;
          break;
        case _Flow.spend:
          spendGross += t.amount;
          if (t.amount > largestExpenseAmount) {
            largestExpenseAmount = t.amount;
            largestExpenseLabel = t.narration.isEmpty ? 'Unknown' : t.narration;
          }
          catAgg.putIfAbsent(t.category, () => [0, 0]);
          catAgg[t.category]![0] += t.amount;
          catAgg[t.category]![1] += 1;

          final rName = t.narration.isEmpty ? 'Unknown' : t.narration;
          recipientAgg.putIfAbsent(rName, () => [0, 0]);
          recipientAgg[rName]![0] += t.amount;
          recipientAgg[rName]![1] += 1;

          if (t.isPerson) {
            personTransfers += t.amount;
          } else {
            merchantSpend += t.amount;
          }

          // Recurring detection keyed by PAYEE (+ amount band), not category —
          // so two unrelated ₹240 orders aren't mistaken for a subscription.
          final payee = (t.narration.isEmpty ? 'unknown' : t.narration)
              .toUpperCase()
              .replaceAll(RegExp(r'[^A-Z ]'), '')
              .trim();
          final key = '$payee|${(t.amount / 50).round() * 50}';
          recurringCandidates.putIfAbsent(key, () => []).add(t);
          break;
      }

      // Monthly / weekly trends use NET consumption vs income only
      final isSpend = t.flow == _Flow.spend;
      final isIncome = t.flow == _Flow.income;
      if (isSpend || isIncome) {
        final mKey = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
        monthAgg.putIfAbsent(mKey, () => [0, 0]);
        monthAgg[mKey]![isIncome ? 0 : 1] += t.amount;

        final wStart = t.date.subtract(Duration(days: t.date.weekday - 1));
        final wKey = DateTime(wStart.year, wStart.month, wStart.day);
        weekAgg.putIfAbsent(wKey, () => [0, 0]);
        weekAgg[wKey]![isIncome ? 0 : 1] += t.amount;
      }
    }

    // Net consumption = gross spend minus refunds (a refund cancels a purchase)
    final totalSpend = (spendGross - refunds).clamp(0, double.infinity).toDouble();
    final totalIncome = income;

    // Categories (consumption only)
    final catTotal = catAgg.values
        .fold<double>(0, (s, v) => s + v[0])
        .clamp(1, double.infinity);
    final categories = catAgg.entries
        .map((e) => CategorySpend(
            e.key, e.value[1].round(), e.value[0], e.value[0] / catTotal * 100))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Coverage / confidence metrics
    final otherCat = categories.where((c) => c.name == 'Other').firstOrNull;
    final uncategorisedPct = otherCat?.pct ?? 0;

    // Recipients
    final topRecipients = recipientAgg.entries
        .map((e) => Recipient(e.key, e.value[0], e.value[1].round()))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Monthly trends
    const monNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mKeys = monthAgg.keys.toList()..sort();
    final months = mKeys.map((k) {
      final m = int.parse(k.split('-')[1]);
      return MonthTrend('${monNames[m - 1]}.', monthAgg[k]![0], monthAgg[k]![1]);
    }).toList();
    final monthsCovered = mKeys.length;

    // Period span (inclusive)
    final periodDays = txns.isEmpty
        ? 0
        : txns.last.date.difference(txns.first.date).inDays + 1;
    final dailyAvgSpend = periodDays > 0 ? totalSpend / periodDays : totalSpend;

    // Weekly trends
    final wKeys = weekAgg.keys.toList()..sort();
    final recentWeeks = wKeys.length > 6 ? wKeys.sublist(wKeys.length - 6) : wKeys;
    final weeks = recentWeeks.map((k) =>
        MonthTrend('${k.day} ${monNames[k.month - 1]}', weekAgg[k]![0], weekAgg[k]![1]))
        .toList();

    // Recurring payments
    final recurring = _detectRecurring(recurringCandidates);

    // Health score (period-aware, confidence-scaled)
    final scored = _computeHealthScore(
      totalIncome: totalIncome,
      totalSpend: totalSpend,
      categories: categories,
      months: months,
      monthsCovered: monthsCovered,
      recurringCount: recurring.length,
    );

    final savingsRate = totalIncome > 0 ? (totalIncome - totalSpend) / totalIncome : 0.0;

    // Risk flags
    final riskFlags = _computeRiskFlags(
      totalIncome: totalIncome,
      totalSpend: totalSpend,
      categories: categories,
      topRecipients: topRecipients,
      months: months,
      recurring: recurring,
      txns: txns,
    );

    // Insights (now period & coverage aware)
    final insights = _computeInsights(
      totalIncome: totalIncome,
      totalSpend: totalSpend,
      categories: categories,
      topRecipients: topRecipients,
      months: months,
      recurring: recurring,
      savingsRate: savingsRate.toDouble(),
      monthsCovered: monthsCovered,
      periodDays: periodDays,
      uncategorisedPct: uncategorisedPct,
      investments: investments,
      refunds: refunds,
    );

    return StatementAnalysis(
      totalSaving: totalIncome - totalSpend,
      totalIncome: totalIncome,
      totalSpend: totalSpend,
      txnCount: txns.length,
      avgTransaction: catAgg.isEmpty
          ? 0
          : spendGross / max(1, txns.where((t) => t.flow == _Flow.spend).length),
      personTransfers: personTransfers,
      merchantSpend: merchantSpend,
      healthScore: scored.score,
      insights: insights,
      riskFlags: riskFlags,
      categories: categories.take(8).toList(),
      months: months,
      weeks: weeks,
      ledger: ledger.reversed.take(40).toList(),
      topRecipients: topRecipients.take(8).toList(),
      monthsCovered: monthsCovered,
      periodDays: periodDays,
      uncategorisedPct: uncategorisedPct.toDouble(),
      investments: investments,
      refunds: refunds,
      transfersExcluded: transfersExcl,
      scoreConfidence: scored.confidence,
      accountHolder: accountHolder,
      recurringPayments: recurring,
      largestExpenseLabel: largestExpenseLabel,
      largestExpenseAmount: largestExpenseAmount,
      dailyAvgSpend: dailyAvgSpend,
    );
  }

  // ── 8. RECURRING PAYMENT DETECTION ─────────────────────────────────────
  static List<String> _detectRecurring(Map<String, List<_RawTxn>> candidates) {
    final recurring = <String>[];
    for (final entry in candidates.entries) {
      final txnList = entry.value;
      if (txnList.length < 2) continue;

      // Check if roughly monthly gap (~25-35 days between transactions)
      txnList.sort((a, b) => a.date.compareTo(b.date));
      int monthlyGaps = 0;
      for (int i = 1; i < txnList.length; i++) {
        final gap = txnList[i].date.difference(txnList[i - 1].date).inDays;
        if (gap >= 25 && gap <= 40) monthlyGaps++;
      }
      if (monthlyGaps >= 1) {
        final label = '${txnList.first.narration} ~₹${txnList.first.amount.round()}/month';
        if (!recurring.contains(label)) recurring.add(label);
      }
    }
    return recurring;
  }

  // ── 9. HEALTH SCORE ENGINE (period-aware, confidence-scaled) ───────────
  // Each dimension is only scored when its data exists. The final score is
  // (earned / available) × 100 so a single-month file isn't handed free marks
  // for dimensions (like stability) it can't actually measure. `confidence`
  // reports what fraction of the full 100-pt model the data supported.
  static _Score _computeHealthScore({
    required double totalIncome,
    required double totalSpend,
    required List<CategorySpend> categories,
    required List<MonthTrend> months,
    required int monthsCovered,
    required int recurringCount,
  }) {
    double earned = 0;     // points scored
    double available = 0;  // points that could be scored given the data

    final hasIncome = totalIncome > 0;

    // Dimension 1: Savings rate (30 pts) — needs income
    if (hasIncome) {
      available += 30;
      final savingsRate = (totalIncome - totalSpend) / totalIncome;
      earned += (savingsRate / 0.20 * 30).clamp(0, 30);
    }

    // Dimension 2: Expense ratio (25 pts) — essential spend < 50% income
    if (hasIncome) {
      available += 25;
      const essentialCats = ['Rent / EMI', 'Bills & Utilities', 'Groceries', 'Transport'];
      double essentialSpend = 0;
      for (final c in categories) {
        if (essentialCats.contains(c.name)) essentialSpend += c.amount;
      }
      final essentialRatio = essentialSpend / totalIncome;
      earned += ((1.0 - essentialRatio / 0.50) * 25).clamp(0, 25);
    }

    // Dimension 3: Spending stability (20 pts) — ONLY if ≥2 months of data
    if (monthsCovered >= 2 && months.length >= 2) {
      available += 20;
      final spends = months.map((m) => m.spend).toList();
      final avg = spends.reduce((a, b) => a + b) / spends.length;
      if (avg > 0) {
        final variance = spends.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) / spends.length;
        final cv = sqrt(variance) / avg; // coefficient of variation
        earned += ((1.0 - cv) * 20).clamp(0, 20);
      } else {
        earned += 20;
      }
    }

    // Dimension 4: Category diversity (15 pts) — needs categorised spend
    if (categories.isNotEmpty && totalSpend > 0) {
      available += 15;
      final topPct = categories.first.pct;
      double d = 15;
      if (topPct > 60) d = 3;
      else if (topPct > 45) d = 8;
      else if (topPct > 35) d = 12;
      earned += d;
    }

    // Dimension 5: Subscription control (10 pts)
    if (totalSpend > 0) {
      available += 10;
      earned += recurringCount <= 3
          ? 10
          : recurringCount <= 6
              ? 7
              : recurringCount <= 10
                  ? 4
                  : 1;
    }

    if (available == 0) return const _Score(50, 0);
    final score = (earned / available * 100).round().clamp(0, 100);
    final confidence = (available / 100 * 100).round().clamp(0, 100);
    return _Score(score, confidence);
  }

  // ── 10. RISK FLAGS ENGINE (12 specific rules) ──────────────────────────
  static List<String> _computeRiskFlags({
    required double totalIncome,
    required double totalSpend,
    required List<CategorySpend> categories,
    required List<Recipient> topRecipients,
    required List<MonthTrend> months,
    required List<String> recurring,
    required List<_RawTxn> txns,
  }) {
    final flags = <String>[];
    if (totalIncome == 0) return flags;

    final savingsRate = (totalIncome - totalSpend) / totalIncome;

    // 1. Low savings
    if (savingsRate < 0.10) {
      flags.add('Savings rate is ${(savingsRate * 100).toStringAsFixed(0)}% — below the recommended 20% minimum');
    }

    // 2. Over-concentrated spending
    if (categories.isNotEmpty && categories.first.pct > 40) {
      flags.add('${categories.first.name} is ${categories.first.pct.toStringAsFixed(0)}% of total spend — high concentration');
    }

    // 3. Spending growth month-over-month
    if (months.length >= 2) {
      final last = months.last.spend;
      final prev = months[months.length - 2].spend;
      if (prev > 0 && last > prev * 1.25) {
        final growth = ((last / prev - 1) * 100).round();
        flags.add('Spending jumped $growth% vs last month');
      }
    }

    // 4. Declining savings trend (3 months in a row)
    if (months.length >= 3) {
      final recent = months.sublist(months.length - 3);
      final rates = recent.map((m) => m.savingPct).toList();
      if (rates[2] < rates[1] && rates[1] < rates[0]) {
        flags.add('Savings rate declined 3 months in a row');
      }
    }

    // 5. Large single transaction (outlier)
    final debitTxns = txns.where((t) => t.isDebit).toList();
    if (debitTxns.length > 3) {
      final amounts = debitTxns.map((t) => t.amount).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      final largest = amounts.last;
      if (largest > median * 5 && largest > 2000) {
        flags.add('₹${largest.round()} single transaction — ${(largest / median).toStringAsFixed(0)}× your median spend');
      }
    }

    // 6. High subscription load
    if (recurring.length > 5) {
      flags.add('${recurring.length} recurring payments detected — review which you actually use');
    }

    // 7. Unknown payee concentration
    final otherCat = categories.where((c) => c.name == 'Other').firstOrNull;
    if (otherCat != null && otherCat.pct > 25) {
      flags.add('${otherCat.pct.toStringAsFixed(0)}% of spend to unidentified merchants');
    }

    // 8. Person transfer spike
    final personCat = categories.where((c) =>
        c.name == 'Person Transfer' || c.name == 'Payments').toList();
    double personTotal = 0;
    for (final c in personCat) personTotal += c.amount;
    if (personTotal > totalSpend * 0.3) {
      flags.add('${(personTotal / totalSpend * 100).toStringAsFixed(0)}% of spend is person-to-person transfers');
    }

    // 9. Rent / EMI too high
    final rentCat = categories.where((c) => c.name == 'Rent / EMI').firstOrNull;
    if (rentCat != null && totalIncome > 0) {
      final rentRatio = rentCat.amount / totalIncome;
      if (rentRatio > 0.40) {
        flags.add('Rent/EMI is ${(rentRatio * 100).toStringAsFixed(0)}% of income — recommended max is 30%');
      }
    }

    // 10. Weekend spending spike
    final weekendSpend = debitTxns
        .where((t) => t.date.weekday >= 6)
        .fold<double>(0, (s, t) => s + t.amount);
    final weekdaySpend = totalSpend - weekendSpend;
    if (weekendSpend > 0 && totalSpend > 0) {
      final weekendPct = weekendSpend / totalSpend;
      // Weekends are 2/7 ≈ 28.6% of days. If > 40% of spend, flag it.
      if (weekendPct > 0.40) {
        flags.add('${(weekendPct * 100).toStringAsFixed(0)}% of spending happens on weekends');
      }
    }

    return flags;
  }

  // ── 11. INSIGHT ENGINE (rule-based, with real numbers) ─────────────────
  static List<String> _computeInsights({
    required double totalIncome,
    required double totalSpend,
    required List<CategorySpend> categories,
    required List<Recipient> topRecipients,
    required List<MonthTrend> months,
    required List<String> recurring,
    required double savingsRate,
    required int monthsCovered,
    required int periodDays,
    required double uncategorisedPct,
    required double investments,
    required double refunds,
  }) {
    final insights = <String>[];

    // 0. Period context — always first so numbers are read correctly
    if (periodDays > 0) {
      final span = monthsCovered >= 2
          ? '$monthsCovered months'
          : '$periodDays day${periodDays == 1 ? '' : 's'}';
      insights.add('Analysis covers $span of activity${monthsCovered < 2 ? ' — trends need 2+ months to be reliable.' : '.'}');
    }

    // 1. Savings assessment (only meaningful with income)
    if (totalIncome > 0) {
      if (savingsRate >= 0.20) {
        insights.add('You\'re saving ${(savingsRate * 100).toStringAsFixed(0)}% of income — above the 20% benchmark. Keep it up.');
      } else if (savingsRate >= 0) {
        final target = (totalIncome * 0.20 - (totalIncome - totalSpend)).round();
        insights.add('Saving ${(savingsRate * 100).toStringAsFixed(0)}% — cut ₹${_formatInr(target)} more to hit the 20% benchmark.');
      } else {
        insights.add('You spent more than you earned this period — a ${(-savingsRate * 100).toStringAsFixed(0)}% shortfall.');
      }
    } else {
      insights.add('No income detected in this file — savings rate can\'t be computed. Upload a statement that includes your salary/credits for a full picture.');
    }

    // 1b. Investments — credit where it's due
    if (investments > 0) {
      insights.add('₹${_formatInr(investments.round())} went to savings/investments — counted as saved, not spent.');
    }
    // 1c. Refunds applied
    if (refunds > 0) {
      insights.add('₹${_formatInr(refunds.round())} in refunds/cashback was netted off your spending.');
    }

    // 2. Top spending category
    if (categories.isNotEmpty) {
      final top = categories.first;
      insights.add('${top.name} is your biggest spend — ₹${_formatInr(top.amount.round())} across ${top.txns} transactions (${top.pct.toStringAsFixed(0)}%).');
    }

    // 3. Top recipient
    if (topRecipients.isNotEmpty) {
      final r = topRecipients.first;
      insights.add('${r.name} received ₹${_formatInr(r.total.round())} across ${r.count} payments — your most-paid entity.');
    }

    // 4. Recurring payments
    if (recurring.isNotEmpty) {
      insights.add('Detected ${recurring.length} recurring payments. Review if all are still needed.');
    }

    // 5. Month-over-month trend
    if (months.length >= 2) {
      final curr = months.last;
      final prev = months[months.length - 2];
      if (curr.spend > prev.spend) {
        final increase = ((curr.spend / prev.spend - 1) * 100).round();
        insights.add('Spending increased $increase% vs last month — ${curr.name} vs ${prev.name}.');
      } else {
        final decrease = ((1 - curr.spend / prev.spend) * 100).round();
        insights.add('Spending dropped $decrease% vs last month — good trajectory.');
      }
    }

    // 6. Food & dining check
    final foodCat = categories.where((c) =>
        c.name == 'Food & Dining' || c.name == 'Groceries').toList();
    double foodTotal = 0;
    for (final c in foodCat) foodTotal += c.amount;
    if (foodTotal > 0 && totalSpend > 0) {
      final pct = foodTotal / totalSpend * 100;
      if (pct > 30) {
        insights.add('Food & groceries is ${pct.toStringAsFixed(0)}% of spend. Consider meal planning or cooking more.');
      }
    }

    // 7. Small transaction accumulation
    final smallTxns = categories
        .where((c) => c.txns > 15 && c.amount / c.txns < 300)
        .toList();
    if (smallTxns.isNotEmpty) {
      final c = smallTxns.first;
      insights.add('${c.txns} small ${c.name} transactions averaging ₹${(c.amount / c.txns).round()} each add up to ₹${_formatInr(c.amount.round())}.');
    }

    // 8. Best savings month
    if (months.length >= 3) {
      var bestMonth = months.first;
      for (final m in months) {
        if (m.savingPct > bestMonth.savingPct) bestMonth = m;
      }
      if (bestMonth.savingPct > 0.25) {
        insights.add('Best month: ${bestMonth.name} — saved ${(bestMonth.savingPct * 100).round()}% of income.');
      }
    }

    // 9. Coverage caveat — be honest when categorisation was uncertain
    if (uncategorisedPct > 25) {
      insights.add('${uncategorisedPct.toStringAsFixed(0)}% of spending couldn\'t be auto-categorised — category breakdown is approximate.');
    }

    return insights;
  }

  // ── HELPER: Format INR with commas ─────────────────────────────────────
  static String _formatInr(int n) {
    if (n < 1000) return '$n';
    final s = n.toString();
    final len = s.length;
    final buf = StringBuffer();
    for (int i = 0; i < len; i++) {
      if (i > 0) {
        final fromEnd = len - i;
        if (fromEnd == 3 || (fromEnd > 3 && (fromEnd - 3) % 2 == 0)) {
          buf.write(',');
        }
      }
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── HELPERS ────────────────────────────────────────────────────────────
  static final _datePattern = RegExp(
      r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})'
      r'|(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+(\d{2,4})',
      caseSensitive: false);

  static final _amountPattern = RegExp(
      r'(?:₹\s*|Rs\.?\s*|INR\s*)?(\d[\d,]*\.\d{1,2})'
      r'|(?:₹\s*|Rs\.?\s*|INR\s*)(\d[\d,]+)');

  static DateTime? _parseDate(String text) {
    final m = _datePattern.firstMatch(text);
    if (m == null) return null;

    if (m.group(1) != null) {
      // dd/mm/yyyy or dd-mm-yyyy
      int d = int.parse(m.group(1)!);
      int mo = int.parse(m.group(2)!);
      int y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo > 12) { final t = d; d = mo; mo = t; } // swap if mm/dd
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      return DateTime(y, mo, d);
    }

    if (m.group(4) != null) {
      // dd Mon yyyy
      const mons = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
      final d = int.parse(m.group(4)!);
      final mo = mons.indexOf(m.group(5)!.toLowerCase()) + 1;
      int y = int.parse(m.group(6)!);
      if (y < 100) y += 2000;
      if (mo < 1 || d < 1 || d > 31) return null;
      return DateTime(y, mo, d);
    }
    return null;
  }

  static double? _parseAmount(String text) {
    final cleaned = text.replaceAll('₹', '').replaceAll('Rs.', '').replaceAll('Rs', '')
        .replaceAll('INR', '').replaceAll(',', '').replaceAll(' ', '').trim();
    return double.tryParse(cleaned);
  }

  static bool _isLikelyDebit(String narration, String line) {
    final u = '${narration.toUpperCase()} ${line.toUpperCase()}';

    // Phrases that contain a misleading "CREDIT"/"CARD" but are DEBITS
    // (paying a credit-card bill is money going out).
    if (u.contains('CREDIT CARD') || u.contains('CC PAYMENT') ||
        u.contains('CARD PAYMENT') || u.contains('CC BILL')) {
      return true;
    }

    // Genuine credit (money in) indicators — use word boundaries so "CREDIT"
    // inside "CREDIT CARD" doesn't trigger (already handled above anyway).
    final creditRe = RegExp(
        r'\b(SALARY|CREDIT|CREDITED|RECEIVED|INWARD|REFUND|CASHBACK|INTEREST|DEPOSIT|'
        r'NEFT CR|IMPS CR|RTGS CR|CR\b|REVERSAL|DIVIDEND|MATURITY|BY TRANSFER|ACH CR)\b');
    if (creditRe.hasMatch(u)) return false;

    return true;
  }

  static bool _isPersonTransfer(String narration) {
    if (RegExp(r'\d{10}@').hasMatch(narration.toLowerCase())) return true;
    if (narration.toUpperCase().contains('PERSON')) return true;
    if (narration.toUpperCase().contains('TRANSFER TO') ||
        narration.toUpperCase().contains('SENT TO')) return true;
    return false;
  }

  // ── ACCOUNT HOLDER NAME EXTRACTION ─────────────────────────────────────
  // Banks print the account holder near the top. Try explicit labels first,
  // then fall back to the first clean "name-looking" line that isn't a header
  // or a transaction narration.
  static const _nameStopWords = [
    'ACCOUNT', 'STATEMENT', 'BANK', 'BRANCH', 'SAVINGS', 'CURRENT', 'CRN',
    'MICR', 'IFSC', 'CURRENCY', 'PERIOD', 'SUMMARY', 'TRANSACTION', 'BALANCE',
    'ADDRESS', 'PHONE', 'NOMINEE', 'STATUS', 'TYPE', 'INDIA', 'UPI', 'IMPS',
    'NEFT', 'RTGS', 'RECD', 'OPENING', 'CLOSING', 'WITHDRAWAL', 'DEPOSIT',
    'DESCRIPTION', 'REGISTERED', 'NUMBER', 'CODE', 'GENERATED', 'PAGE',
  ];

  static String _extractAccountHolder(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1) Explicit label: "Name: ...", "Customer Name - ...", etc.
    final labelRe = RegExp(
        r'(?:Account Holder|Customer Name|A/C Holder Name|A/C Holder|Name)\s*[:\-]\s*([A-Za-z][A-Za-z .]{2,40})',
        caseSensitive: false);
    for (final l in lines.take(40)) {
      final m = labelRe.firstMatch(l);
      if (m != null) {
        final name = m.group(1)!.trim();
        if (_looksLikeName(name)) return _titleCase(name);
      }
    }

    // 2) First clean name-looking line near the top (no digits / slashes / @).
    for (final l in lines.take(30)) {
      if (l.contains('/') || l.contains('@') || RegExp(r'\d').hasMatch(l)) {
        continue;
      }
      final upper = l.toUpperCase();
      if (_nameStopWords.any((s) => upper.contains(s))) continue;
      final cleaned = l.replaceAll(RegExp(r'[^A-Za-z ]'), '').trim();
      if (_looksLikeName(cleaned)) return _titleCase(cleaned);
    }
    return '';
  }

  static bool _looksLikeName(String s) {
    final tokens = s.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2 || tokens.length > 4) return false;
    for (final t in tokens) {
      if (t.length < 2) return false;
      if (!RegExp(r'^[A-Za-z.]+$').hasMatch(t)) return false;
    }
    return true;
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

}

// ── Merchant recognition database ────────────────────────────────────────────
const _merchantPatterns = <String, String>{
  'SWIGGY': 'Swiggy', 'ZOMATO': 'Zomato', 'DOMINOS': 'Dominos',
  'STARBUCKS': 'Starbucks', 'MCDONALDS': 'McDonalds', 'KFC': 'KFC',
  'HALDIRAMS': 'Haldirams', 'BURGER KING': 'Burger King', 'SUBWAY': 'Subway',
  'BLINKIT': 'Blinkit', 'ZEPTO': 'Zepto', 'BIGBASKET': 'BigBasket',
  'DMART': 'DMart', 'MORE RETAIL': 'More Retail', 'GROFERS': 'Grofers',
  'AMAZON': 'Amazon', 'FLIPKART': 'Flipkart', 'MYNTRA': 'Myntra',
  'AJIO': 'Ajio', 'NYKAA': 'Nykaa', 'CROMA': 'Croma',
  'MEESHO': 'Meesho', 'SNAPDEAL': 'Snapdeal',
  'UBER': 'Uber', 'OLA': 'Ola', 'RAPIDO': 'Rapido',
  'IRCTC': 'IRCTC', 'BPCL': 'BPCL Fuel', 'IOCL': 'IOCL Fuel',
  'MAKEMYTRIP': 'MakeMyTrip', 'GOIBIBO': 'GoIbibo',
  'NETFLIX': 'Netflix', 'SPOTIFY': 'Spotify', 'HOTSTAR': 'Hotstar',
  'YOUTUBE': 'YouTube Premium', 'PRIME VIDEO': 'Prime Video',
  'BOOKMYSHOW': 'BookMyShow', 'PVR': 'PVR INOX',
  'APOLLO': 'Apollo', 'PRACTO': 'Practo', '1MG': '1mg',
  'PHARMEASY': 'PharmEasy', 'MAX HOSPITAL': 'Max Hospital',
  'TATA POWER': 'Tata Power', 'BSES': 'BSES', 'MAHANAGAR GAS': 'Mahanagar Gas',
  'JIO': 'Jio', 'AIRTEL': 'Airtel', 'VI PREPAID': 'Vi',
  'UDEMY': 'Udemy', 'COURSERA': 'Coursera', 'UNACADEMY': 'Unacademy',
  'CHATGPT': 'ChatGPT Plus', 'OPENAI': 'OpenAI',
  'APPLE.COM': 'Apple', 'GOOGLE': 'Google Play', 'LINKEDIN': 'LinkedIn',
};

// ── Category keyword database ────────────────────────────────────────────────
const _categoryKeywords = <String, List<String>>{
  'Food & Dining': [
    'SWIGGY', 'ZOMATO', 'DOMINOS', 'STARBUCKS', 'MCDONALDS', 'KFC',
    'HALDIRAMS', 'BURGER', 'SUBWAY', 'PIZZA', 'RESTAURANT', 'CAFE',
    'FOOD', 'DINING', 'DINEOUT', 'EATSURE', 'DUNZO',
  ],
  'Groceries': [
    'BLINKIT', 'ZEPTO', 'BIGBASKET', 'DMART', 'MORE RETAIL',
    'GROFERS', 'GROCERY', 'SUPERMARKET', 'RELIANCE FRESH', 'NATURE',
  ],
  'Shopping': [
    'AMAZON', 'FLIPKART', 'MYNTRA', 'AJIO', 'NYKAA', 'CROMA',
    'MEESHO', 'SNAPDEAL', 'SHOPPERS', 'LIFESTYLE', 'DECATHLON',
    'IKEA', 'CHROMA', 'RELIANCE DIGITAL',
  ],
  'Transport': [
    'UBER', 'OLA', 'RAPIDO', 'IRCTC', 'BPCL', 'IOCL', 'PETROL',
    'DIESEL', 'FUEL', 'METRO', 'MAKEMYTRIP', 'GOIBIBO', 'INDIGO',
    'SPICEJET', 'VISTARA', 'PARKING', 'FASTAG', 'TOLL',
  ],
  'Entertainment': [
    'NETFLIX', 'SPOTIFY', 'HOTSTAR', 'YOUTUBE', 'PRIME VIDEO',
    'BOOKMYSHOW', 'PVR', 'INOX', 'GAMING', 'STEAM', 'PLAY STORE',
  ],
  'Bills & Utilities': [
    'TATA POWER', 'BSES', 'MAHANAGAR GAS', 'ELECTRICITY', 'GAS BILL',
    'WATER BILL', 'BROADBAND', 'WIFI', 'JIO', 'AIRTEL', 'VI PREPAID',
    'VODAFONE', 'RECHARGE', 'BILLPAY', 'BILLDESK',
  ],
  'Health & Medical': [
    'APOLLO', 'PRACTO', '1MG', 'PHARMEASY', 'HOSPITAL', 'MEDICAL',
    'PHARMACY', 'DOCTOR', 'HEALTH', 'DIAGNOSTIC', 'LAB', 'INSURANCE',
  ],
  'Education': [
    'UDEMY', 'COURSERA', 'UNACADEMY', 'BYJU', 'SCHOOL', 'COLLEGE',
    'UNIVERSITY', 'TUITION', 'COACHING', 'EXAM', 'EDUCATION',
  ],
  'Subscriptions': [
    'CHATGPT', 'OPENAI', 'APPLE.COM', 'LINKEDIN', 'AUTOPAY',
    'SUBSCRIPTION', 'RECURRING', 'MEMBERSHIP', 'PREMIUM',
  ],
  'Rent / EMI': [
    'RENT', 'EMI', 'HOUSING', 'FLAT', 'LANDLORD', 'LOAN',
    'MORTGAGE', 'HOME LOAN',
  ],
  'Person Transfer': [
    'SENT TO', 'TRANSFER TO', 'PAID TO',
  ],
};

// Money leaving the account but NOT consumed — excluded from spend so it
// doesn't deflate the savings rate. (Credit-card bill, self-transfer, wallet load.)
const _transferKeywords = <String>[
  'CREDIT CARD PAYMENT', 'CC PAYMENT', 'CARD PAYMENT', 'CREDIT CARD BILL',
  'CC BILL', 'BILLDESK CREDIT CARD', 'AMEX PAYMENT',
  'SELF', 'OWN ACCOUNT', 'TO SELF', 'SAME ACCOUNT', 'INTERNAL TRANSFER',
  'ADD MONEY', 'WALLET LOAD', 'LOAD WALLET', 'ADD FUNDS', 'WALLET TOPUP',
  'TOP UP WALLET', 'FUND TRANSFER SELF',
];

// Money moved into savings/investments — counts as SAVED, not spent.
const _investmentKeywords = <String>[
  'SIP', 'MUTUAL FUND', 'GROWW', 'ZERODHA', 'UPSTOX', 'KUVERA', 'INDMONEY',
  'COIN ZERODHA', 'NPS', 'PPF', 'ELSS', 'FIXED DEPOSIT', 'RECURRING DEPOSIT',
  'INVESTMENT', 'STOCKS', 'EQUITY', 'SMALLCASE', 'PAYTM MONEY', 'ETMONEY',
  'NIFTY', 'INDEX FUND', 'GOLD BOND', 'SGB',
  // IPO / AMC / brokerage
  'ASBA', 'AMC', 'ICICIAMC', 'SBIAMC', 'HDFCAMC', 'NIPPONAMC', 'KOTAKIMC',
  'BSE STAR MF', 'NSE MF', 'CAMS', 'KARVY', 'DEMAT', 'TRADING ACCOUNT',
  'KOTAK SECURITIES', 'ICICI SECURITIES', 'HDFC SECURITIES', 'ANGEL BROKING',
  'ANGEL ONE', 'SHAREKHAN', 'MOTILAL OSWAL', '5PAISA', 'FYERS', 'DHAN',
  'STOXKART', 'IIFL SECURITIES', 'GEOJIT',
];

// Credits that return money for a prior purchase — offset spend, not income.
const _refundKeywords = <String>[
  'REFUND', 'CASHBACK', 'REVERSAL', 'REVERSED', 'CHARGEBACK',
  'RETURN', 'FAILED TXN', 'DISPUTE CREDIT',
];

// Credits that are NOT real income — self-transfers in, etc.
const _transferInKeywords = <String>[
  'SELF', 'OWN ACCOUNT', 'TO SELF', 'FROM SELF', 'INTERNAL TRANSFER',
  'SAME ACCOUNT', 'REDEMPTION', 'MATURITY', 'FD CLOSURE', 'RD CLOSURE',
];

bool _containsAny(String n, List<String> kws) {
  for (final k in kws) {
    if (n.contains(k)) return true;
  }
  return false;
}

// Decide how a transaction flows through the budget.
_Flow _classifyFlow(String narrationUpper, bool isDebit) {
  if (isDebit) {
    if (_containsAny(narrationUpper, _investmentKeywords)) return _Flow.investment;
    if (_containsAny(narrationUpper, _transferKeywords)) return _Flow.transfer;
    return _Flow.spend;
  } else {
    if (_containsAny(narrationUpper, _refundKeywords)) return _Flow.refund;
    if (_containsAny(narrationUpper, _transferInKeywords)) return _Flow.transfer;
    return _Flow.income;
  }
}

// Health-score result with a confidence figure (how much of the model the
// available data actually supported).
class _Score {
  final int score;
  final int confidence;
  const _Score(this.score, this.confidence);
}

// How a transaction affects the budget. This is the key to accuracy:
// only `spend` is consumption; transfers/investments/refunds must NOT be
// counted as spending or the savings rate is meaningless.
enum _Flow { income, refund, spend, transfer, investment }

// ── Raw transaction (internal) ───────────────────────────────────────────────
class _RawTxn {
  final DateTime date;
  final String narration;
  final double amount;
  final bool isDebit;
  final String category;
  final bool isPerson;
  final _Flow flow;

  _RawTxn({
    required this.date,
    required this.narration,
    required this.amount,
    required this.isDebit,
    this.category = 'Other',
    this.isPerson = false,
    this.flow = _Flow.spend,
  });
}
