import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'ondevice_analysis.dart';

class CategorySpend {
  final String name;
  final int txns;
  final double amount;
  final double pct;
  const CategorySpend(this.name, this.txns, this.amount, this.pct);
}

class MonthTrend {
  final String name; // "Sep."
  final double income; // cr
  final double spend; // dr
  const MonthTrend(this.name, this.income, this.spend);

  double get savingPct =>
      income > 0 ? ((income - spend) / income).clamp(0.0, 1.0) : 0.0;
}


class TxnEntry {
  final String name;
  final String date;
  final double amount;
  final bool isDebit;
  final String category;
  const TxnEntry(this.name, this.date, this.amount, this.isDebit, this.category);
}

class Recipient {
  final String name;
  final double total;
  final int count;
  const Recipient(this.name, this.total, this.count);
}

class StatementAnalysis {
  final double totalSaving; // cr - dr
  final double totalIncome; // cr
  final double totalSpend; // dr
  final int txnCount;
  final double avgTransaction;
  final double personTransfers; // DR to "person"-type categories
  final double merchantSpend;
  final int healthScore;
  final List<String> insights;
  final List<String> riskFlags;
  final List<CategorySpend> categories;
  final List<MonthTrend> months;
  final List<MonthTrend> weeks;
  final List<TxnEntry> ledger;
  final List<Recipient> topRecipients;
  final bool isDemo;

  // ── Accuracy / coverage metadata (defaults keep old call-sites valid) ──
  final int monthsCovered;       // distinct calendar months in the file
  final int periodDays;          // span between first & last txn (inclusive)
  final double uncategorisedPct; // % of consumption spend tagged "Other"
  final double investments;      // money moved to savings/investments (saved, not spent)
  final double refunds;          // credits that offset spend (refunds/cashback)
  final double transfersExcluded;// self-transfers / card-bill payments excluded
  final int scoreConfidence;     // 0-100: how much of the score is data-backed

  // ── Richer analysis surface ──
  final String accountHolder;         // name pulled from the statement header
  final List<String> recurringPayments;
  final String largestExpenseLabel;
  final double largestExpenseAmount;
  final double dailyAvgSpend;

  const StatementAnalysis({
    required this.totalSaving,
    required this.totalIncome,
    required this.totalSpend,
    required this.txnCount,
    required this.avgTransaction,
    required this.personTransfers,
    required this.merchantSpend,
    required this.healthScore,
    required this.insights,
    required this.riskFlags,
    required this.categories,
    required this.months,
    required this.weeks,
    required this.ledger,
    required this.topRecipients,
    this.isDemo = false,
    this.monthsCovered = 1,
    this.periodDays = 30,
    this.uncategorisedPct = 0,
    this.investments = 0,
    this.refunds = 0,
    this.transfersExcluded = 0,
    this.scoreConfidence = 100,
    this.accountHolder = '',
    this.recurringPayments = const [],
    this.largestExpenseLabel = '',
    this.largestExpenseAmount = 0,
    this.dailyAvgSpend = 0,
  });

  double get savingsRate =>
      totalIncome > 0 ? ((totalIncome - totalSpend) / totalIncome) : 0.0;

  static const demo = StatementAnalysis(
    totalSaving: 80241,
    totalIncome: 142500,
    totalSpend: 62259,
    txnCount: 155,
    avgTransaction: 1240.50,
    personTransfers: 7370,
    merchantSpend: 13348,
    healthScore: 64,
    insights: [
      'Spending is concentrated in Shopping — consider a monthly cap.',
      'Detected recurring payments worth ₹2,140/month.',
    ],
    riskFlags: [
      'High spend ratio this month',
      'Large impulsive purchase detected',
    ],
    categories: [
      CategorySpend('Shopping', 46, 8125.00, 42),
      CategorySpend('Service', 38, 4841.12, 19),
      CategorySpend('Entertainment', 26, 1524.00, 12),
      CategorySpend('Transfers', 14, 614.76, 9),
      CategorySpend('Food & Dining', 31, 3210.40, 18),
    ],
    months: [
      MonthTrend('Sep.', 20000, 15200),
      MonthTrend('Oct.', 24000, 12000),
      MonthTrend('Nov.', 21000, 18900),
      MonthTrend('Dec.', 26000, 20800),
      MonthTrend('Jan.', 28000, 10100),
      MonthTrend('Feb.', 23500, 20700),
    ],
    weeks: [
      MonthTrend('12 May', 5200, 3950),
      MonthTrend('19 May', 6100, 3050),
      MonthTrend('26 May', 4800, 4320),
      MonthTrend('2 Jun', 7400, 2660),
      MonthTrend('9 Jun', 5900, 2120),
    ],
    ledger: [
      TxnEntry('Amazon Pay', '12/06/2026', 1249.00, true, 'Shopping'),
      TxnEntry('Salary credit', '01/06/2026', 42000.00, false, 'Income'),
      TxnEntry('Swiggy', '10/06/2026', 384.00, true, 'Food'),
      TxnEntry('Rahul Sharma', '08/06/2026', 2500.00, true, 'Person'),
      TxnEntry('Netflix', '05/06/2026', 649.00, true, 'Entertainment'),
    ],
    topRecipients: [
      Recipient('Amazon Pay', 8125, 12),
      Recipient('Rahul Sharma', 5400, 6),
      Recipient('Swiggy', 3210, 18),
      Recipient('Netflix', 1947, 3),
    ],
    isDemo: true,
  );
}

class StatementService {
  StatementAnalysis analyze(Uint8List fileBytes, String filename) {
    return OnDeviceAnalysis.analyse(fileBytes, filename);
  }
}

IconData categoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('shop')) return Icons.shopping_basket_rounded;
  if (n.contains('food') || n.contains('dining')) return Icons.restaurant_rounded;
  if (n.contains('entertain')) return Icons.sports_esports_rounded;
  if (n.contains('transfer') || n.contains('person')) return Icons.swap_horiz_rounded;
  if (n.contains('service')) return Icons.miscellaneous_services_rounded;
  if (n.contains('transport') || n.contains('travel')) return Icons.directions_car_rounded;
  if (n.contains('bill') || n.contains('utilit')) return Icons.receipt_long_rounded;
  if (n.contains('health') || n.contains('medic')) return Icons.medical_services_rounded;
  if (n.contains('income') || n.contains('salary')) return Icons.trending_up_rounded;
  if (n.contains('merchant')) return Icons.storefront_rounded;
  if (n.contains('unknown')) return Icons.help_outline_rounded;
  return Icons.payments_rounded;
}

// Chart palette — CashPilot pastels
const chartColors = [
  Color(0xFFC9A9F5), // lavender
  Color(0xFFD7EBBE), // lime
  Color(0xFFF2B8A0), // peach
  Color(0xFFA8D8EA), // sky
  Color(0xFFF5D7A9), // sand
  Color(0xFFE3A9F5), // pink
];
