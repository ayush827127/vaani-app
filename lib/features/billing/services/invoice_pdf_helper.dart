import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/shop.dart';
import '../../../shared/widgets/shop_logo_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../repositories/invoice_repository.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class InvoicePdfHelper {
  /// Load an invoice by ID from the DB, generate its PDF and share.
  static Future<void> shareById(
    BuildContext context,
    int invoiceId,
    int shopId,
  ) async {
    if (!context.mounted) return;
    final l10n = context.l10n;

    final invoiceRepo = getIt<InvoiceRepository>();
    final shopRepo = getIt<ShopRepository>();
    final customerRepo = getIt<CustomerRepository>();

    final invoice = await invoiceRepo.getInvoiceById(invoiceId);
    if (invoice == null) return;

    final shop = await shopRepo.getShop();
    Customer? customer;
    if (invoice.customerId != null) {
      customer = await customerRepo.getCustomerById(invoice.customerId!);
    }

    final bytes = await buildPdfBytes(
      l10n: l10n,
      shop: shop,
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.createdAt,
      customer: customer,
      paymentMode: invoice.paymentMode,
      status: invoice.status,
      items: invoice.items
          .map((it) => (
                name: it.productName,
                qty: it.quantity,
                price: it.sellingPrice,
                total: it.lineTotal,
              ))
          .toList(),
      subtotal: invoice.subtotal,
      gstAmount: invoice.gstAmount,
      discountAmount: invoice.discountAmount,
      grandTotal: invoice.grandTotal,
    );

    await _share(bytes, invoice.invoiceNumber);
  }

  static Future<void> _share(Uint8List bytes, String invoiceNumber) async {
    final dir = await getTemporaryDirectory();
    final safeName = invoiceNumber.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-');
    final filePath = '${dir.path}/invoice_$safeName.pdf';
    await File(filePath).writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(filePath, mimeType: 'application/pdf')],
      subject: 'Invoice $invoiceNumber',
    ));
  }

  static Future<Uint8List> buildPdfBytes({
    required AppLocalizations l10n,
    required Shop? shop,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required Customer? customer,
    required String paymentMode,
    String status = 'paid',
    required List<({String name, int qty, double price, double total})> items,
    required double subtotal,
    required double gstAmount,
    required double discountAmount,
    required double grandTotal,
  }) async {
    final doc = pw.Document();

    pw.Font regular = pw.Font.helvetica();
    pw.Font bold = pw.Font.helveticaBold();
    try {
      regular = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}

    pw.MemoryImage? shopLogoImage;
    final logoBytes =
        await fetchShopLogoBytes(logoPath: shop?.logoPath, logoUrl: shop?.logoUrl);
    if (logoBytes != null) {
      shopLogoImage = pw.MemoryImage(logoBytes);
    }

    pw.MemoryImage? qrImage;
    final isUpi = paymentMode == 'upi';
    final upiId = shop?.upiId;
    if (isUpi && upiId != null && upiId.isNotEmpty) {
      final name = Uri.encodeComponent(shop?.name ?? '');
      final amount = grandTotal.toStringAsFixed(2);
      final deepLink = 'upi://pay?pa=$upiId&pn=$name&am=$amount&cu=INR';
      try {
        final painter = QrPainter(
          data: deepLink,
          version: QrVersions.auto,
          eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
        );
        final imgData =
            await painter.toImageData(300, format: ui.ImageByteFormat.png);
        if (imgData != null) {
          qrImage = pw.MemoryImage(imgData.buffer.asUint8List());
        }
      } catch (_) {}
    }

    const kLabelSize = 10.0;
    const kValueSize = 10.0;
    const kSummarySize = 11.0;
    const kHeaderSize = 22.0;
    const kBorderColor = PdfColors.grey400;
    const kHeaderBg = PdfColors.grey100;

    pw.Widget cell(
      String text, {
      bool isBold = false,
      pw.TextAlign align = pw.TextAlign.left,
      bool isHeader = false,
    }) =>
        pw.Container(
          color: isHeader ? kHeaderBg : null,
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                fontSize: kLabelSize,
                fontWeight:
                    isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        );

    pw.Widget infoRow(String label, String value) => pw.Padding(
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
                        style: const pw.TextStyle(fontSize: kValueSize))),
              ]),
        );

    pw.Widget summaryRow(String label, String value,
            {bool isBold = false, double fontSize = kSummarySize}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(label,
                    style: pw.TextStyle(
                        fontSize: fontSize,
                        fontWeight: isBold
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal)),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: fontSize,
                        fontWeight: isBold
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal)),
              ]),
        );

    final date = invoiceDate;
    final hour12 = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final timeStr =
        '${hour12.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      build: (pw.Context ctx) => [
        if (shopLogoImage != null) ...[
          pw.Center(
              child: pw.ClipOval(
                  child: pw.Image(shopLogoImage,
                      width: 70, height: 70, fit: pw.BoxFit.cover))),
          pw.SizedBox(height: 8),
        ],
        pw.Center(
            child: pw.Text(shop?.name ?? l10n.shopFallback,
                style: pw.TextStyle(
                    fontSize: kHeaderSize, fontWeight: pw.FontWeight.bold))),
        if (shop?.ownerName != null && shop!.ownerName.isNotEmpty)
          pw.Center(
              child: pw.Text(shop.ownerName,
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey800))),
        if (shop?.address != null) ...[
          pw.SizedBox(height: 2),
          pw.Center(
              child: pw.Text('Address: ${shop!.address!}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center)),
        ],
        if (shop?.phone != null && shop!.phone.isNotEmpty)
          pw.Center(
              child: pw.Text('Phone: ${shop.phone}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700))),
        if (shop?.gstNumber != null)
          pw.Center(
              child: pw.Text('GSTIN: ${shop!.gstNumber!}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700))),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1.5, color: PdfColors.grey700),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                infoRow('Invoice No', invoiceNumber),
                infoRow('Date', AppFormatters.formatDate(date)),
                infoRow('Time', timeStr),
              ])),
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                infoRow('Customer', customer?.name ?? l10n.walkInCustomer),
                if (customer?.phone != null) infoRow('Phone', customer!.phone!),
                infoRow('Payment', localizedPaymentMode(l10n, paymentMode)),
                infoRow('Status', _statusLabel(status)),
              ])),
        ]),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
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
            ...items.map((it) => pw.TableRow(children: [
                  cell(it.name),
                  cell('${it.qty}', align: pw.TextAlign.center),
                  cell('Rs.${it.price.toStringAsFixed(2)}',
                      align: pw.TextAlign.right),
                  cell('Rs.${it.total.toStringAsFixed(2)}',
                      align: pw.TextAlign.right),
                ])),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        summaryRow(l10n.subtotal, 'Rs.${subtotal.toStringAsFixed(2)}'),
        if (discountAmount > 0)
          summaryRow(
              l10n.discount, '-Rs.${discountAmount.toStringAsFixed(2)}'),
        if (gstAmount > 0)
          summaryRow(l10n.gst, 'Rs.${gstAmount.toStringAsFixed(2)}'),
        pw.Divider(thickness: 1, color: PdfColors.grey500),
        summaryRow(l10n.grandTotal, 'Rs.${grandTotal.toStringAsFixed(2)}',
            isBold: true, fontSize: 13),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.5, color: PdfColors.grey700),
        if (qrImage != null) ...[
          pw.SizedBox(height: 10),
          pw.Center(
              child: pw.Text(l10n.scanToPayUpi,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 12))),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Image(qrImage, width: 110, height: 110)),
          pw.SizedBox(height: 4),
          pw.Center(
              child: pw.Text(shop?.upiId ?? '',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700))),
          pw.Center(
              child: pw.Text('Amount: Rs.${grandTotal.toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        ],
        pw.SizedBox(height: 12),
        pw.Center(
            child: pw.Text(l10n.thankYouShopping,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold))),
        pw.Center(
            child: pw.Text('Visit us again!',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700))),
        pw.SizedBox(height: 4),
        pw.Center(
            child: pw.Text(l10n.generatedByVaani,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey500))),
        pw.SizedBox(height: 8),
      ],
    ));

    return await doc.save();
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'PAID';
      case 'partial_paid':
        return 'PARTIAL PAID';
      case 'cancelled':
        return 'CANCELLED';
      case 'pending':
        return 'PENDING';
      default:
        return status.toUpperCase();
    }
  }
}
