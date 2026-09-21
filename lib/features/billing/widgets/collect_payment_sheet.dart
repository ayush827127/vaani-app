import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../repositories/invoice_repository.dart';
import '../../../l10n/l10n_extensions.dart';

// ── Public entry-point ─────────────────────────────────────────────────────────

void showCollectPaymentSheet({
  required BuildContext context,
  required Customer customer,
  required int shopId,
  VoidCallback? onSuccess,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => CollectPaymentSheet(
      customer: customer,
      shopId: shopId,
      onSuccess: onSuccess,
    ),
  );
}

// ── Widget ─────────────────────────────────────────────────────────────────────

class CollectPaymentSheet extends StatefulWidget {
  final Customer customer;
  final int shopId;
  final VoidCallback? onSuccess;

  const CollectPaymentSheet({
    super.key,
    required this.customer,
    required this.shopId,
    this.onSuccess,
  });

  @override
  State<CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends State<CollectPaymentSheet> {
  final _advanceAmountCtrl = TextEditingController();
  // Used when the customer has an outstanding balance but no specific
  // invoice to allocate it against — e.g. it came entirely from a "Give
  // Credit" ledger entry (give_credit_sheet.dart), which has no invoice at
  // all. Kept separate from _allocationCtrls (invoice-specific) rather than
  // folded into that map under a fake key, since it represents a genuinely
  // different kind of collection (against the customer's aggregate balance,
  // not a specific bill).
  final _generalCollectionCtrl = TextEditingController();
  String _method = 'cash';
  bool _isAdvanceDeposit = false; // true = add to advance; false = reduce outstanding
  bool _isProcessing = false;
  bool _success = false;
  bool _isLoadingInvoices = true;

  List<Invoice> _outstandingInvoices = [];
  // invoiceId -> whether it's selected to be settled by this payment
  final Set<int> _selectedInvoiceIds = {};
  // invoiceId -> the controller for that invoice's allocated amount
  final Map<int, TextEditingController> _allocationCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadOutstandingInvoices();
  }

  Future<void> _loadOutstandingInvoices() async {
    final invoices = await getIt<InvoiceRepository>()
        .getOutstandingInvoicesByCustomer(widget.customer.id!);
    if (!mounted) return;
    setState(() {
      _outstandingInvoices = invoices;
      _isLoadingInvoices = false;
      // Default: nothing pre-selected — the shopkeeper picks which bill(s)
      // this payment settles.
      for (final inv in invoices) {
        _allocationCtrls[inv.id!] =
            TextEditingController(text: inv.pendingAmount.toStringAsFixed(2));
      }
    });
  }

