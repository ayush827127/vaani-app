import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/payment_transaction.dart';
import '../../../shared/widgets/customer_avatar.dart';
import '../repositories/customer_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../billing/repositories/payment_transaction_repository.dart';
import '../../billing/widgets/collect_payment_sheet.dart';
import '../../billing/widgets/give_credit_sheet.dart';
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

  Future<void> _load() async {
    final customerRepo = getIt<CustomerRepository>();
    final invoiceRepo = getIt<InvoiceRepository>();
    final txnRepo = getIt<PaymentTransactionRepository>();
    final results = await Future.wait([
      customerRepo.getCustomerById(widget.customerId),
      invoiceRepo.getInvoicesByCustomer(widget.customerId),
      txnRepo.getByCustomer(widget.customerId, limit: 200),
    ]);
    if (!mounted) return;
    setState(() {
      _customer = results[0] as Customer?;
      _invoices = (results[1] as List).cast<Invoice>();
      _transactions = (results[2] as List).cast<PaymentTransaction>();
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

  void _openGiveCredit() {
    final cust = _customer;
    if (cust == null) return;
    showGiveCreditSheet(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: l10n.editCustomer,
            onPressed: () async {
              final updated = await context.push('/customers/${cust.id}/edit', extra: cust);
              if (updated == true) _load();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: c.textSecondary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: l10n.overview),
            Tab(text: l10n.allInvoices),
            Tab(text: l10n.ledger),
          ],
        ),
      ),
      // Khata-style "You Gave / You Got" pair, not a single FAB — the whole
      // point of a ledger is that both directions are equally one tap away,
      // not one primary action with the other buried in a tab.
      bottomNavigationBar: _LedgerActionBar(
        onGiveCredit: _openGiveCredit,
        onCollectPayment: _openCollectPayment,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(customer: cust),
          _InvoicesTab(invoices: _invoices),
          _LedgerTab(transactions: _transactions, currentOutstanding: cust.totalOutstanding),
        ],
      ),
    );
  }
}

class _LedgerActionBar extends StatelessWidget {
  final VoidCallback onGiveCredit;
  final VoidCallback onCollectPayment;

