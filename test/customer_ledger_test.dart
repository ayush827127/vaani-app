import 'package:flutter_test/flutter_test.dart';
import 'package:vaani/features/customers/customer_ledger.dart';
import 'package:vaani/shared/models/customer.dart';

Customer c(String name,
        {String? phone,
        double due = 0,
        double advance = 0,
        DateTime? visit,
        DateTime? created}) =>
    Customer(
      shopId: 1,
      name: name,
      phone: phone,
      totalOutstanding: due,
      advanceBalance: advance,
      lastVisit: visit,
      createdAt: created ?? DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final aditya = c('Aditya Singh', phone: '9472946170', due: 120, visit: DateTime(2026, 9, 19));
  final ujjawal = c('Ujjawal Singh', phone: '9846431819', advance: 150, visit: DateTime(2026, 8, 22));
  final gyandeep = c('gyandeep', phone: '6202368917', visit: DateTime(2026, 7, 10));
  final rahul = c('Rahul Kumar', phone: '9123456780', due: 75, visit: DateTime(2026, 9, 5));
  final pankaj = c('Pankaj Verma', phone: '8987654321', advance: 200, visit: DateTime(2026, 8, 28));
  final mohit = c('Mohit Sharma', phone: '9301234567', visit: DateTime(2026, 9, 12));
  final all = [aditya, ujjawal, gyandeep, rahul, pankaj, mohit];

  test('one net balance per customer: due and advance are never both shown', () {
    expect(netBalance(aditya), 120);
    expect(netBalance(ujjawal), -150);
    expect(netBalance(gyandeep), 0);
    // Both stored fields set — netted, not shown twice.
    expect(netBalance(c('X', due: 500, advance: 200)), 300);
    expect(netBalance(c('Y', due: 200, advance: 500)), -300);
    expect(netBalance(c('Z', due: 200, advance: 200)), 0);
  });

  test('summary totals use net balances', () {
    final s = summarize([...all, c('Both', due: 100, advance: 40)]);
    expect(s.totalDue, 120 + 75 + 60);
    expect(s.dueCount, 3);
    expect(s.totalAdvance, 150 + 200);
    expect(s.advanceCount, 2);
  });

  test('filters split the list by financial state', () {
    List<String> names(LedgerFilter f) =>
        applyLedgerView(all, filter: f, sort: LedgerSort.nameAZ).map((x) => x.name).toList();
    expect(names(LedgerFilter.all).length, 6);
    expect(names(LedgerFilter.withDue), ['Aditya Singh', 'Rahul Kumar']);
    expect(names(LedgerFilter.withAdvance), ['Pankaj Verma', 'Ujjawal Singh']);
    expect(names(LedgerFilter.settled), ['gyandeep', 'Mohit Sharma']);
  });

  test('search matches name (any case) or phone digits', () {
    expect(applyLedgerView(all, query: 'SINGH').length, 2);
    expect(applyLedgerView(all, query: '9846').single.name, 'Ujjawal Singh');
    expect(applyLedgerView(all, query: 'zzz'), isEmpty);
    expect(applyLedgerView(all, query: 'singh', filter: LedgerFilter.withDue).single.name,
        'Aditya Singh');
  });

  test('sorting', () {
    List<String> order(LedgerSort s) => applyLedgerView(all, sort: s).map((x) => x.name).toList();
    expect(order(LedgerSort.recent).first, 'Aditya Singh');
    expect(order(LedgerSort.recent).last, 'gyandeep');
    expect(order(LedgerSort.oldest).first, 'gyandeep');
    expect(order(LedgerSort.highestDue).take(2), ['Aditya Singh', 'Rahul Kumar']);
    expect(order(LedgerSort.highestAdvance).take(2), ['Pankaj Verma', 'Ujjawal Singh']);
    expect(order(LedgerSort.nameAZ).first, 'Aditya Singh');
    expect(order(LedgerSort.nameAZ)[1], 'gyandeep');
  });
}
