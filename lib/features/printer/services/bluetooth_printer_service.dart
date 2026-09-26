import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

// Re-export the device model so callers only need to import this service file
export 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart'
    show BluetoothInfo;

/// Wraps the print_bluetooth_thermal static API for testability and separation
/// of concerns.  The billing module never calls PrintBluetoothThermal directly.
class BluetoothPrinterService {
  // ── Permissions ────────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    try {
      // Android 12+ requires BLUETOOTH_CONNECT + BLUETOOTH_SCAN — checked
      // first so an already-granted pair (the common case on every launch
      // after the first, since this runs on every app start via
      // PrinterNotifier's auto-reconnect) never calls .request() at all.
      final connectGranted = await Permission.bluetoothConnect.status;
      final scanGranted = await Permission.bluetoothScan.status;
      if (connectGranted.isGranted && scanGranted.isGranted) return true;

      final results = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();

      final allOk =
          results.values.every((s) => s.isGranted || s.isRestricted);
      if (allOk) return true;

      // Older Android (<12) needs fine location for BT scan discovery —
      // same check-first treatment.
      if ((await Permission.location.status).isGranted) return true;
      final loc = await Permission.location.request();
      return loc.isGranted;
    } catch (_) {
      return true; // permissions API not available on this device — proceed
    }
  }

  // ── Adapter state ──────────────────────────────────────────────────────────

  Future<bool> isBluetoothOn() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  // ── Device discovery ───────────────────────────────────────────────────────

  /// Returns OS-paired Bluetooth devices.  The user must pair the printer
  /// in Android Settings → Bluetooth before it appears here.
  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<bool> connect(BluetoothInfo device) async {
    try {
      return await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress, // upstream package typo — single 's'
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectByMac(String macAddress) async {
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect; // getter, not a method call
    } catch (_) {}
  }

  // ── Status ─────────────────────────────────────────────────────────────────

  Future<bool> isConnected() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  // ── Printing ───────────────────────────────────────────────────────────────

  Future<bool> writeBytes(List<int> bytes) async {
    try {
      return await PrintBluetoothThermal.writeBytes(bytes); // positional argument
    } catch (_) {
      return false;
    }
  }
}
