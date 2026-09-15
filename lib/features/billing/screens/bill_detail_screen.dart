import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/shop.dart';
import '../repositories/invoice_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../auth/repositories/shop_repository.dart';
import '../services/invoice_pdf_helper.dart';
import '../../../l10n/l10n_extensions.dart';

class BillDetailScreen extends StatefulWidget {
  final int invoiceId;
  const BillDetailScreen({super.key, required this.invoiceId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  Invoice? _invoice;
  Customer? _customer;
  Shop? _shop;
  int _shopId = 1;
  bool _loading = true;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;

    final results = await Future.wait([
      getIt<InvoiceRepository>().getInvoiceById(widget.invoiceId),
      getIt<ShopRepository>().getShop(),
    ]);
    final inv = results[0] as Invoice?;
    final shop = results[1] as Shop?;

    Customer? customer;
    if (inv?.customerId != null) {
      customer = await getIt<CustomerRepository>().getCustomerById(inv!.customerId!);
    }

    if (!mounted) return;
    setState(() {
      _invoice = inv;
      _customer = customer;
      _shop = shop;
      _loading = false;
    });
  }

  Future<Uint8List> _buildPdfBytes(PdfPageFormat _) => InvoicePdfHelper.buildPdfBytes(
        l10n: context.l10n,
        shop: _shop,
        invoiceNumber: _invoice!.invoiceNumber,
        invoiceDate: _invoice!.createdAt,
        customer: _customer,
        paymentMode: _invoice!.paymentMode,
        status: _invoice!.status,
        items: _invoice!.items
            .map((it) => (
                  name: it.productName,
                  qty: it.quantity,
                  price: it.sellingPrice,
                  total: it.lineTotal,
                ))
            .toList(),
        subtotal: _invoice!.subtotal,
        gstAmount: _invoice!.gstAmount,
        discountAmount: _invoice!.discountAmount,
        grandTotal: _invoice!.grandTotal,
      );

  bool get _hasReturnableItems =>
      _invoice != null && _invoice!.items.any((it) => it.remainingQuantity > 0);

  Future<void> _voidBill() async {
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Void this bill?', style: TextStyle(color: c.textPrimary)),
        content: Text(
          'This reverses the stock, removes it from sales reports, and refunds any '
          "money already collected for it back onto the customer's advance balance. "
          'This cannot be undone.',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Void Bill', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInProgress = true);
    try {
      await getIt<InvoiceRepository>().voidInvoice(widget.invoiceId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Bill voided'),
          backgroundColor: context.colors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to void bill: $e'),
          backgroundColor: context.colors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _openReturnSheet() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final returns = await showModalBottomSheet<Map<int, int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReturnItemsSheet(invoice: invoice),
    );
    if (returns == null || returns.isEmpty) return;

    setState(() => _actionInProgress = true);
    try {
      await getIt<InvoiceRepository>().returnItems(widget.invoiceId, returns);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Return recorded'),
          backgroundColor: context.colors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to record return: $e'),
          backgroundColor: context.colors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final invoice = _invoice;
    final isCancelled = invoice?.status == AppConstants.statusCancelled;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          invoice?.invoiceNumber ?? l10n.billDetail,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
              fontSize: 16),
        ),
        actions: [
          if (invoice != null) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded, color: AppColors.primaryLight),
              tooltip: 'Share',
              onPressed: () => InvoicePdfHelper.shareById(context, invoice.id!, _shopId),
            ),
            IconButton(
              icon: const Icon(Icons.print_rounded, color: AppColors.primaryLight),
              tooltip: l10n.printShare,
              onPressed: () => Printing.layoutPdf(onLayout: _buildPdfBytes),
            ),
            if (!isCancelled)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: c.textPrimary),
                onSelected: (v) {
                  if (v == 'return') _openReturnSheet();
                  if (v == 'void') _voidBill();
                },
                itemBuilder: (_) => [
                  if (_hasReturnableItems)
                    const PopupMenuItem(
                      value: 'return',
                      child: Text('Return Items'),
                    ),
                  const PopupMenuItem(
                    value: 'void',
                    child: Text('Void Bill'),
                  ),
                ],
              ),
          ],
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryLight))
          : invoice == null
              ? Center(
                  child: Text(l10n.billNotFound,
                      style: TextStyle(color: c.textSecondary)))
              : Stack(
                  children: [
                    Column(
                      children: [
                        if (isCancelled)
                          Container(
                            width: double.infinity,
                            color: c.danger.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'THIS BILL HAS BEEN VOIDED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: c.danger, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          )
                        else if (invoice.items.any((it) => it.returnedQuantity > 0))
                          Container(
                            width: double.infinity,
                            color: const Color(0xFFFF8C00).withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'PART OF THIS BILL HAS BEEN RETURNED',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF8C00), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        Expanded(
                          child: PdfPreview(
                            build: _buildPdfBytes,
                            allowSharing: false,
                            allowPrinting: false,
                            canChangePageFormat: false,
                            canChangeOrientation: false,
                            canDebug: false,
                            maxPageWidth: 700,
                            actions: const [],
                          ),
                        ),
                      ],
                    ),
                    if (_actionInProgress)
                      Container(
                        color: Colors.black.withValues(alpha: 0.3),
                        child: const Center(
                          child: CircularProgressIndicator(color: AppColors.primaryLight),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ── Return items sheet ────────────────────────────────────────────────────────

class _ReturnItemsSheet extends StatefulWidget {
  final Invoice invoice;
  const _ReturnItemsSheet({required this.invoice});

  @override
  State<_ReturnItemsSheet> createState() => _ReturnItemsSheetState();
}

class _ReturnItemsSheetState extends State<_ReturnItemsSheet> {
  final Map<int, int> _returnQty = {};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final returnableItems =
        widget.invoice.items.where((it) => it.remainingQuantity > 0).toList();

    final totalToReturn = returnableItems.fold<int>(
        0, (s, it) => s + (_returnQty[it.id] ?? 0));

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1B3A) : AppColors.scaffoldLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: c.surfaceBorder, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Return Items',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary)),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: SingleChildScrollView(
                child: Column(
                  children: returnableItems.map((it) {
                    final qty = _returnQty[it.id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.productName,
                                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                                Text('${it.remainingQuantity} available to return',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline_rounded, color: c.textHint),
                            onPressed: qty > 0
                                ? () => setState(() => _returnQty[it.id!] = qty - 1)
                                : null,
                          ),
                          SizedBox(
                            width: 28,
                            child: Text('$qty',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle_outline_rounded,
                                color: qty < it.remainingQuantity ? AppColors.primaryLight : c.textHint),
                            onPressed: qty < it.remainingQuantity
                                ? () => setState(() => _returnQty[it.id!] = qty + 1)
                                : null,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: totalToReturn > 0
                    ? () => Navigator.pop(
                        context,
                        Map<int, int>.fromEntries(
                            _returnQty.entries.where((e) => e.value > 0)))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  disabledBackgroundColor: c.divider,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  totalToReturn > 0 ? 'Confirm Return ($totalToReturn item${totalToReturn > 1 ? 's' : ''})' : 'Select items to return',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
