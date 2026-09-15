import 'bluetooth_printer_service.dart';
import 'usb_printer_service.dart';
import 'network_printer_service.dart';

export 'bluetooth_printer_service.dart' show BluetoothInfo;
export 'usb_printer_service.dart' show UsbPrinterDevice;

/// Single entry-point for all printer communication.
///
/// The billing module (and any future module) calls [PrinterService] only.
/// It never imports a specific transport package.
///
/// Transport hierarchy:
///   PrinterService
///     ├── BluetoothPrinterService  (Bluetooth Classic / SPP)
///     ├── UsbPrinterService        (USB OTG / Host)
///     └── NetworkPrinterService    (Wi-Fi / LAN  — future)
class PrinterService {
  PrinterService({
    BluetoothPrinterService? bluetooth,
    UsbPrinterService? usb,
    NetworkPrinterService? network,
  })  : bluetooth = bluetooth ?? BluetoothPrinterService(),
        usb = usb ?? UsbPrinterService(),
        network = network ?? NetworkPrinterService();

  final BluetoothPrinterService bluetooth;
  final UsbPrinterService usb;
  final NetworkPrinterService network;

  // ── Unified byte delivery ──────────────────────────────────────────────────

  /// Sends raw ESC/POS bytes to whichever transport is active.
  /// Returns `false` (never throws) when the connection type is unknown or
  /// the underlying write fails, so callers can handle it gracefully.
  Future<bool> sendBytes(List<int> bytes, String connectionType) async {
    switch (connectionType) {
      case 'bluetooth':
        return bluetooth.writeBytes(bytes);
      case 'usb':
        return usb.writeBytes(bytes);
      case 'network':
        return network.writeBytes(bytes);
      default:
        return false;
    }
  }

  // ── Disconnect all transports ──────────────────────────────────────────────

  Future<void> disconnectAll() async {
    await bluetooth.disconnect();
    await usb.disconnect();
    await network.disconnect();
  }
}
