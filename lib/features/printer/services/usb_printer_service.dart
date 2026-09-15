import 'dart:typed_data';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';

class UsbPrinterDevice {
  final int vendorId;
  final int productId;
  final String? productName;
  final String? manufacturerName;

  const UsbPrinterDevice({
    required this.vendorId,
    required this.productId,
    this.productName,
    this.manufacturerName,
  });

  String get displayName => productName ?? manufacturerName ?? 'USB Printer ($vendorId:$productId)';
}

class UsbPrinterService {
  final _usb = FlutterUsbPrinter();
  bool _connected = false;

  Future<List<UsbPrinterDevice>> getDevices() async {
    try {
      final raw = await FlutterUsbPrinter.getUSBDeviceList();
      return raw
          .map((m) => UsbPrinterDevice(
                vendorId: m['vendorId'] as int? ?? 0,
                productId: m['productId'] as int? ?? 0,
                productName: m['productName'] as String?,
                manufacturerName: m['manufacturerName'] as String?,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(UsbPrinterDevice device) async {
    try {
      final ok = await _usb.connect(device.vendorId, device.productId);
      _connected = ok == true;
      return _connected;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      _usb.close();
    } catch (_) {}
    _connected = false;
  }

  bool get isConnected => _connected;

  Future<bool> writeBytes(List<int> bytes) async {
    if (!_connected) return false;
    try {
      await _usb.write(Uint8List.fromList(bytes));
      return true;
    } catch (_) {
      return false;
    }
  }
}
