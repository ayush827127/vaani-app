import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera barcode / QR scanner.
/// Pops with the scanned [String] value, or null if the user cancels.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value != null && value.isNotEmpty) {
      _scanned = true;
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Barcode'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          CustomPaint(
            painter: _ScanOverlayPainter(borderColor: cs.primary),
            child: const SizedBox.expand(),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Point camera at barcode or QR code',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final Color borderColor;
  const _ScanOverlayPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    const scanSize = 240.0;
    const cornerLen = 28.0;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2;

    final overlay = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), overlay);
    canvas.drawRect(Rect.fromLTWH(0, top + scanSize, size.width, size.height - top - scanSize), overlay);
    canvas.drawRect(Rect.fromLTWH(0, top, left, scanSize), overlay);
    canvas.drawRect(Rect.fromLTWH(left + scanSize, top, size.width - left - scanSize, scanSize), overlay);

    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Four corner brackets
    final corners = [
      [Offset(left, top + cornerLen), Offset(left, top), Offset(left + cornerLen, top)],
      [Offset(left + scanSize - cornerLen, top), Offset(left + scanSize, top), Offset(left + scanSize, top + cornerLen)],
      [Offset(left, top + scanSize - cornerLen), Offset(left, top + scanSize), Offset(left + cornerLen, top + scanSize)],
      [Offset(left + scanSize - cornerLen, top + scanSize), Offset(left + scanSize, top + scanSize), Offset(left + scanSize, top + scanSize - cornerLen)],
    ];
    for (final pts in corners) {
      canvas.drawLine(pts[0], pts[1], border);
      canvas.drawLine(pts[1], pts[2], border);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
