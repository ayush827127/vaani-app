import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../repositories/invoice_repository.dart';
import '../../../l10n/l10n_extensions.dart';

// ── Public entry-point ─────────────────────────────────────────────────────────

/// The other half of the customer ledger, alongside
/// [showCollectPaymentSheet] — a khata-style "You Gave" entry: goods or
/// cash given to a customer on credit, with no invoice/items involved. Kept
/// as a separate, deliberately much simpler sheet rather than a mode toggle
/// inside CollectPaymentSheet, since it shares none of that sheet's
/// invoice-allocation logic — just an amount and an optional reason.
void showGiveCreditSheet({
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
    builder: (_) => GiveCreditSheet(
      customer: customer,
      shopId: shopId,
      onSuccess: onSuccess,
    ),
  );
}

// ── Widget ─────────────────────────────────────────────────────────────────────

class GiveCreditSheet extends StatefulWidget {
  final Customer customer;
  final int shopId;
  final VoidCallback? onSuccess;

  const GiveCreditSheet({
    super.key,
    required this.customer,
    required this.shopId,
    this.onSuccess,
  });

  @override
  State<GiveCreditSheet> createState() => _GiveCreditSheetState();
}

class _GiveCreditSheetState extends State<GiveCreditSheet> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isProcessing = false;
  bool _success = false;

  double get _amount => double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isProcessing) return;
    if (_amount <= 0) {
      _snack(context.l10n.enterValidAmount);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final newOutstanding = widget.customer.totalOutstanding + _amount;
      await getIt<InvoiceRepository>().giveCredit(
        shopId: widget.shopId,
        customerId: widget.customer.id!,
        amount: _amount,
        newOutstanding: newOutstanding,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final pad = MediaQuery.of(context).padding.bottom;
    final c = context.colors;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger = const Color(0xFFE24C4C);

    final canConfirm = !_isProcessing && _amount > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1B3A) : AppColors.scaffoldLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, pad > 0 ? pad + 8 : 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.surfaceBorder, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.giveCredit,
                              style: TextStyle(color: c.textHint, fontSize: 12, letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text(widget.customer.name,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins')),
                          if (widget.customer.phone != null)
                            Text('+91 ${widget.customer.phone}',
                                style: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (widget.customer.totalOutstanding > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: const Color(0xFFFF8C00), size: 15),
                        const SizedBox(width: 8),
                        Text(l10n.outstanding,
                            style: const TextStyle(color: Color(0xFFFF8C00), fontSize: 13)),
                        const Spacer(),
                        Text(
                          AppFormatters.formatCurrency(widget.customer.totalOutstanding),
                          style: const TextStyle(
                              color: Color(0xFFFF6B00), fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Amount field
                Row(
                  children: [
                    Text(l10n.amount, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                    const Spacer(),
                    SizedBox(
                      width: 160,
                      child: TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.right,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
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
                            borderSide: BorderSide(color: danger.withValues(alpha: 0.6)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Reason field
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.reasonOptional,
                      style: TextStyle(color: c.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: l10n.reasonHint,
                    hintStyle: TextStyle(color: c.textHint, fontSize: 12),
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: isDark ? BorderSide.none : BorderSide(color: c.inputBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 20),

                // Preview: what the customer will owe after this entry
                if (_amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.newOutstanding,
                            style: TextStyle(color: c.textSecondary, fontSize: 13)),
                        Text(
                          AppFormatters.formatCurrency(widget.customer.totalOutstanding + _amount),
                          style: TextStyle(color: danger, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canConfirm ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _success ? c.success : danger,
                      disabledBackgroundColor: c.divider,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : _success
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(l10n.creditRecorded,
                                      style: const TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              )
                            : Text(
                                l10n.confirmPayment(AppFormatters.formatCurrency(_amount)),
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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
}
