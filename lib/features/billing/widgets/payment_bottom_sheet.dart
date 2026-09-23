import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/shop.dart';
import '../../../shared/widgets/shop_logo_image.dart';
import '../../../shared/widgets/customer_avatar.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../providers/billing_providers.dart';
import '../repositories/invoice_repository.dart';
import '../../../l10n/l10n_extensions.dart';

// ── Public entry-point ─────────────────────────────────────────────────────────

void showPaymentSheet({
  required BuildContext context,
  required int shopId,
  required List<CartItem> cartItems,
  required double subtotal,
  required double gstAmount,
  required double discountAmount,
  required double grandTotal,
  required String discountType,
  required double discountValue,
  required String initialPaymentMode,
  Customer? initialCustomer,
  required VoidCallback onSuccess,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => PaymentBottomSheet(
      shopId: shopId,
      cartItems: cartItems,
      subtotal: subtotal,
      gstAmount: gstAmount,
      discountAmount: discountAmount,
      grandTotal: grandTotal,
      discountType: discountType,
      discountValue: discountValue,
      initialPaymentMode: initialPaymentMode,
      initialCustomer: initialCustomer,
      onSuccess: onSuccess,
    ),
  );
}

// ── Widget ─────────────────────────────────────────────────────────────────────

class PaymentBottomSheet extends StatefulWidget {
  final int shopId;
  final List<CartItem> cartItems;
  final double subtotal;
  final double gstAmount;
  final double discountAmount;
  final double grandTotal;
  final String discountType;
  final double discountValue;
  final String initialPaymentMode;
  final Customer? initialCustomer;
  final VoidCallback onSuccess;

  const PaymentBottomSheet({
    super.key,
    required this.shopId,
    required this.cartItems,
    required this.subtotal,
    required this.gstAmount,
    required this.discountAmount,
    required this.grandTotal,
    required this.discountType,
    required this.discountValue,
    required this.initialPaymentMode,
    this.initialCustomer,
    required this.onSuccess,
  });

