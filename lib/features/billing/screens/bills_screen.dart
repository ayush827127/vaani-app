import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/widgets/customer_avatar.dart';
import '../../customers/repositories/customer_repository.dart';
import '../repositories/invoice_repository.dart';
import '../services/invoice_pdf_helper.dart';
import '../../../l10n/l10n_extensions.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// One calendar month's worth of bills — see _buildGroups() below.
class _MonthGroup {
  final int year;
  final int month; // 1-12
  final List<Invoice> invoices;
  final double total;
  const _MonthGroup({
    required this.year,
    required this.month,
    required this.invoices,
    required this.total,
  });

  String get key => '$year-$month';
  String get label => '${_monthNames[month - 1]} $year';
}

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _searchCtrl = TextEditingController();

  List<Invoice> _all = [];
  List<Invoice> _filtered = [];
  Map<int, Customer> _customersById = {};
  bool _loading = true;
  String _filter = 'All';
  int _shopId = 1;

  // Which month groups are expanded — toggled freely by the user and
  // preserved across searches/filter changes (only seeded once, on first
  // load, with the latest month open) rather than recomputed from
  // _filtered every time, so collapsing an older month doesn't spring back
  // open just because the user typed in the search box.
  final Set<String> _expandedMonths = {};
  bool _expandedMonthsSeeded = false;

  static const _modes = ['All', 'Cash', 'UPI', 'Card', 'Credit'];

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      getIt<InvoiceRepository>().getInvoicesByShopWithItemCounts(_shopId, limit: 500),
      getIt<CustomerRepository>().getAllCustomers(_shopId),
    ]);
    if (!mounted) return;
    final invoices = results[0] as List<Invoice>;
    final customers = results[1] as List<Customer>;
    setState(() {
      _all = invoices;
      _customersById = {for (final c in customers) if (c.id != null) c.id!: c};
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((inv) {
        final matchesMode =
            _filter == 'All' || inv.paymentMode.toLowerCase() == _filter.toLowerCase();
        final matchesQuery = q.isEmpty ||
            inv.invoiceNumber.toLowerCase().contains(q) ||
            inv.customerName.toLowerCase().contains(q);
        return matchesMode && matchesQuery;
      }).toList();

      final groups = _buildGroups(_filtered);
      if (!_expandedMonthsSeeded && groups.isNotEmpty) {
        _expandedMonths.add(groups.first.key);
        _expandedMonthsSeeded = true;
      }
    });
  }

  List<_MonthGroup> _buildGroups(List<Invoice> invoices) {
    final byMonth = <String, List<Invoice>>{};
    for (final inv in invoices) {
      final key = '${inv.createdAt.year}-${inv.createdAt.month}';
      byMonth.putIfAbsent(key, () => []).add(inv);
    }
    final groups = byMonth.entries.map((e) {
      final first = e.value.first.createdAt;
      final total = e.value.fold(0.0, (sum, inv) => sum + inv.grandTotal);
      return _MonthGroup(year: first.year, month: first.month, invoices: e.value, total: total);
    }).toList();
    // Invoices already come newest-first from the DB query, but sort groups
    // explicitly too since Map iteration order isn't guaranteed to follow it.
    groups.sort((a, b) {
      final byYear = b.year.compareTo(a.year);
      return byYear != 0 ? byYear : b.month.compareTo(a.month);
    });
    return groups;
  }

  void _toggleMonth(String key) {
    setState(() {
      if (_expandedMonths.contains(key)) {
        _expandedMonths.remove(key);
      } else {
        _expandedMonths.add(key);
      }
    });
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _applyFilter();
  }

  int _countFor(String mode) => mode == 'All'
      ? _all.length
      : _all.where((inv) => inv.paymentMode.toLowerCase() == mode.toLowerCase()).length;

  String _modeFilterLabel(String mode, AppLocalizations l10n) {
    switch (mode) {
      case 'All':
        return l10n.all;
      case 'Cash':
        return l10n.cash;
      case 'UPI':
        return l10n.upi;
      case 'Card':
        return l10n.card;
      case 'Credit':
        return l10n.credit;
      default:
        return mode;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final groups = _buildGroups(_filtered);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/billing'),
        backgroundColor: AppColors.primaryLight,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: Text(l10n.bills),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.searchByCustomerHint,
                hintStyle: TextStyle(color: c.textHint),
                prefixIcon:
                    Icon(Icons.search_rounded, color: c.textHint),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.inputBorder)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Payment mode filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _modes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final m = _modes[i];
                final active = _filter == m;
                final count = _countFor(m);
                return GestureDetector(
                  onTap: () => _setFilter(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primaryLight
                          : c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? AppColors.primaryLight
                            : c.inputBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _modeFilterLabel(m, l10n),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : c.textSecondary),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '$count',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : c.textHint),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Month-grouped list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryLight))
                : groups.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primaryLight,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                          itemCount: groups.length,
                          itemBuilder: (_, i) => _MonthSection(
                            group: groups[i],
                            expanded: _expandedMonths.contains(groups[i].key),
                            customersById: _customersById,
                            onToggle: () => _toggleMonth(groups[i].key),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final c = context.colors;
    return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: c.textSecondary),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty || _filter != 'All'
                  ? context.l10n.noMatchingBills
                  : context.l10n.noBillsYet,
              style: TextStyle(
                  color: c.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
  }
}

