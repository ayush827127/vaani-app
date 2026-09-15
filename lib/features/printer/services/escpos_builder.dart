import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/print_invoice_data.dart';
import '../models/printer_settings.dart';

class EscPosBuilder {
  static Future<List<int>> buildTestPage(PrinterSettings settings) async {
    final profile = await CapabilityProfile.load();
    final size = settings.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(size, profile);
    final w = settings.paperWidth == 80 ? 48 : 32;

    List<int> bytes = [];
    bytes += gen.reset();
    bytes += gen.text(_dashes(w, '='), styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('VAANI AI BILLING',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += gen.emptyLines(1);
    bytes += gen.text('Printer Connected Successfully',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.emptyLines(1);
    bytes += gen.text(_dashes(w, '-'));
    bytes += gen.text(_now(), styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text(_dashes(w, '-'));
    bytes += gen.emptyLines(1);
    bytes += gen.text('Paper Width: ${settings.paperWidth}mm',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.emptyLines(1);
    bytes += gen.text(_dashes(w, '='), styles: const PosStyles(align: PosAlign.center));
    bytes += gen.feed(3);
    bytes += gen.cut();
    return bytes;
  }

  static Future<List<int>> buildInvoice(
    PrintInvoiceData data,
    PrinterSettings settings,
  ) async {
    final profile = await CapabilityProfile.load();
    final size = settings.paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(size, profile);
    final w = settings.paperWidth == 80 ? 48 : 32;

    List<int> bytes = [];
    bytes += gen.reset();

    // ── Shop header ──────────────────────────────────────────────────
    bytes += gen.text(_dashes(w, '='));
    bytes += gen.text(data.shopName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += gen.emptyLines(1);
    if (data.shopAddress != null) {
      bytes += gen.text(data.shopAddress!, styles: const PosStyles(align: PosAlign.center));
    }
    if (data.shopPhone != null) {
      bytes += gen.text('Tel: ${data.shopPhone}', styles: const PosStyles(align: PosAlign.center));
    }
    if (data.shopGstNumber != null) {
      bytes += gen.text('GSTIN: ${data.shopGstNumber}', styles: const PosStyles(align: PosAlign.center));
    }

    bytes += gen.text(_dashes(w, '='));

    // ── Invoice meta ─────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Invoice:', width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text: data.invoiceNumber, width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Date:', width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text: _formatDate(data.invoiceDate), width: 8),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Customer:', width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text: data.customerName ?? 'Walk-in Customer', width: 8),
    ]);
    if (data.customerPhone != null) {
      bytes += gen.row([
        PosColumn(text: 'Phone:', width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text: data.customerPhone!, width: 8),
      ]);
    }
    bytes += gen.row([
      PosColumn(text: 'Payment:', width: 4, styles: const PosStyles(bold: true)),
      PosColumn(text: data.paymentMode.toUpperCase(), width: 8),
    ]);

    bytes += gen.text(_dashes(w, '-'));

    // ── Items header ─────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
      PosColumn(text: 'Price', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      PosColumn(text: 'Total', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += gen.text(_dashes(w, '-'));

    // ── Items ────────────────────────────────────────────────────────
    for (final item in data.items) {
      // Long names wrap onto a second line
      final name = item.name.length > 16 ? item.name.substring(0, 16) : item.name;
      bytes += gen.row([
        PosColumn(text: name, width: 6),
        PosColumn(text: '${item.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: _rs(item.price), width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: _rs(item.total), width: 2, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += gen.text(_dashes(w, '-'));

    // ── Totals ───────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Subtotal', width: 8),
      PosColumn(text: '${String.fromCharCode(0x20B9)}${data.subtotal.toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (settings.showGst && data.gstAmount > 0) {
      bytes += gen.row([
        PosColumn(text: 'GST', width: 8),
        PosColumn(text: '${String.fromCharCode(0x20B9)}${data.gstAmount.toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    if (data.discountAmount > 0) {
      bytes += gen.row([
        PosColumn(text: 'Discount', width: 8),
        PosColumn(text: '-${String.fromCharCode(0x20B9)}${data.discountAmount.toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += gen.text(_dashes(w, '='));
    bytes += gen.row([
      PosColumn(text: 'TOTAL', width: 8, styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
      PosColumn(
          text: '${String.fromCharCode(0x20B9)}${data.grandTotal.toStringAsFixed(2)}',
          width: 4,
          styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2, width: PosTextSize.size2)),
    ]);
    bytes += gen.text(_dashes(w, '='));

    // ── Footer ───────────────────────────────────────────────────────
    bytes += gen.emptyLines(1);
    bytes += gen.text('Thank you for shopping!', styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('Generated by VAANI App', styles: const PosStyles(align: PosAlign.center));
    bytes += gen.emptyLines(1);
    bytes += gen.text(_dashes(w, '-'));

    bytes += gen.feed(3);
    bytes += gen.cut();

    if (settings.printDuplicate) {
      // Add a second copy
      final copy = await buildInvoice(
        data,
        settings.copyWith(printDuplicate: false), // prevent infinite recursion
      );
      bytes += copy;
    }

    return bytes;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _dashes(int width, [String ch = '-']) => ch * width;

  static String _rs(double amount) => amount.toStringAsFixed(2);

  static String _now() {
    final now = DateTime.now();
    final d = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