  @override
  State<PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<PaymentBottomSheet>
    with SingleTickerProviderStateMixin {
  // Payment method: 'cash' | 'upi' | 'card' | 'mixed'
  late String _method;

  // Registered-customer received amount (editable)
  late final TextEditingController _receivedCtrl;

  // Mixed payment split fields
  final _cashCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();

  // Walk-in partial-payment warning
  bool _walkInPartialWarning = false;

  // Whether to apply available advance balance to reduce this bill
  bool _applyAdvance = true;

  // State
  bool _isProcessing = false;
  bool _success = false;
  Customer? _customer;
  Shop? _shop;

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get _isWalkIn => _customer == null;

  // Advance balance available on the customer account
  double get _availableAdvance => _customer?.advanceBalance ?? 0;

  // Amount of advance to deduct from this bill (0 if walk-in or toggle off)
  double get _advanceApplied =>
      (!_isWalkIn && _applyAdvance && _availableAdvance > 0)
          ? min(_availableAdvance, widget.grandTotal)
          : 0;

  // Net cash/UPI/card the customer still owes after advance
  double get _netBillDue => max(0, widget.grandTotal - _advanceApplied);

  // Unpaid amount carried over from the customer's earlier bills.
  double get _previousDue => _customer?.totalOutstanding ?? 0;

  // Everything the customer would need to pay to leave with nothing owed:
  // this bill (after any advance applied) plus the previous due.
  double get _totalPayable => _netBillDue + _previousDue;

  // Physical amount the customer is actually handing over now — pre-filled
  // with _totalPayable but freely editable: less leaves a remaining due,
  // exactly that clears it, more is kept as advance.
  double get _receivedFromCustomer {
    if (_isWalkIn) return widget.grandTotal;
    return max(0, double.tryParse(_receivedCtrl.text.replaceAll(',', '')) ?? _totalPayable);
  }

  // How much of this invoice remains unpaid
  double get _pendingAmount =>
      max(0.0, widget.grandTotal - _advanceApplied - _receivedFromCustomer);

  // Physical cash beyond what's needed for this bill
  double get _excessPayment =>
      max(0.0, _receivedFromCustomer - _netBillDue);

  // Portion of excess that reduces existing outstanding
  double get _outstandingReduced =>
      min(_excessPayment, _customer?.totalOutstanding ?? 0);

  // Portion of excess beyond clearing outstanding → new advance credit
  double get _newAdvanceFromOverpayment =>
      _excessPayment - _outstandingReduced;

  String get _status {
    if (_pendingAmount == 0) return AppConstants.statusPaid;
    if (_advanceApplied + _receivedFromCustomer > 0) return AppConstants.statusPartialPaid;
    return AppConstants.statusPending;
  }

  // New outstanding = old − reduced + new pending from this bill
  double get _newOutstanding {
    if (_customer == null) return 0;
    return max(0.0,
        (_customer!.totalOutstanding - _outstandingReduced) + _pendingAmount);
  }

  // New advance = old − applied + any overpayment credit
  double get _newAdvanceBalance {
    if (_customer == null) return 0;
    return max(0.0,
        _customer!.advanceBalance - _advanceApplied + _newAdvanceFromOverpayment);
  }

  // Mixed: running total of individual fields
  double get _mixedCash => max(0, double.tryParse(_cashCtrl.text) ?? 0);
  double get _mixedUpi => max(0, double.tryParse(_upiCtrl.text) ?? 0);
  double get _mixedCard => max(0, double.tryParse(_cardCtrl.text) ?? 0);
  double get _mixedTotal => _mixedCash + _mixedUpi + _mixedCard;
  // For mixed mode the target is what the customer needs to physically pay
  double get _mixedTarget => _isWalkIn ? widget.grandTotal : _receivedFromCustomer;
  bool get _mixedIsValid => (_mixedTotal - _mixedTarget).abs() < 0.01;

  // UPI deep-link for QR in PDF
  String? get _upiDeepLink {
    final id = _shop?.upiId;
    if (id == null || id.isEmpty) return null;
    return 'upi://pay?pa=$id&pn=${Uri.encodeComponent(_shop!.name)}&am=${widget.grandTotal.toStringAsFixed(2)}&cu=INR';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer;
    _method = widget.initialPaymentMode;
    // Default to net amount due after any available advance
    final initialAdvance = widget.initialCustomer != null && _applyAdvance
        ? min(widget.initialCustomer!.advanceBalance, widget.grandTotal)
        : 0.0;
    _receivedCtrl = TextEditingController(
        text: (max(0, widget.grandTotal - initialAdvance) +
                (widget.initialCustomer?.totalOutstanding ?? 0))
            .toStringAsFixed(2));
    _receivedCtrl.addListener(() => setState(() {
          _walkInPartialWarning = false;
        }));
    _loadShop();
  }

  // Recalculate suggested received amount when advance toggle or customer changes
  void _resetReceivedDefault() {
    _receivedCtrl.text = _totalPayable.toStringAsFixed(2);
  }

  Future<void> _loadShop() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (mounted) setState(() => _shop = shop);
  }

  @override
  void dispose() {
    _receivedCtrl.dispose();
    _cashCtrl.dispose();
    _upiCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validate() {
    final l10n = context.l10n;
    if (widget.grandTotal <= 0) {
      _snack(l10n.invalidBillAmount);
      return false;
    }
    if (!_isWalkIn && _receivedFromCustomer < 0) {
      _snack(l10n.receivedAmountNegative);
      return false;
    }
    if (_method == 'mixed') {
      if (_mixedTotal <= 0) {
        _snack(l10n.enterPaymentSplitAmounts);
        return false;
      }
      if (!_mixedIsValid) {
        final diff = (_mixedTarget - _mixedTotal).abs();
        _snack(l10n.splitTotalMismatch(AppFormatters.formatCurrency(diff)));
        return false;
      }
    }
    return true;
  }

  // ── Customer picker ────────────────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getInt(AppConstants.keyShopId) ?? widget.shopId;
    final customers = await getIt<CustomerRepository>().getAllCustomers(shopId);
    if (!mounted) return;

    final selected = await showModalBottomSheet<Customer>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CustomerPickerSheet(customers: customers),
    );