// ── Month Section ─────────────────────────────────────────────────────────────
//
// A tappable header ("September 2026 — ₹100 · 2 bills") that expands or
// collapses its bills — the PhonePe/Google-Pay-style grouping this screen
// replaced a flat "21 bills / total sales" summary block with. The current
// month starts expanded; older ones start collapsed (see
// _BillsScreenState._applyFilter's seeding of _expandedMonths).

class _MonthSection extends StatelessWidget {
  final _MonthGroup group;
  final bool expanded;
  final Map<int, Customer> customersById;
  final VoidCallback onToggle;

  const _MonthSection({
    required this.group,
    required this.expanded,
    required this.customersById,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.label,
                      style: TextStyle(
                          color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    AppFormatters.formatCurrency(group.total),
                    style: TextStyle(
                        color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${l10n.billsCountLabel(group.invoices.length)}',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(
                children: [
                  for (var i = 0; i < group.invoices.length; i++)
                    _InvoiceTile(
                      invoice: group.invoices[i],
                      customer: group.invoices[i].customerId != null
                          ? customersById[group.invoices[i].customerId]
                          : null,
                      showDivider: i > 0,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Invoice Row ────────────────────────────────────────────────────────────────
//
// Flat list row (no per-row border/shadow) with a divider above every row
// but the first in its month — the "clean white list with subtle
// separators" look, rather than a stack of individually-boxed cards.

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  // Resolved from the invoice's customerId against the shop's customer list
  // — null for a walk-in sale, or if the linked customer was since deleted.
  final Customer? customer;
  final bool showDivider;
  const _InvoiceTile({required this.invoice, this.customer, this.showDivider = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final items = invoice.itemCount ?? invoice.items.length;
    final itemLabel = items == 1 ? '1 item' : '$items items';

    final now = DateTime.now();
    final diff = now.difference(invoice.createdAt);
    final String dateLabel;
    if (diff.inDays == 0) {
      dateLabel = AppFormatters.formatTime(invoice.createdAt);
    } else if (diff.inDays == 1) {
      dateLabel = l10n.yesterdayAt(AppFormatters.formatTime(invoice.createdAt));
    } else {
      dateLabel = AppFormatters.formatDate(invoice.createdAt);
    }

    return InkWell(
      onTap: () => context.push('/bills/${invoice.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: showDivider
            ? BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: 1)))
            : null,
        child: Row(
          children: [
            GestureDetector(
              onTap: customer != null
                  ? () => context.push('/customers/${customer!.id}')
                  : null,
              child: customer != null
                  ? CustomerAvatar(customer: customer!, size: 38, color: AppColors.primary)
                  : Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.textHint.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded, color: c.textHint, size: 20),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          invoice.customerName,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (invoice.status == 'cancelled') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('VOIDED',
                              style: TextStyle(
                                  color: c.danger, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemLabel · $dateLabel',
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.formatCurrency(invoice.grandTotal),
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  localizedPaymentMode(l10n, invoice.paymentMode),
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  InvoicePdfHelper.shareById(context, invoice.id!, invoice.shopId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(Icons.share_outlined, color: c.textSecondary, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
