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
  const _MonthGroup({
    required this.year,
    required this.month,
    required this.invoices,
  });

  Iterable<Invoice> get _live => invoices.where((i) => i.status != 'cancelled');

  double get sales => _live.fold(0.0, (sum, i) => sum + i.grandTotal);
  double get due => _live.fold(0.0, (sum, i) => sum + i.pendingAmount);
  double get received => sales - due;

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
  final _searchFocus = FocusNode();

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
      return _MonthGroup(year: first.year, month: first.month, invoices: e.value);
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
    _searchFocus.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchCtrl.clear();
    _setFilter('All');
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'UPI':
        return Icons.qr_code_2_rounded;
      case 'Cash':
        return Icons.payments_outlined;
      case 'Card':
        return Icons.credit_card_rounded;
      case 'Credit':
        return Icons.receipt_long_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final groups = _buildGroups(_filtered);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/billing'),
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(l10n.newBill,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  size: 19, color: AppColors.primaryLight),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.bills,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary)),
                  Text(l10n.billsSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: l10n.search,
            onPressed: () => _searchFocus.requestFocus(),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: l10n.resetFilters,
            onPressed: _resetFilters,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.searchByCustomerHint,
                  hintStyle: TextStyle(color: c.textHint),
                  prefixIcon: Icon(Icons.search_rounded, color: c.textHint),
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: c.inputBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: c.inputBorder)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Payment mode filter chips — every mode shows its count, even 0.
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
                final fg = active ? Colors.white : c.textPrimary;
                return GestureDetector(
                  onTap: () => _setFilter(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primaryLight : c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: active ? AppColors.primaryLight : c.inputBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_modeIcon(m), size: 15, color: fg),
                        const SizedBox(width: 6),
                        Text(
                          '${_modeFilterLabel(m, l10n)} ${_countFor(m)}',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryLight))
                : groups.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primaryLight,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
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
          Icon(Icons.receipt_long_outlined, size: 56, color: c.textSecondary),
          const SizedBox(height: 12),
          Text(
            _searchCtrl.text.isNotEmpty || _filter != 'All'
                ? context.l10n.noMatchingBills
                : context.l10n.noBillsYet,
            style: TextStyle(color: c.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ── Month Section ─────────────────────────────────────────────────────────────
//
// Expanded: a Total Sales / Received / Due summary row above the month's
// bills. Collapsed: a one-line "Received · Due" recap. Voided bills are
// excluded from every figure.

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
    final now = DateTime.now();
    final isCurrent = group.year == now.year && group.month == now.month;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_month_rounded,
                      size: 18, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.label,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        if (!expanded) ...[
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text:
                                    '${AppFormatters.formatCurrency(group.received)} ${l10n.received}',
                                style: TextStyle(
                                    color: c.success, fontWeight: FontWeight.w600),
                              ),
                              TextSpan(
                                  text: ' · ',
                                  style: TextStyle(color: c.textSecondary)),
                              TextSpan(
                                text:
                                    '${AppFormatters.formatCurrency(group.due)} ${l10n.due}',
                                style: TextStyle(
                                    color: group.due > 0 ? c.danger : c.textSecondary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isCurrent)
                    Text(l10n.thisMonth,
                        style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: isCurrent ? AppColors.primaryLight : c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.trending_up_rounded,
                      color: AppColors.primaryLight,
                      amount: group.sales,
                      label: l10n.totalSales,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.check_circle_outline_rounded,
                      color: c.success,
                      amount: group.received,
                      label: l10n.received,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.error_outline_rounded,
                      color: c.danger,
                      amount: group.due,
                      label: l10n.due,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
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
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double amount;
  final String label;
  const _SummaryCard(
      {required this.icon, required this.color, required this.amount, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(AppFormatters.formatCurrency(amount),
                style: TextStyle(
                    color: color,
                    fontFamily: 'Poppins',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ),
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Invoice Row ────────────────────────────────────────────────────────────────
//
// Who · how much · how paid · paid or due. The whole row opens Bill Details
// (where sharing lives), so there is no per-row share icon.

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  // Resolved from the invoice's customerId against the shop's customer list
  // — null for a walk-in sale, or if the linked customer was since deleted.
  final Customer? customer;
  final bool showDivider;
  const _InvoiceTile({required this.invoice, this.customer, this.showDivider = false});

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
            ],
            Text(text,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );

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

    final voided = invoice.status == 'cancelled';
    final hasDue = invoice.pendingAmount > 0.005;
    final isUpi = invoice.paymentMode.toLowerCase() == 'upi';
    final modeColor = isUpi ? const Color(0xFF2563EB) : c.textSecondary;

    final Widget status;
    if (voided) {
      status = _pill('VOIDED', c.danger);
    } else if (hasDue) {
      status = _pill('${AppFormatters.formatCurrency(invoice.pendingAmount)} ${l10n.due}',
          c.danger);
    } else {
      status = _pill(l10n.paid, c.success, icon: Icons.check_rounded);
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
            customer != null
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.customerName,
                    style: TextStyle(
                        color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pill(localizedPaymentMode(l10n, invoice.paymentMode), modeColor),
                    const SizedBox(width: 4),
                    status,
                  ],
                ),
              ],
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textHint),
          ],
        ),
      ),
    );
  }
}