    if (selected != null) {
      setState(() {
        _customer = selected;
        _walkInPartialWarning = false;
        _applyAdvance = true;
      });
      _resetReceivedDefault();
    }
  }

  // ── Generate Bill ──────────────────────────────────────────────────────────

  Future<void> _generateBill() async {
    // Without this, a fast double-tap could call this twice before the
    // button's own rebuild (disabledBackgroundColor/onPressed: null) takes
    // effect — the invoice_number UNIQUE constraint stops a duplicate row,
    // but the user just sees a confusing failure for what was actually a
    // successful first submission.
    if (_isProcessing) return;
    if (!_validate()) return;

    // Walk-in partial payment guard
    if (_isWalkIn && _pendingAmount > 0) {
      setState(() => _walkInPartialWarning = true);
      return;
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final isVoiceOrigin = container.read(cartVoiceOriginProvider);
    final isOnBasic = container.read(subscriptionProvider)?.isOnBasicPlan ?? false;

    setState(() => _isProcessing = true);

    String invoiceNum;
    try {
      final invoiceRepo = getIt<InvoiceRepository>();

      // Local, offline-first gate — see basicPlanVoiceInvoiceLimit's doc
      // comment for why the backend independently enforces the same limit
      // from its own synced data rather than trusting this check alone.
      if (isVoiceOrigin && isOnBasic) {
        final used = await invoiceRepo.countVoiceInvoices(widget.shopId);
        if (used >= AppConstants.basicPlanVoiceInvoiceLimit) {
          if (mounted) {
            setState(() => _isProcessing = false);
            _showVoiceLimitReachedDialog();
          }
          return;
        }
      }

      invoiceNum = await invoiceRepo.getNextInvoiceNumber(widget.shopId);

      // receivedAmount on the invoice = advance applied + cash/UPI/card towards this bill
      final billCoveredByCustomer =
          min(_receivedFromCustomer, _netBillDue);
      final invoiceReceived = _advanceApplied + billCoveredByCustomer;

      final invoice = Invoice(
        invoiceNumber: invoiceNum,
        shopId: widget.shopId,
        customerId: _customer?.id,
        customerName: _customer?.name ?? AppConstants.defaultCustomerName,
        subtotal: widget.subtotal,
        discountType: widget.discountType,
        discountValue: widget.discountValue,
        discountAmount: widget.discountAmount,
        gstAmount: widget.gstAmount,
        grandTotal: widget.grandTotal,
        receivedAmount: _isWalkIn ? widget.grandTotal : invoiceReceived,
        pendingAmount: _pendingAmount,
        paymentMode: _method,
        status: _status,
        isVoiceCreated: isVoiceOrigin,
        createdAt: DateTime.now(),
      );

      // Ledger rows to record alongside the invoice — built here (amounts
      // only) since the invoiceId they need doesn't exist until
      // createInvoice() inserts the invoice inside its own transaction.
      final paymentTxns = <PendingPaymentTxn>[
        if (_advanceApplied > 0)
          PendingPaymentTxn(type: 'advance_used', amount: _advanceApplied, paymentMode: 'advance'),
        if (billCoveredByCustomer > 0)
          PendingPaymentTxn(type: 'bill_payment', amount: billCoveredByCustomer, paymentMode: _method),
        if (_outstandingReduced > 0)
          PendingPaymentTxn(type: 'outstanding_collection', amount: _outstandingReduced, paymentMode: _method),
        if (_newAdvanceFromOverpayment > 0)
          PendingPaymentTxn(type: 'advance_deposit', amount: _newAdvanceFromOverpayment, paymentMode: _method),
      ];

      // Invoice + items + stock deduction + customer balance + payment
      // ledger, all in one database transaction — either the whole sale
      // commits or none of it does.
      await invoiceRepo.createInvoice(
        invoice: invoice,
        cartItems: widget.cartItems,
        customerId: _customer?.id,
        newOutstanding: _customer != null ? _newOutstanding : null,
        newAdvanceBalance: _customer != null ? _newAdvanceBalance : null,
        paymentTransactions: _customer != null ? paymentTxns : const [],
      );
    } on InsufficientStockException catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _snack('${e.itemName}: only ${e.available} in stock, ${e.requested} requested');
      }
      return;
    } catch (e) {
      // Nothing committed — the whole attempt is one transaction, so it's
      // safe to say the sale did not go through.
      if (mounted) {
        setState(() => _isProcessing = false);
        _snack(context.l10n.failedToGenerateBill('$e'));
      }
      return;
    }

    // The sale is already committed at this point — a failure from here on
    // (PDF generation, printing) must not be reported as "bill failed", or a
    // shopkeeper retrying in response would create a second, duplicate sale
    // for the same cart.
    if (mounted) setState(() { _isProcessing = false; _success = true; });
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      Navigator.pop(context);
      widget.onSuccess();
    }

    try {
      final pdfBytes = await _buildPdf(invoiceNum: invoiceNum);
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      debugPrint('[Checkout] Sale $invoiceNum saved, but PDF/print failed: $e');
      // The sale sheet is already dismissed by this point — nothing left to
      // update in this widget. The bill is safely saved and can be reprinted
      // from Bills > invoice detail at any time.
    }
  }

  void _showVoiceLimitReachedDialog() {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Voice invoice limit reached', style: TextStyle(color: c.textPrimary)),
        content: Text(
          "You've used all ${AppConstants.basicPlanVoiceInvoiceLimit} voice-created invoices on "
          'the Basic plan. Upgrade to Pro for unlimited voice billing — or finish this sale '
          'manually instead (manual billing has no limit).',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Not now', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(context); // close the payment sheet too
              context.push('/profile/subscription');
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  // ── PDF Builder ────────────────────────────────────────────────────────────
  // Uses the same unified A4 template as InvoicePreviewScreen so both paths
  // produce identical invoices.

  Future<Uint8List> _buildPdf({required String invoiceNum}) async {
    final l10n = context.l10n;
    final doc = pw.Document();

    // ── Fonts ─────────────────────────────────────────────────────────────────
    pw.Font regular = pw.Font.helvetica();
    pw.Font bold = pw.Font.helveticaBold();
    try {
      regular = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}

    // ── Shop logo ─────────────────────────────────────────────────────────────
    pw.MemoryImage? shopLogoImage;
    final logoBytes =
        await fetchShopLogoBytes(logoPath: _shop?.logoPath, logoUrl: _shop?.logoUrl);
    if (logoBytes != null) {
      shopLogoImage = pw.MemoryImage(logoBytes);
    }

    // ── UPI QR ────────────────────────────────────────────────────────────────
    pw.MemoryImage? qrImg;
    if (_method == 'upi' || (_method == 'mixed' && _mixedUpi > 0)) {
      final link = _upiDeepLink;
      if (link != null) {
        final painter = QrPainter(
          data: link,
          version: QrVersions.auto,
          eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF000000)),
        );
        final imgData =
            await painter.toImageData(300, format: ui.ImageByteFormat.png);
        if (imgData != null) {
          qrImg = pw.MemoryImage(imgData.buffer.asUint8List());
        }
      }
    }

    // ── Date + 12-hour time ───────────────────────────────────────────────────
    final now = DateTime.now();
    final hour12 =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final timeStr =
        '${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
        ' ${now.hour >= 12 ? 'PM' : 'AM'}';

    // ── Styling constants ─────────────────────────────────────────────────────
    const kLabelSize = 10.0;
    const kSummarySize = 11.0;
    const kBorderColor = PdfColors.grey400;
    const kHeaderBg = PdfColors.grey100;

    // ── Local helpers (identical to InvoicePreviewScreen) ─────────────────────

    pw.Widget cell(
      String text, {
      bool isBold = false,
      pw.TextAlign align = pw.TextAlign.left,
      bool isHeader = false,
    }) {
      return pw.Container(
        color: isHeader ? kHeaderBg : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: kLabelSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget infoRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 80,
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: kLabelSize, color: PdfColors.grey700)),
            ),
            pw.Text(':',
                style: const pw.TextStyle(
                    fontSize: kLabelSize, color: PdfColors.grey700)),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Text(value,
                  style: const pw.TextStyle(fontSize: kLabelSize)),
            ),
          ],
        ),
      );
    }

    pw.Widget summaryRow(
      String label,
      String value, {
      bool isBold = false,
      double fontSize = kSummarySize,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight:
                        isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight:
                        isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );
    }

    // ── Build document ────────────────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        build: (pw.Context ctx) => [
          // ── Shop header ─────────────────────────────────────────────────────
          if (shopLogoImage != null) ...[
            pw.Center(
              child: pw.ClipOval(
                child: pw.Image(shopLogoImage,
                    width: 70, height: 70, fit: pw.BoxFit.cover),
              ),
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Center(
            child: pw.Text(
              _shop?.name ?? l10n.shopFallback,
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (_shop?.ownerName != null && _shop!.ownerName.isNotEmpty)
            pw.Center(
              child: pw.Text(_shop!.ownerName,
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey800)),
            ),
          if (_shop?.address != null) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Address: ${_shop!.address!}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
          if (_shop?.phone != null && _shop!.phone.isNotEmpty)
            pw.Center(
              child: pw.Text('Phone: ${_shop!.phone}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
          if (_shop?.gstNumber != null)
            pw.Center(
              child: pw.Text('GSTIN: ${_shop!.gstNumber!}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1.5, color: PdfColors.grey700),

          // ── Invoice meta (two-column) ────────────────────────────────────────
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    infoRow('Invoice No', invoiceNum),
                    infoRow('Date', AppFormatters.formatDate(now)),
                    infoRow('Time', timeStr),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    infoRow('Customer',
                        _customer?.name ?? AppConstants.defaultCustomerName),
                    if (_customer?.phone != null)
                      infoRow('Phone', _customer!.phone!),
                    infoRow('Payment', localizedPaymentMode(l10n, _method)),
                    infoRow(
                        'Status',
                        _pendingAmount <= 0
                            ? 'PAID'
                            : (_advanceApplied + _receivedFromCustomer > 0
                                ? 'PARTIAL PAID'
                                : 'PENDING')),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),

          // ── Items table ──────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Table(
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            border: pw.TableBorder.all(color: kBorderColor, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FixedColumnWidth(36),
              2: pw.FixedColumnWidth(70),
              3: pw.FixedColumnWidth(70),
            },
            children: [
              pw.TableRow(children: [
                cell(l10n.itemHeader, isBold: true, isHeader: true),
                cell(l10n.qtyHeader,
                    isBold: true,
                    align: pw.TextAlign.center,
                    isHeader: true),
                cell(l10n.rateHeader,
                    isBold: true,
                    align: pw.TextAlign.right,
                    isHeader: true),
                cell(l10n.totalHeader,
                    isBold: true,
                    align: pw.TextAlign.right,
                    isHeader: true),
              ]),
              ...widget.cartItems.map(
                (item) => pw.TableRow(children: [
                  cell(item.item.name),
                  cell('${item.quantity}', align: pw.TextAlign.center),
                  cell(
                    'Rs.${item.item.sellingPrice.toStringAsFixed(2)}',
                    align: pw.TextAlign.right,
                  ),
                  cell(
                    'Rs.${item.lineTotal.toStringAsFixed(2)}',
                    align: pw.TextAlign.right,
                  ),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),

          // ── Summary ──────────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          summaryRow(l10n.subtotal,
              'Rs.${widget.subtotal.toStringAsFixed(2)}'),
          if (widget.discountAmount > 0)
            summaryRow(l10n.discount,
                '-Rs.${widget.discountAmount.toStringAsFixed(2)}'),
          if (widget.gstAmount > 0)
            summaryRow(
                l10n.gst, 'Rs.${widget.gstAmount.toStringAsFixed(2)}'),
          pw.Divider(thickness: 1, color: PdfColors.grey500),
          summaryRow(
            l10n.grandTotal,
            'Rs.${widget.grandTotal.toStringAsFixed(2)}',
            isBold: true,
            fontSize: 13,
          ),

          // Received / Pending (partial payment)
          if (_pendingAmount > 0) ...[
            pw.SizedBox(height: 4),
            summaryRow(
                l10n.received,
                'Rs.${(widget.grandTotal - _pendingAmount).toStringAsFixed(2)}'),
            summaryRow(
                l10n.pending, 'Rs.${_pendingAmount.toStringAsFixed(2)}'),
          ],

          // Mixed payment split
          if (_method == 'mixed') ...[
            pw.SizedBox(height: 4),
            pw.Text(l10n.paymentSplitLabel,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10)),
            if (_mixedCash > 0)
              summaryRow(
                  '  ${l10n.cash}', 'Rs.${_mixedCash.toStringAsFixed(2)}'),
            if (_mixedUpi > 0)
              summaryRow(
                  '  ${l10n.upi}', 'Rs.${_mixedUpi.toStringAsFixed(2)}'),
            if (_mixedCard > 0)
              summaryRow(
                  '  ${l10n.card}', 'Rs.${_mixedCard.toStringAsFixed(2)}'),
          ],

          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1.5, color: PdfColors.grey700),

          // ── UPI QR code ──────────────────────────────────────────────────────
          if (qrImg != null) ...[
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                l10n.scanToPayUpi,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Image(qrImg, width: 110, height: 110)),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                _shop?.upiId ?? '',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Amount: Rs.${widget.grandTotal.toStringAsFixed(2)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          ],

          // ── Footer ───────────────────────────────────────────────────────────
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              l10n.thankYouShopping,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text('Visit us again!',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(l10n.generatedByVaani,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey500)),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.colors.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final pad = MediaQuery.of(context).padding.bottom;
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1B3A) : AppColors.scaffoldLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, pad > 0 ? pad + 8 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: c.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            _buildHeader(),
            const SizedBox(height: 16),

            // Amount section
            _buildAmountSection(),
            const SizedBox(height: 16),

            // Payment method
            _buildMethodChips(),

            // Mixed split fields
            if (_method == 'mixed') ...[
              const SizedBox(height: 14),
              _buildMixedFields(),
            ],

            // Walk-in partial warning
            if (_walkInPartialWarning) ...[
              const SizedBox(height: 12),
              _buildPartialWarning(),
            ],

            const SizedBox(height: 20),
            _buildGenerateButton(),
          ],
        ),
      ),
    );
  }

  // ── Section builders ───────────────────────────────────────────────────────

  Widget _buildHeader() {
    final c = context.colors;
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.payment,
                  style: TextStyle(color: c.textHint, fontSize: 12, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(
                _isWalkIn ? l10n.walkInCustomer : _customer!.name,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins'),
              ),
              if (!_isWalkIn && _customer!.phone != null)
                Text(
                  '+91 ${_customer!.phone}',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
            ],
          ),
        ),
        // Change customer button
        GestureDetector(
          onTap: _pickCustomer,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isWalkIn ? Icons.person_add_rounded : Icons.swap_horiz_rounded,
                  color: AppColors.primaryLight,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _isWalkIn ? l10n.addCustomer : l10n.change,
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Only shown when the customer has advance credit on file: lets the
  // shopkeeper choose whether to spend it on this bill. (Extra money paid
  // now is NOT a separate field — see the Receive Amount result row.)
  Widget _buildAdvanceToggle() {
    final l10n = context.l10n;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _applyAdvance = !_applyAdvance);
          _resetReceivedDefault();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _applyAdvance
                ? c.success.withValues(alpha: 0.12)
                : c.divider.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _applyAdvance
                    ? c.success.withValues(alpha: 0.35)
                    : c.surfaceBorder),
          ),
          child: Row(
            children: [
              Icon(
                _applyAdvance
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: _applyAdvance ? c.success : c.textHint,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.applyAdvance(AppFormatters.formatCurrency(_advanceApplied > 0
                      ? _advanceApplied
                      : _customer!.advanceBalance)),
                  style: TextStyle(
                      color: _applyAdvance ? c.success : c.textHint,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    final c = context.colors;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isWalkIn) {
      // Walk-in: just show the big total
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Text(l10n.totalAmount,
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  AppFormatters.formatCurrency(widget.grandTotal),
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Registered customer: Current Bill + Previous Due, then one editable
    // Receive Amount and one result line under it.
    final received = _receivedFromCustomer;
    final diff = received - _totalPayable;
    final String resultLabel;
    final double resultValue;
    final Color resultColor;
    if (diff > 0.005) {
      resultLabel = l10n.advanceBalance;
      resultValue = diff;
      resultColor = c.success;
    } else if (diff < -0.005) {
      resultLabel = l10n.remainingDue;
      resultValue = -diff;
      resultColor = const Color(0xFFFF6B00);
    } else {
      resultLabel = l10n.remainingDue;
      resultValue = 0;
      resultColor = c.success;
    }

    return Column(
      children: [
        _AmountRow(
          label: l10n.currentBill,
          value: AppFormatters.formatCurrency(widget.grandTotal),
          valueColor: c.textPrimary,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(l10n.previousDue,
                style: TextStyle(color: c.textSecondary, fontSize: 14)),
            const SizedBox(width: 4),
            Tooltip(
              message: l10n.previousDueInfo,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 3),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.info_outline_rounded, size: 16, color: c.textHint),
              ),
            ),
            const Spacer(),
            Text(
              AppFormatters.formatCurrency(_previousDue),
              style: TextStyle(
                  color: _previousDue > 0 ? const Color(0xFFFF6B00) : c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),

        // Existing advance credit (only when the customer has some).
        if (_customer!.advanceBalance > 0) ...[
          _buildAdvanceToggle(),
          if (_advanceApplied > 0) ...[
            const SizedBox(height: 8),
            _AmountRow(
              label: l10n.advanceApplied,
              value: '− ${AppFormatters.formatCurrency(_advanceApplied)}',
              valueColor: c.success,
            ),
          ],
        ],

        const SizedBox(height: 14),

        // Receive Amount (editable, pre-filled with Current Bill + Previous Due)
        Row(
          children: [
            Text(l10n.receiveAmount,
                style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: _receivedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: TextStyle(
                    color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(color: c.textSecondary, fontSize: 14),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // One result line: Remaining Due / Advance Balance.
        _AmountRow(
          label: resultLabel,
          value: AppFormatters.formatCurrency(resultValue),
          valueColor: resultColor,
        ),
      ],
    );
  }

  Widget _buildMethodChips() {
    final c = context.colors;
    final l10n = context.l10n;
    final methods = [
      ('cash', l10n.cash, Icons.payments_rounded),
      ('upi', l10n.upi, Icons.phone_android_rounded),
      ('card', l10n.card, Icons.credit_card_rounded),
      ('mixed', l10n.mixed, Icons.shuffle_rounded),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.paymentMethod,
            style: TextStyle(color: c.textSecondary, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(
          children: methods.map((m) {
            final (id, label, icon) = m;
            final active = _method == id;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _method = id;
                  // Pre-fill mixed cash field with total for convenience
                  if (id == 'mixed' && _cashCtrl.text.isEmpty) {
                    _cashCtrl.text = _mixedTarget.toStringAsFixed(2);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryLight
                        : (isDark ? const Color(0xFF2A2750) : c.divider),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? AppColors.primaryLight
                          : c.surfaceBorder,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 18,
                          color: active ? Colors.white : c.textHint),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : c.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMixedFields() {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          _MixedRow(label: l10n.cash, ctrl: _cashCtrl, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
          _MixedRow(label: l10n.upi, ctrl: _upiCtrl, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
          _MixedRow(label: l10n.card, ctrl: _cardCtrl, onChanged: () => setState(() {})),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: c.divider, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.total,
                  style: TextStyle(color: c.textSecondary, fontSize: 13)),
              Row(
                children: [
                  Text(
                    AppFormatters.formatCurrency(_mixedTotal),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _mixedIsValid ? c.success : c.danger),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _mixedIsValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: _mixedIsValid ? c.success : c.danger,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
          if (!_mixedIsValid && _mixedTotal > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.needMoreOrLess(
                  AppFormatters.formatCurrency((_mixedTarget - _mixedTotal).abs()),
                  _mixedTotal < _mixedTarget ? l10n.more : l10n.less),
              style: TextStyle(color: c.danger, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartialWarning() {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: c.danger, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.partialPaymentRequiresCustomer,
                  style: TextStyle(color: c.danger, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickCustomer,
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: Text(l10n.selectCustomer),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryLight,
                side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    final c = context.colors;
    final l10n = context.l10n;
    final canProceed = !_isProcessing &&
        (_method != 'mixed' || _mixedIsValid || _mixedTotal == 0);

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: canProceed ? _generateBill : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _success ? c.success : AppColors.primaryLight,
          disabledBackgroundColor: c.divider,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: _success ? 0 : 2,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isProcessing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : _success
                  ? Row(
                      key: const ValueKey('success'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(l10n.billGenerated,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    )
                  : Row(
                      key: const ValueKey('generate'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          l10n.generateBill(AppFormatters.formatCurrency(_receivedFromCustomer)),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

// ── Utility widgets ────────────────────────────────────────────────────────────

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _AmountRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

class _MixedRow extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  const _MixedRow({required this.label, required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(color: c.textHint, fontSize: 13),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1B3A) : Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: isDark ? BorderSide.none : BorderSide(color: c.inputBorder)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      );
  }
}

// ── Customer picker sheet ──────────────────────────────────────────────────────

class _CustomerPickerSheet extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPickerSheet({required this.customers});

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Customer> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.customers;
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.customers
            : widget.customers.where((c) =>
                c.name.toLowerCase().contains(q) ||
                (c.phone?.contains(q) ?? false)).toList();
      });
    });
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
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: c.surfaceBorder, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.searchCustomerHint,
                hintStyle: TextStyle(color: c.textHint),
                prefixIcon: Icon(Icons.search_rounded, color: c.textHint),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(l10n.noCustomersFoundInSearch,
                        style: TextStyle(color: c.textHint)))
                : ListView.builder(
                    controller: ctrl,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final cust = _filtered[i];
                      return ListTile(
                        leading: CustomerAvatar(customer: cust, size: 40, color: AppColors.primaryLight),
                        title: Text(cust.name, style: TextStyle(color: c.textPrimary)),
                        subtitle: cust.phone != null
                            ? Text('+91 ${cust.phone}',
                                style: TextStyle(color: c.textSecondary, fontSize: 12))
                            : null,
                        trailing: cust.totalOutstanding > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B00).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  l10n.dueAmount(AppFormatters.formatCurrency(cust.totalOutstanding)),
                                  style: const TextStyle(color: Color(0xFFFF8C00), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              )
                            : null,
                        onTap: () => Navigator.pop(context, cust),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