  @override
  void dispose() {
    _advanceAmountCtrl.dispose();
    _generalCollectionCtrl.dispose();
    for (final c in _allocationCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _generalCollectionAmount {
    final raw = double.tryParse(_generalCollectionCtrl.text.replaceAll(',', '')) ?? 0;
    if (raw < 0) return 0;
    final cap = widget.customer.totalOutstanding;
    return raw > cap ? cap : raw;
  }

  double _allocationFor(Invoice inv) {
    if (!_selectedInvoiceIds.contains(inv.id)) return 0;
    final ctrl = _allocationCtrls[inv.id];
    final raw = double.tryParse((ctrl?.text ?? '').replaceAll(',', '')) ?? 0;
    if (raw < 0) return 0;
    return raw > inv.pendingAmount ? inv.pendingAmount : raw;
  }

  double get _totalAllocated =>
      _outstandingInvoices.fold(0.0, (s, inv) => s + _allocationFor(inv));

  // Only relevant when there are no outstanding invoices to allocate
  // against — see _generalCollectionCtrl's doc comment.
  double get _duesAmount =>
      _outstandingInvoices.isEmpty ? _generalCollectionAmount : _totalAllocated;

  double get _advanceAmount =>
      double.tryParse(_advanceAmountCtrl.text.replaceAll(',', '')) ?? 0;

  double get _amount => _isAdvanceDeposit ? _advanceAmount : _duesAmount;

  void _toggleInvoice(Invoice inv) {
    setState(() {
      if (_selectedInvoiceIds.contains(inv.id)) {
        _selectedInvoiceIds.remove(inv.id);
      } else {
        _selectedInvoiceIds.add(inv.id!);
        _allocationCtrls[inv.id]!.text = inv.pendingAmount.toStringAsFixed(2);
      }
    });
  }

  Future<void> _confirm() async {
    if (_isProcessing) return;
    if (_amount <= 0) {
      _snack(context.l10n.enterValidAmount);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final invoiceRepo = getIt<InvoiceRepository>();

      double newOutstanding = widget.customer.totalOutstanding;
      double newAdvance = widget.customer.advanceBalance;
      List<InvoicePaymentAllocation> allocations = const [];

      double? generalCollection;

      if (_isAdvanceDeposit) {
        newAdvance += _amount;
      } else if (_outstandingInvoices.isEmpty) {
        // No specific invoice to allocate against — this customer's due
        // came from a "Give Credit" ledger entry, not a bill. Collect
        // straight against the aggregate balance instead.
        generalCollection = _generalCollectionAmount;
        newOutstanding = (newOutstanding - generalCollection).clamp(0.0, double.infinity);
      } else {
        // Settle each selected invoice individually so its own
        // received/pending/status stay accurate, then reflect the same
        // total against the customer's aggregate outstanding.
        allocations = _outstandingInvoices
            .map((inv) {
              final allocated = _allocationFor(inv);
              if (allocated <= 0) return null;
              final newReceived = inv.receivedAmount + allocated;
              final newPending = (inv.pendingAmount - allocated).clamp(0.0, double.infinity);
              final newStatus = newPending <= 0.01
                  ? AppConstants.statusPaid
                  : AppConstants.statusPartialPaid;
              return InvoicePaymentAllocation(
                invoiceId: inv.id!,
                allocated: allocated,
                newReceivedAmount: newReceived,
                newPendingAmount: newPending,
                newStatus: newStatus,
              );
            })
            .whereType<InvoicePaymentAllocation>()
            .toList();
        newOutstanding = (newOutstanding - _totalAllocated).clamp(0.0, double.infinity);
      }

      // Invoice payment fields + ledger rows + customer balance, all in one
      // database transaction — see collectPayment()'s doc comment.
      await invoiceRepo.collectPayment(
        shopId: widget.shopId,
        customerId: widget.customer.id!,
        newOutstanding: newOutstanding,
        newAdvanceBalance: newAdvance,
        paymentMode: _method,
        advanceDepositAmount: _isAdvanceDeposit ? _amount : null,
        invoiceAllocations: allocations,
        generalCollectionAmount: generalCollection,
      );

      if (mounted) setState(() { _isProcessing = false; _success = true; });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _snack('Failed: $e');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final pad = MediaQuery.of(context).padding.bottom;
    final c = context.colors;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final methods = [
      ('cash', l10n.cash, Icons.payments_rounded),
      ('upi', l10n.upi, Icons.phone_android_rounded),
      ('card', l10n.card, Icons.credit_card_rounded),
    ];

    final canConfirm = !_isProcessing && _amount > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1B3A) : AppColors.scaffoldLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding:
            EdgeInsets.fromLTRB(20, 12, 20, pad > 0 ? pad + 8 : 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: c.surfaceBorder,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.collectPayment,
                              style: TextStyle(
                                  color: c.textHint,
                                  fontSize: 12,
                                  letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text(widget.customer.name,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins')),
                          if (widget.customer.phone != null)
                            Text('+91 ${widget.customer.phone}',
                                style: TextStyle(
                                    color: c.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Balance info
                if (widget.customer.totalOutstanding > 0 ||
                    widget.customer.advanceBalance > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        if (widget.customer.totalOutstanding > 0)
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Color(0xFFFF8C00), size: 15),
                              const SizedBox(width: 8),
                              Text(l10n.outstanding,
                                  style: const TextStyle(
                                      color: Color(0xFFFF8C00), fontSize: 13)),
                              const Spacer(),
                              Text(
                                AppFormatters.formatCurrency(
                                    widget.customer.totalOutstanding),
                                style: const TextStyle(
                                    color: Color(0xFFFF6B00),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        if (widget.customer.totalOutstanding > 0 &&
                            widget.customer.advanceBalance > 0)
                          const SizedBox(height: 8),
                        if (widget.customer.advanceBalance > 0)
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet_rounded,
                                  color: c.success, size: 15),
                              const SizedBox(width: 8),
                              Text(l10n.advanceBalance,
                                  style: TextStyle(
                                      color: c.success, fontSize: 13)),
                              const Spacer(),
                              Text(
                                AppFormatters.formatCurrency(
                                    widget.customer.advanceBalance),
                                style: TextStyle(
                                    color: c.success,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Purpose toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isAdvanceDeposit = !_isAdvanceDeposit;
                      if (_isAdvanceDeposit) {
                        _advanceAmountCtrl.text = '';
                      } else {
                        _selectedInvoiceIds.clear();
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isAdvanceDeposit
                          ? c.success.withValues(alpha: 0.10)
                          : AppColors.primaryLight.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isAdvanceDeposit
                            ? c.success.withValues(alpha: 0.35)
                            : AppColors.primaryLight.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAdvanceDeposit
                              ? Icons.account_balance_wallet_rounded
                              : Icons.receipt_long_rounded,
                          color: _isAdvanceDeposit
                              ? c.success
                              : AppColors.primaryLight,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isAdvanceDeposit
                                ? l10n.depositAsAdvance
                                : l10n.collectAgainstDues,
                            style: TextStyle(
                              color: _isAdvanceDeposit
                                  ? c.success
                                  : AppColors.primaryLight,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.swap_vert_rounded,
                            color: c.textHint, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isAdvanceDeposit)
                  _buildAdvanceAmountField(c)
                else
                  _buildInvoicePicker(c, l10n),

                const SizedBox(height: 16),

                // Payment method chips
                Text(l10n.paymentMethod,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        letterSpacing: 0.5)),
                const SizedBox(height: 10),
                Row(
                  children: methods.map((m) {
                    final (id, label, icon) = m;
                    final active = _method == id;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _method = id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primaryLight
                                : (isDark
                                    ? const Color(0xFF2A2750)
                                    : c.divider),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: active ? AppColors.primaryLight : c.surfaceBorder),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon,
                                  size: 18,
                                  color:
                                      active ? Colors.white : c.textHint),
                              const SizedBox(height: 4),
                              Text(label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: active
                                          ? Colors.white
                                          : c.textHint)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canConfirm ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _success ? c.success : AppColors.primaryLight,
                      disabledBackgroundColor: c.divider,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : _success
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(l10n.paymentRecorded,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                ],
                              )
                            : Text(
                                l10n.confirmPayment(
                                    AppFormatters.formatCurrency(_amount)),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdvanceAmountField(dynamic c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text(context.l10n.amount,
            style: TextStyle(color: c.textSecondary, fontSize: 14)),
        const Spacer(),
        SizedBox(
          width: 160,
          child: TextFormField(
            controller: _advanceAmountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: TextStyle(
                color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(color: c.textSecondary, fontSize: 15),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: isDark ? BorderSide.none : BorderSide(color: c.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.6)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoicePicker(dynamic c, AppLocalizations l10n) {
    if (_isLoadingInvoices) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }
    if (_outstandingInvoices.isEmpty) {
      // A balance with no invoice behind it — most likely a "Give Credit"
      // ledger entry — still needs somewhere to collect against, just not
      // an invoice picker.
      if (widget.customer.totalOutstanding > 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No specific bill for this balance — collect against the total owed',
                style: TextStyle(color: c.textSecondary, fontSize: 12, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(context.l10n.amount, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    controller: _generalCollectionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    autofocus: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    style: TextStyle(
                        color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(color: c.textSecondary, fontSize: 15),
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: Theme.of(context).brightness == Brightness.dark
                            ? BorderSide.none
                            : BorderSide(color: c.inputBorder),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: Text(
          'No pending bills for this customer. Switch to "Deposit as advance" to record a prepayment instead.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select bill(s) to settle',
            style: TextStyle(color: c.textSecondary, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.surfaceBorder),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _outstandingInvoices.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                _buildInvoiceRow(_outstandingInvoices[i], c),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total to collect',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            Text(
              AppFormatters.formatCurrency(_totalAllocated),
              style: TextStyle(
                  color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceRow(Invoice inv, dynamic c) {
    final selected = _selectedInvoiceIds.contains(inv.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleInvoice(inv),
            child: Icon(
              selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: selected ? AppColors.primaryLight : c.textHint,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleInvoice(inv),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inv.invoiceNumber,
                      style: TextStyle(
                          color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    '${AppFormatters.formatDate(inv.createdAt)} · ${context.l10n.pending} ${AppFormatters.formatCurrency(inv.pendingAmount)}',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: _allocationCtrls[inv.id],
              enabled: selected,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                  color: selected ? c.textPrimary : c.textHint,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1B3A) : Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
