import 'dart:ui' as ui;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n_extensions.dart';

class BarcodePreviewScreen extends StatefulWidget {
  final String barcode;
  final String itemName;

  const BarcodePreviewScreen({
    super.key,
    required this.barcode,
    required this.itemName,
  });

  @override
  State<BarcodePreviewScreen> createState() => _BarcodePreviewScreenState();
}

class _BarcodePreviewScreenState extends State<BarcodePreviewScreen> {
  final _repaintKey = GlobalKey();
  bool _printing = false;

  Barcode get _barcodeType {
    final v = widget.barcode;
    final isNumeric = RegExp(r'^\d+$').hasMatch(v);
    if (isNumeric && v.length == 13) return Barcode.ean13();
    if (isNumeric && v.length == 12) return Barcode.upcA();
    if (isNumeric && v.length == 8) return Barcode.ean8();
    return Barcode.code128();
  }

  Future<void> _printLabel() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      // Capture the rendered barcode widget as PNG bytes
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      pw.Font bold = pw.Font.helveticaBold();
      pw.Font regular = pw.Font.helvetica();
      try {
        bold = await PdfGoogleFonts.notoSansBold();
        regular = await PdfGoogleFonts.notoSansRegular();
      } catch (_) {}

      await Printing.layoutPdf(
        onLayout: (format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: format,
              theme: pw.ThemeData.withFont(base: regular, bold: bold),
              margin: const pw.EdgeInsets.all(32),
              build: (ctx) => pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      widget.itemName,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Container(
                      width: 220,
                      height: 90,
                      child: pw.Image(pw.MemoryImage(pngBytes),
                          fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      widget.barcode,
                      style: const pw.TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
          return pdf.save();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.barcodePreview),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.itemName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Barcode card — always white background for scannability
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.surfaceBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    RepaintBoundary(
                      key: _repaintKey,
                      child: ColoredBox(
                        color: Colors.white,
                        child: BarcodeWidget(
                          barcode: _barcodeType,
                          data: widget.barcode,
                          width: 280,
                          height: 100,
                          drawText: false,
                          backgroundColor: Colors.white,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.barcode,
                      style: const TextStyle(
                        fontSize: 16,
                        letterSpacing: 3,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _printing ? null : _printLabel,
                  icon: _printing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print_rounded),
                  label: Text(
                    _printing ? l10n.printing : l10n.printBarcode,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
