import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/payment_transaction.dart';
import '../repositories/customer_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../billing/repositories/payment_transaction_repository.dart';
import '../../billing/widgets/collect_payment_sheet.dart';
import '../../billing/services/invoice_pdf_helper.dart';
import '../../../l10n/l10n_extensions.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final int customerId;
  const CustomerDetailsScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen>
    with SingleTickerProviderStateMixin {
  Customer? _customer;
  List<Invoice> _invoices = [];
  List<Invoice> _outstandingInvoices = [];
  List<PaymentTransaction> _transactions = [];
  bool _isLoading = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double get _pendingTotal =>
      _outstandingInvoices.fold(0.0, (sum, inv) => sum + inv.pendingAmount);

  Future<void> _load() async {
    final customerRepo = getIt<CustomerRepository>();
    final invoiceRepo = getIt<InvoiceRepository>();
    final txnRepo = getIt<PaymentTransactionRepository>();
    final results = await Future.wait([
      customerRepo.getCustomerById(widget.customerId),
      invoiceRepo.getInvoicesByCustomer(widget.customerId),
      invoiceRepo.getOutstandingInvoicesByCustomer(widget.customerId),
      txnRepo.getByCustomer(widget.customerId, limit: 200),
    ]);
    if (!mounted) return;
    setState(() {
      _customer = results[0] as Customer?;
      _invoices = (results[1] as List).cast<Invoice>();
      _outstandingInvoices = (results[2] as List).cast<Invoice>();
      _transactions = (results[3] as List).cast<PaymentTransaction>();
      _isLoading = false;
    });
  }

  void _openCollectPayment() {
    final cust = _customer;
    if (cust == null) return;
    showCollectPaymentSheet(
      context: context,
      customer: cust,
      shopId: cust.shopId,
      onSuccess: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    final cust = _customer;
    final c = context.colors;
    final l10n = context.l10n;
    if (cust == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(l10n.customerNotFound, style: TextStyle(color: c.textPrimary)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(cust.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: c.textSecondary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: l10n.overview),
            Tab(text: l10n.allInvoices),
            Tab(text: l10n.paymentHistory),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCollectPayment,
        backgroundColor: AppColors.primaryLight,
        icon: const Icon(Icons.payments_rounded, color: Colors.white),
        label: Text(
          l10n.collectPayment,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(
            customer: cust,
            pendingTotal: _pendingTotal,
            onCollect: _openCollectPayment,
          ),
          _InvoicesTab(invoices: _invoices),
          _HistoryTab(transactions: _transactions),
        ],
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Customer customer;
  final double pendingTotal;
  final VoidCallback onCollect;

  const _OverviewTab({
    required this.customer,
    required this.pendingTotal,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final hasBalance = customer.totalOutstanding > 0 || customer.advanceBalance > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.surfaceBorder),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    customer.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary),
                      ),
                      if (customer.phone != null)
                        Text(customer.phone!, style: TextStyle(color: c.textSecondary)),
                      if (customer.lastVisit != null)
                        Text(
                          l10n.lastVisit(AppFormatters.formatDate(customer.lastVisit!)),
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4-stat grid: Total Business, Total Bills, Outstanding, Advance
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _StatCard(
                value: AppFormatters.formatCurrency(customer.totalPurchases),
                label: l10n.totalBusiness,
                color: AppColors.primaryLight,
                icon: Icons.trending_up_rounded,
                c: c,
              ),
              _StatCard(
                value: '${customer.totalBills}',
                label: l10n.totalBills,
                color: c.success,
                icon: Icons.receipt_long_rounded,
                c: c,
              ),
              _StatCard(
                value: AppFormatters.formatCurrency(customer.totalOutstanding),
                label: l10n.outstanding,
                color: const Color(0xFFFF6B00),
                icon: Icons.warning_amber_rounded,
                c: c,
              ),
              _StatCard(
                value: AppFormatters.formatCurrency(pendingTotal),
                label: l10n.pending,
                color: const Color(0xFFFF8C00),
                icon: Icons.hourglass_bottom_rounded,
                c: c,
              ),
            ],
          ),

          // Balance card with advance + collect payment
          if (hasBalance) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.balanceSummary,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  if (customer.totalOutstanding > 0)
                    _BalanceRow(
                      icon: Icons.warning_amber_rounded,
                      label: l10n.outstanding,
                      value: AppFormatters.formatCurrency(customer.totalOutstanding),
                      color: const Color(0xFFFF6B00),
                    ),
                  if (customer.totalOutstanding > 0 && customer.advanceBalance > 0)
                    const SizedBox(height: 10),
                  if (customer.advanceBalance > 0)
                    _BalanceRow(
                      icon: Icons.account_balance_wallet_rounded,
                      label: l10n.advanceBalance,
                      value: AppFormatters.formatCurrency(customer.advanceBalance),
                      color: c.success,
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCollect,
                      icon: const Icon(Icons.payments_rounded,
                          size: 16, color: AppColors.primaryLight),
                      label: Text(
                        l10n.collectPayment,
                        style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primaryLight),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
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

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;
  final dynamic c;

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label,
              style: TextStyle(color: c.textSecondary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Invoices Tab ──────────────────────────────────────────────────────────────

class _InvoicesTab extends StatelessWidget {
  final List<Invoice> invoices;

  const _InvoicesTab({required this.invoices});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: c.textHint),
            const SizedBox(height: 12),
            Text(l10n.noInvoicesYet, style: TextStyle(color: c.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: invoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _InvoiceTile(invoice: invoices[i]),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final inv = invoice;

    final isPaid = inv.status == 'paid';
    final isPartial = inv.status == 'partial_paid';
    final isCancelled = inv.status == 'cancelled';
    final statusColor = isPaid
        ? c.success
        : isPartial
            ? const Color(0xFFFF8C00)
            : isCancelled
                ? c.textHint
                : c.danger;
    final statusLabel = isPaid
        ? l10n.paid
        : isPartial
            ? l10n.partialPaid
            : isCancelled
                ? 'Voided'
                : l10n.unpaid;

    return InkWell(
      onTap: () => context.push('/bills/${inv.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isPaid
                  ? c.surfaceBorder
                  : statusColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Invoice number + status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    inv.invoiceNumber,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => InvoicePdfHelper.shareById(
                      context, inv.id!, inv.shopId),
                  child: const Icon(Icons.share_rounded,
                      size: 16, color: AppColors.primaryLight),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: Date + Grand total
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 12, color: c.textHint),
                const SizedBox(width: 4),
                Text(
                  AppFormatters.formatDate(inv.createdAt),
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  AppFormatters.formatCurrency(inv.grandTotal),
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ],
            ),
            // Row 3: Pending due + payment mode
            const SizedBox(height: 6),
            Row(
              children: [
                if (!isPaid && inv.pendingAmount > 0) ...[
                  Icon(Icons.timer_outlined, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    '${l10n.due}: ${AppFormatters.formatCurrency(inv.pendingAmount)}',
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    inv.paymentMode.toUpperCase(),
                    style: TextStyle(color: c.textHint, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final List<PaymentTransaction> transactions;

  const _HistoryTab({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 56, color: c.textHint),
            const SizedBox(height: 12),
            Text(l10n.noPaymentHistoryYet,
                style: TextStyle(color: c.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _TxnTile(txn: transactions[i]),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final PaymentTransaction txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final (icon, color, label) = _meta(txn.type, c, l10n);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      AppFormatters.formatDate(txn.createdAt),
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        txn.paymentMode.toUpperCase(),
                        style: TextStyle(color: c.textHint, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            AppFormatters.formatCurrency(txn.amount),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _meta(String type, dynamic c, dynamic l10n) {
    switch (type) {
      case 'bill_payment':
        return (Icons.receipt_long_rounded, AppColors.primaryLight, l10n.billPayment as String);
      case 'advance_used':
        return (
          Icons.account_balance_wallet_rounded,
          const Color(0xFF6B46C1),
          l10n.advanceUsed as String
        );
      case 'outstanding_collection':
        return (
          Icons.check_circle_rounded,
          const Color(0xFFFF8C00),
          l10n.outstandingCollected as String
        );
      case 'advance_deposit':
        return (Icons.add_card_rounded, c.success as Color, l10n.advanceDeposit as String);
      case 'refund':
        return (Icons.replay_rounded, c.success as Color, 'Refund (voided/returned bill)');
      default:
        return (Icons.payments_rounded, c.textSecondary as Color, type);
    }
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _BalanceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BalanceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      );
}
