import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../repositories/invoice_repository.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../../shared/models/shop.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../printer/providers/printer_provider.dart';
import '../services/invoice_pdf_helper.dart';

class InvoicePreviewScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? invoiceData;
  const InvoicePreviewScreen({super.key, this.invoiceData});

  @override
  ConsumerState<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends ConsumerState<InvoicePreviewScreen> {
  bool _isSaving = false;
  bool _isSaved = false;
  Shop? _shop;
  String _invoiceNumber = '';

  List<CartItem> get _cart => (widget.invoiceData?['cart'] as List<CartItem>?) ?? [];
  List<InvoiceItem>? get _invoiceItems => widget.invoiceData?['invoiceItems'] as List<InvoiceItem>?;
  bool get _isViewMode => _invoiceItems != null;
  Customer? get _customer => widget.invoiceData?['customer'] as Customer?;
  DateTime get _invoiceDate => (widget.invoiceData?['invoiceDate'] as DateTime?) ?? DateTime.now();
  double get _subtotal => (widget.invoiceData?['subtotal'] as double?) ?? 0;
  double get _gstAmount => (widget.invoiceData?['gstAmount'] as double?) ?? 0;
  double get _discountAmount => (widget.invoiceData?['discountAmount'] as double?) ?? 0;
  double get _grandTotal => (widget.invoiceData?['grandTotal'] as double?) ?? 0;
  String get _discountType => (widget.invoiceData?['discountType'] as String?) ?? 'none';
  double get _discountValue => (widget.invoiceData?['discountValue'] as double?) ?? 0;
  String get _paymentMode => (widget.invoiceData?['paymentMode'] as String?) ?? 'cash';
  int get _shopId => (widget.invoiceData?['shopId'] as int?) ?? 1;

  List<({String name, int qty, double price, double total})> get _lineItems {
    final saved = _invoiceItems;
    if (saved != null) {
      return saved
          .map((it) => (name: it.itemName, qty: it.quantity, price: it.sellingPrice, total: it.lineTotal))
          .toList();
    }
    return _cart
        .map((c) => (name: c.item.name, qty: c.quantity, price: c.effectivePrice, total: c.lineTotal))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final shop = await getIt<ShopRepository>().getShop();
    final existingNum = widget.invoiceData?['invoiceNumber'] as String?;
    final num = existingNum ?? await getIt<InvoiceRepository>().getNextInvoiceNumber(_shopId);
    setState(() {
      _shop = shop;
      _invoiceNumber = num;
      if (_isViewMode) _isSaved = true;
    });
  }

  Future<void> _saveInvoice() async {
    setState(() => _isSaving = true);
    final invoice = Invoice(
      invoiceNumber: _invoiceNumber,
      shopId: _shopId,
      customerId: _customer?.id,
      customerName: _customer?.name ?? AppConstants.defaultCustomerName,
      subtotal: _subtotal,
      discountType: _discountType,
      discountValue: _discountValue,
      discountAmount: _discountAmount,
      gstAmount: _gstAmount,
      grandTotal: _grandTotal,
      paymentMode: _paymentMode,
      status: AppConstants.statusPaid,
      createdAt: DateTime.now(),
    );
    await getIt<InvoiceRepository>().createInvoice(
      invoice: invoice,
      cartItems: _cart,
      customerId: _customer?.id,
    );
    setState(() {
      _isSaving = false;
      _isSaved = true;
    });
    _tryAutoPrint(invoice);
  }

  void _tryAutoPrint(Invoice invoice) {
    final printerState = ref.read(printerProvider);
    if (!printerState.isConnected) return;
    if (!printerState.settings.autoPrint) return;

    final data = PrintInvoiceData(
      shopName: _shop?.name ?? '',
      shopAddress: _shop?.address,
      shopPhone: _shop?.phone,
      shopGstNumber: _shop?.gstNumber,
      customerName: _customer?.name,
      customerPhone: _customer?.phone,
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.createdAt,
      items: _cart.isNotEmpty
          ? _cart
              .map((c) => PrintLineItem(
                    name: c.item.name,
                    quantity: c.quantity,
                    price: c.effectivePrice,
                    total: c.lineTotal,
                  ))
              .toList()
          : (_invoiceItems ?? [])
              .map((it) => PrintLineItem(
                    name: it.itemName,
                    quantity: it.quantity,
                    price: it.sellingPrice,
                    total: it.lineTotal,
                  ))
              .toList(),
      subtotal: _subtotal,
      gstAmount: _gstAmount,
      discountAmount: _discountAmount,
      grandTotal: _grandTotal,
      paymentMode: _paymentMode,
      upiId: _shop?.upiId,
    );

    ref.read(printerProvider.notifier).printInvoice(data).then((ok) {
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invoice saved. Printer connection lost.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
  }

  Future<Uint8List> _buildPdfBytes(PdfPageFormat _) => InvoicePdfHelper.buildPdfBytes(
        l10n: context.l10n,
        shop: _shop,
        invoiceNumber: _invoiceNumber,
        invoiceDate: _invoiceDate,
        customer: _customer,
        paymentMode: _paymentMode,
        items: _lineItems,
        subtotal: _subtotal,
        gstAmount: _gstAmount,
        discountAmount: _discountAmount,
        grandTotal: _grandTotal,
      );

  Future<void> _downloadPdf() async {
    await Printing.layoutPdf(onLayout: _buildPdfBytes);
  }

  Future<void> _shareInvoice() async {
    final bytes = await _buildPdfBytes(PdfPageFormat.a4);
    final dir = await getTemporaryDirectory();
    final safeName = _invoiceNumber.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-');
    final file = File('${dir.path}/invoice_$safeName.pdf');
    await file.writeAsBytes(bytes);
    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Invoice $_invoiceNumber',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = _shop != null && _invoiceNumber.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.invoicePreview),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ready
                ? PdfPreview(
                    build: _buildPdfBytes,
                    allowSharing: false,
                    allowPrinting: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    maxPageWidth: 700,
                    actions: const [],
                  )
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryLight),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: context.colors.surface,
            child: Column(
              children: [
                if (!_isSaved)
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveInvoice,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(l10n.confirmSaveInvoice),
                  ),
                if (_isSaved)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _downloadPdf,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(l10n.download),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareInvoice,
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => context.push('/billing'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(l10n.newBill),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
