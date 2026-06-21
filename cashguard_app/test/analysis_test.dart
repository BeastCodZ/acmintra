import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashguard_app/services/ondevice_analysis.dart';
import 'package:cashguard_app/services/statement_service.dart';

StatementAnalysis run(String html) =>
    OnDeviceAnalysis.analyse(utf8.encode(html), 'statement.html');

void main() {
  test('Basic income + spend parsing', () {
    const html = '''
      <tr><td>01/06/2026</td><td>SALARY CREDIT ACME CORP</td><td>INR 65000.00</td></tr>
      <tr><td>03/06/2026</td><td>UPI/SWIGGY/swiggy@axis</td><td>INR 482.00</td></tr>
      <tr><td>05/06/2026</td><td>UPI/AMAZON/amazon@apl</td><td>INR 1299.00</td></tr>
      <tr><td>08/06/2026</td><td>UPI/9876543210@ybl SENT TO</td><td>INR 2500.00</td></tr>
    ''';
    final a = run(html);
    print('income=${a.totalIncome} spend=${a.totalSpend} health=${a.healthScore} conf=${a.scoreConfidence}');
    expect(a.totalIncome, 65000);
    expect(a.totalSpend, 482 + 1299 + 2500);
    expect(a.personTransfers, 2500);
    expect(a.scoreConfidence, lessThan(100)); // single month → stability not scored
  });

  test('Transfers & investments are NOT counted as spend', () {
    const html = '''
      <tr><td>01/06/2026</td><td>SALARY CREDIT</td><td>INR 100000.00</td></tr>
      <tr><td>02/06/2026</td><td>UPI/SWIGGY</td><td>INR 500.00</td></tr>
      <tr><td>03/06/2026</td><td>CREDIT CARD PAYMENT HDFC</td><td>INR 25000.00</td></tr>
      <tr><td>04/06/2026</td><td>SIP MUTUAL FUND GROWW</td><td>INR 15000.00</td></tr>
      <tr><td>05/06/2026</td><td>ADD MONEY PAYTM WALLET</td><td>INR 2000.00</td></tr>
    ''';
    final a = run(html);
    print('income=${a.totalIncome} spend=${a.totalSpend} invest=${a.investments} transfers=${a.transfersExcluded}');
    // Only the ₹500 Swiggy is real consumption
    expect(a.totalSpend, 500);
    expect(a.investments, 15000);
    expect(a.transfersExcluded, 25000 + 2000);
    // Savings rate should be (100000-500)/100000 ≈ 99.5%, NOT wrecked by the CC payment
    expect(a.savingsRate, greaterThan(0.98));
  });

  test('Refunds offset spend instead of inflating income', () {
    const html = '''
      <tr><td>01/06/2026</td><td>SALARY</td><td>INR 50000.00</td></tr>
      <tr><td>02/06/2026</td><td>AMAZON SHOPPING</td><td>INR 3000.00</td></tr>
      <tr><td>03/06/2026</td><td>AMAZON REFUND</td><td>INR 1000.00</td></tr>
    ''';
    final a = run(html);
    print('income=${a.totalIncome} spend=${a.totalSpend} refunds=${a.refunds}');
    expect(a.totalIncome, 50000);       // refund NOT added to income
    expect(a.totalSpend, 3000 - 1000);  // refund nets off spend → 2000
    expect(a.refunds, 1000);
  });

  test('Multi-month statement scores stability (full confidence)', () {
    const html = '''
      <tr><td>05/04/2026</td><td>SALARY</td><td>INR 60000.00</td></tr>
      <tr><td>10/04/2026</td><td>SWIGGY</td><td>INR 2000.00</td></tr>
      <tr><td>05/05/2026</td><td>SALARY</td><td>INR 60000.00</td></tr>
      <tr><td>10/05/2026</td><td>SWIGGY</td><td>INR 2100.00</td></tr>
      <tr><td>05/06/2026</td><td>SALARY</td><td>INR 60000.00</td></tr>
      <tr><td>10/06/2026</td><td>SWIGGY</td><td>INR 1950.00</td></tr>
    ''';
    final a = run(html);
    print('monthsCovered=${a.monthsCovered} conf=${a.scoreConfidence} health=${a.healthScore}');
    expect(a.monthsCovered, 3);
    expect(a.scoreConfidence, 100); // all dimensions scorable
  });

  test('No income → score is honest, not a fake 50', () {
    const html = '''
      <tr><td>02/06/2026</td><td>SWIGGY</td><td>INR 500.00</td></tr>
      <tr><td>03/06/2026</td><td>AMAZON</td><td>INR 1200.00</td></tr>
    ''';
    final a = run(html);
    print('income=${a.totalIncome} health=${a.healthScore} conf=${a.scoreConfidence}');
    expect(a.totalIncome, 0);
    expect(a.scoreConfidence, lessThan(60)); // savings+expense dims unavailable
    expect(a.insights.any((i) => i.contains('No income')), isTrue);
  });

  // Kotak cell-per-line format: Syncfusion extracts each PDF table cell as a
  // separate line. Balance arithmetic must determine debit vs credit since the
  // Dr/Cr column position is lost in text extraction.
  test('Kotak cell-per-line: balance arithmetic classifies Dr vs Cr', () {
    // This matches exactly what Syncfusion produces from a Kotak PDF:
    // serial / date / narration / ref / amount / balance — each on its own line.
    const text = '''
Savings Account Transactions
#
Date
Description
Chq/Ref. No.
Withdrawal (Dr.)
Deposit (Cr.)
Balance
-
-
Opening Balance
-
-
-
50,026.07
1
01 Dec 2025
Recd:IMPS/533507426564/VAISHALITR/KKBK/X9120/IMPS
IMPS-533510863219
820.00
50,846.07
2
01 Dec 2025
UPI/DARSH PRAKASH/114946646527/UPI
UPI-533558112399
820.00
50,026.07
3
01 Dec 2025
UPI/Saesha Khanna/570118980532/UPIPayment
UPI-533589822600
500.00
50,526.07
4
01 Dec 2025
UPI/DARSH PRAKASH/114969926670/UPI
UPI-533589873618
500.00
50,026.07
12
18 Dec 2025
T36975314-17655091246333DK ICICIAMC -ASBA
12,990.00
37,036.07
15
23 Dec 2025
IFT-KOTAK SECURITIES LIMITED -FCM-251223KDLI3H
FCM-251223KDLI3H
17,000.00
54,036.07
23
31 Dec 2025
Int.Pd:9247583956:01-10-2025 to 31-12-2025
541.00
54,577.07
''';
    final a = OnDeviceAnalysis.analyse(utf8.encode(text), 'statement.html');
    print('income=${a.totalIncome} spend=${a.totalSpend} invest=${a.investments}');
    // Credits (balance went UP): txn1=820, txn3=500, txn15=17000, txn23=541
    expect(a.totalIncome, closeTo(820 + 500 + 17000 + 541, 1));
    // Debits that are plain spend (balance went DOWN, not investment keyword):
    // txn2=820, txn4=500
    expect(a.totalSpend, closeTo(820 + 500, 5));
    // Txn12 ICICIAMC ASBA = investment (debit + investment keyword)
    expect(a.investments, closeTo(12990, 1));
  });
}
