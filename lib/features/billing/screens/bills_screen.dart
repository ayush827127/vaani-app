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
      getIt<InvoiceRepository>().getInvoicesByShop(_shopId, limit: 200),
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
    });
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _applyFilter();
  }

  int _countFor(String mode) => mode == 'All'
      ? _all.length
      : _all.where((inv) => inv.paymentMode.toLowerCase() == mode.toLowerCase()).length;

  double get _filteredTotal => _filtered.fold(0.0, (sum, inv) => sum + inv.grandTotal);

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
          // Summary bar — how many bills and how much they add up to for
          // whatever's currently filtered/searched, so the list isn't just a
          // flat scroll with no sense of the total until you count by hand.
          if (!_loading && _filtered.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    l10n.billsCount(_filtered.length),
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    AppFormatters.formatCurrency(_filteredTotal),
                    style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryLight))
                : _filtered.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primaryLight,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _InvoiceTile(
                            invoice: _filtered[i],
                            customer: _filtered[i].customerId != null
                                ? _customersById[_filtered[i].customerId]
                                : null,
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

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  // Resolved from the invoice's customerId against the shop's customer list
  // — null for a walk-in sale, or if the linked customer was since deleted.
  final Customer? customer;
  const _InvoiceTile({required this.invoice, this.customer});

  static const _modeIcons = {
    'cash': Icons.payments_rounded,
    'upi': Icons.phone_android_rounded,
    'card': Icons.credit_card_rounded,
    'credit': Icons.account_balance_wallet_rounded,
  };

  static const _modeColors = {
    'cash': Color(0xFF16A34A),
    'upi': Color(0xFF7C3AED),
    'card': Color(0xFF2563EB),
    'credit': Color(0xFFEA580C),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final mode = invoice.paymentMode.toLowerCase();
    final modeColor = _modeColors[mode] ?? AppColors.primary;
    final modeIcon = _modeIcons[mode] ?? Icons.payment_rounded;

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

    return GestureDetector(
      onTap: () => context.push('/bills/${invoice.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: Row(
          children: [
            // Customer avatar — the customer's own photo when they have one
            // synced, their initial otherwise, or a generic person icon for
            // a walk-in sale with no linked customer at all. Tapping it
            // jumps straight to that customer's profile without having to
            // open the bill first. A small dot in the corner keeps the
            // payment-mode cue that used to be the icon here.
            GestureDetector(
              onTap: customer != null
                  ? () => context.push('/customers/${customer!.id}')
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  customer != null
                      ? CustomerAvatar(customer: customer!, size: 42, color: AppColors.primary)
                      : Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: c.textHint.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_rounded, color: c.textHint, size: 22),
                        ),
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: modeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                      child: Icon(modeIcon, color: Colors.white, size: 9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Invoice info
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
                              fontSize: 14,
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
                            color: c.danger.withValues(alpha: 0.12),
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
                    invoice.invoiceNumber,
                    style: TextStyle(
                        color: c.textDisabled,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 2),
                  Text(dateLabel,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.formatCurrency(invoice.grandTotal),
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    localizedPaymentMode(l10n, invoice.paymentMode).toUpperCase(),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: modeColor),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () =>
                  InvoicePdfHelper.shareById(context, invoice.id!, invoice.shopId),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(Icons.share_rounded,
                    color: AppColors.primaryLight, size: 18),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: c.textDisabled, size: 18),
          ],
        ),
      ),
    );
  }
}
