import '../../shared/models/customer.dart';

/// Ledger view of a customer list — the Customers screen is about who owes
/// money and who has credit, so everything here is derived from one net
/// balance per customer rather than from activity categories.

enum LedgerFilter { all, withDue, withAdvance, settled }

enum LedgerSort { recent, oldest, highestDue, highestAdvance, nameAZ }

/// A customer's single ledger balance: positive = they owe the shop (Due),
/// negative = the shop holds their money (Advance), zero = settled.
///
/// The database keeps outstanding and advance as two separate fields (the
/// billing flows need them separate), and they can legitimately both be
/// non-zero — e.g. a "Give Credit" entry on a customer who has advance on
/// file. For display they're netted, so a customer is never shown as owing
/// and being owed at the same time.
double netBalance(Customer c) {
  final net = c.totalOutstanding - c.advanceBalance;
  return net.abs() < 0.005 ? 0 : net;
}

DateTime lastActivity(Customer c) => c.lastVisit ?? c.createdAt;

class LedgerSummary {
  final double totalDue;
  final int dueCount;
  final double totalAdvance;
  final int advanceCount;
  const LedgerSummary({
    required this.totalDue,
    required this.dueCount,
    required this.totalAdvance,
    required this.advanceCount,
  });
}

LedgerSummary summarize(Iterable<Customer> customers) {
  double due = 0, advance = 0;
  int dueCount = 0, advanceCount = 0;
  for (final c in customers) {
    final net = netBalance(c);
    if (net > 0) {
      due += net;
      dueCount++;
    } else if (net < 0) {
      advance += -net;
      advanceCount++;
    }
  }
  return LedgerSummary(
    totalDue: due,
    dueCount: dueCount,
    totalAdvance: advance,
    advanceCount: advanceCount,
  );
}

bool matchesFilter(Customer c, LedgerFilter f) {
  final net = netBalance(c);
  switch (f) {
    case LedgerFilter.all:
      return true;
    case LedgerFilter.withDue:
      return net > 0;
    case LedgerFilter.withAdvance:
      return net < 0;
    case LedgerFilter.settled:
      return net == 0;
  }
}

bool matchesQuery(Customer c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q);
}

/// Search, filter and sort in one pass over the already-loaded list, so every
/// keystroke / chip tap / sort change updates the screen instantly with no
/// database round trip.
List<Customer> applyLedgerView(
  List<Customer> all, {
  String query = '',
  LedgerFilter filter = LedgerFilter.all,
  LedgerSort sort = LedgerSort.recent,
}) {
  final list =
      all.where((c) => matchesQuery(c, query) && matchesFilter(c, filter)).toList();
  int byName(Customer a, Customer b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  switch (sort) {
    case LedgerSort.recent:
      list.sort((a, b) {
        final d = lastActivity(b).compareTo(lastActivity(a));
        return d != 0 ? d : byName(a, b);
      });
    case LedgerSort.oldest:
      list.sort((a, b) {
        final d = lastActivity(a).compareTo(lastActivity(b));
        return d != 0 ? d : byName(a, b);
      });
    case LedgerSort.highestDue:
      list.sort((a, b) {
        final d = netBalance(b).compareTo(netBalance(a));
        return d != 0 ? d : byName(a, b);
      });
    case LedgerSort.highestAdvance:
      list.sort((a, b) {
        final d = netBalance(a).compareTo(netBalance(b));
        return d != 0 ? d : byName(a, b);
      });
    case LedgerSort.nameAZ:
      list.sort(byName);
  }
  return list;
}