  const _LedgerActionBar({required this.onGiveCredit, required this.onCollectPayment});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    const danger = Color(0xFFE24C4C);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onGiveCredit,
                icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: danger),
                label: Text(l10n.youGave,
                    style: const TextStyle(
                        color: danger, fontSize: 13, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onCollectPayment,
                icon: const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white),
                label: Text(l10n.youGot,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.success,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Customer customer;

  const _OverviewTab({required this.customer});

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
                CustomerAvatar(customer: customer, size: 64, color: AppColors.primary),
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

          // Total Sales / Total Bills side by side, then the customer's total
          // Outstanding on its own. There is deliberately no separate
          // "Pending" figure here: pending is a per-bill amount (shown on
          // each bill and in the billing payment screen), and summing it
          // here just showed the same number as Outstanding under a second
          // name.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatCard(
                    value: AppFormatters.formatCurrency(customer.totalPurchases),
                    label: l10n.totalSales,
                    color: AppColors.primaryLight,
                    icon: Icons.trending_up_rounded,
                    c: c,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    value: l10n.billsCountLabel(customer.totalBills),
                    label: l10n.totalBills,
                    color: c.success,
                    icon: Icons.receipt_long_rounded,
                    c: c,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatCard(
            value: AppFormatters.formatCurrency(customer.totalOutstanding),
            label: l10n.outstanding,
            color: const Color(0xFFFF6B00),
            icon: Icons.warning_amber_rounded,
            c: c,
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
                  // No action buttons here — the persistent "You Gave / You
                  // Got" bar at the bottom of this screen already covers
                  // both directions on every tab; repeating one of them
                  // here would just be a second, redundant button.
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
                    '${l10n.pending}: ${AppFormatters.formatCurrency(inv.pendingAmount)}',
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

// ── Ledger Tab ────────────────────────────────────────────────────────────────

// Effect of each transaction type on the customer's OUTSTANDING balance —
// must mirror invoice_repository.dart's write paths exactly (createInvoice's
// 'invoice_due' insert, collectPayment's 'outstanding_collection', giveCredit's
// 'manual_credit', _reverseInvoiceItems' 'invoice_due_reversal') since this is
// purely a display-side reconstruction of a value the database already holds
// as customer.totalOutstanding — it has to reproduce the same arithmetic to
// walk it backward correctly.
double _outstandingDelta(PaymentTransaction txn) {
  switch (txn.type) {
    case 'invoice_due':
    case 'manual_credit':
      return txn.amount;
    case 'outstanding_collection':
    case 'invoice_due_reversal':
      return -txn.amount;
    default:
      return 0;
  }
}

class _LedgerTab extends StatelessWidget {
  final List<PaymentTransaction> transactions;
  final double currentOutstanding;

  const _LedgerTab({required this.transactions, required this.currentOutstanding});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: c.textHint),
            const SizedBox(height: 12),
            Text(l10n.noLedgerEntriesYet, style: TextStyle(color: c.textSecondary)),
          ],
        ),
      );
    }

    // transactions is newest-first (PaymentTransactionRepository.getByCustomer
    // orders by created_at DESC) — walk it in that order starting from the
    // customer's current balance, subtracting each entry's own effect to
    // arrive at the balance that stood just before it (i.e. just after the
    // next-older entry). Only accurate back as far as this list actually
    // reaches (capped at 200 rows) — a customer with a longer history will
    // see correct balances for their most recent 200 entries and a slightly
    // drifted figure beyond that, which is an acceptable trade for not
    // needing to load/compute over an unbounded transaction history.
    final runningBalances = <double>[];
    double runningAfter = currentOutstanding;
    for (final txn in transactions) {
      runningBalances.add(runningAfter);
      runningAfter -= _outstandingDelta(txn);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) =>
          _TxnTile(txn: transactions[i], balanceAfter: runningBalances[i]),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final PaymentTransaction txn;
  final double balanceAfter;
  const _TxnTile({required this.txn, required this.balanceAfter});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final (icon, color, label, isDebit) = _meta(txn.type, c, l10n);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                if (txn.notes != null && txn.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(txn.notes!,
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isDebit ? '+' : '-'}${AppFormatters.formatCurrency(txn.amount)}',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                '${l10n.balance}: ${AppFormatters.formatCurrency(balanceAfter)}',
                style: TextStyle(color: c.textHint, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // isDebit = true when this entry increases what the customer owes
  // (shown with a '+' prefix, matching the "You Gave" framing); false when
  // it reduces it or has no effect on outstanding at all.
  (IconData, Color, String, bool) _meta(String type, dynamic c, dynamic l10n) {
    const danger = Color(0xFFE24C4C);
    switch (type) {
      case 'bill_payment':
        return (Icons.receipt_long_rounded, AppColors.primaryLight, l10n.billPayment as String, false);
      case 'advance_used':
        return (
          Icons.account_balance_wallet_rounded,
          const Color(0xFF6B46C1),
          l10n.advanceUsed as String,
          false,
        );
      case 'outstanding_collection':
        return (
          Icons.check_circle_rounded,
          c.success as Color,
          l10n.outstandingCollected as String,
          false,
        );
      case 'advance_deposit':
        return (Icons.add_card_rounded, c.success as Color, l10n.advanceDeposit as String, false);
      case 'refund':
        return (Icons.replay_rounded, c.success as Color, 'Refund (voided/returned bill)', false);
      case 'manual_credit':
        return (Icons.arrow_upward_rounded, danger, l10n.creditGiven as String, true);
      case 'invoice_due':
        return (Icons.receipt_rounded, const Color(0xFFFF8C00), l10n.billDue as String, true);
      case 'invoice_due_reversal':
        return (Icons.undo_rounded, c.success as Color, l10n.billVoided as String, false);
      default:
        return (Icons.payments_rounded, c.textSecondary as Color, type, false);
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
