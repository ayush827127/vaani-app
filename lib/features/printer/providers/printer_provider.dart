import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/printer_settings.dart';
import '../models/print_invoice_data.dart';
import '../repositories/printer_repository.dart';
import '../services/printer_service.dart';
import '../services/escpos_builder.dart';

// Re-export the types that the UI layer and billing layer need.
// They import this file; they never import transport packages directly.
export '../models/printer_settings.dart';
export '../models/print_invoice_data.dart';
export '../services/printer_service.dart' show BluetoothInfo, UsbPrinterDevice;

// ── Connection state ──────────────────────────────────────────────────────────

enum PrinterConnectionState { disconnected, connecting, connected, error }

// ── App state model ───────────────────────────────────────────────────────────

class PrinterState {
  final PrinterConnectionState connectionState;
  final PrinterSettings settings;
  final String? connectedDeviceName;
  final String? errorMessage;
  final bool isScanning;

  const PrinterState({
    this.connectionState = PrinterConnectionState.disconnected,
    this.settings = const PrinterSettings(),
    this.connectedDeviceName,
    this.errorMessage,
    this.isScanning = false,
  });

  bool get isConnected =>
      connectionState == PrinterConnectionState.connected;
  bool get isBusy =>
      connectionState == PrinterConnectionState.connecting || isScanning;

  PrinterState copyWith({
    PrinterConnectionState? connectionState,
    PrinterSettings? settings,
    String? connectedDeviceName,
    String? errorMessage,
    bool? isScanning,
    bool clearDeviceName = false,
    bool clearError = false,
  }) =>
      PrinterState(
        connectionState: connectionState ?? this.connectionState,
        settings: settings ?? this.settings,
        connectedDeviceName:
            clearDeviceName ? null : connectedDeviceName ?? this.connectedDeviceName,
        errorMessage:
            clearError ? null : errorMessage ?? this.errorMessage,
        isScanning: isScanning ?? this.isScanning,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PrinterNotifier extends StateNotifier<PrinterState> {
  PrinterNotifier() : super(const PrinterState()) {
    Future.microtask(_init);
  }

  final _repo = PrinterRepository();
  // All transport communication flows through PrinterService only.
  final _printerService = PrinterService();

  // ── Init & auto-reconnect ─────────────────────────────────────────────────

  Future<void> _init() async {
    final settings = await _repo.loadSettings();
    state = state.copyWith(settings: settings);
    if (settings.autoReconnect && settings.hasSavedPrinter) {
      await _tryAutoReconnect(settings);
    }
  }

  Future<void> _tryAutoReconnect(PrinterSettings settings) async {
    switch (settings.connectionType) {
      case 'bluetooth':
        if (settings.macAddress == null) return;
        try {
          final ok = await _printerService.bluetooth.requestPermissions();
          if (!ok) return;
          if (!await _printerService.bluetooth.isBluetoothOn()) return;
          final connected = await _printerService.bluetooth
              .connectByMac(settings.macAddress!);
          if (connected) {
            state = state.copyWith(
              connectionState: PrinterConnectionState.connected,
              connectedDeviceName: settings.printerName,
            );
          }
        } catch (_) {} // silent — auto-reconnect never surfaces errors

      case 'usb':
        if (settings.usbVendorId == null) return;
        try {
          final vid = int.tryParse(settings.usbVendorId ?? '0') ?? 0;
          final pid = int.tryParse(settings.usbProductId ?? '0') ?? 0;
          final devices = await _printerService.usb.getDevices();
          final match = devices.where(
              (d) => d.vendorId == vid && d.productId == pid);
          if (match.isEmpty) return;
          final connected = await _printerService.usb.connect(match.first);
          if (connected) {
            state = state.copyWith(
              connectionState: PrinterConnectionState.connected,
              connectedDeviceName: settings.printerName,
            );
          }
        } catch (_) {}
    }
  }

  // ── Bluetooth ─────────────────────────────────────────────────────────────

  Future<List<BluetoothInfo>> scanBluetooth() async {
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final ok = await _printerService.bluetooth.requestPermissions();
      if (!ok) {
        state = state.copyWith(
          isScanning: false,
          errorMessage: 'Bluetooth permission denied.',
        );
        return [];
      }
      if (!await _printerService.bluetooth.isBluetoothOn()) {
        state = state.copyWith(
          isScanning: false,
          errorMessage: 'Please turn on Bluetooth and try again.',
        );
        return [];
      }
      final devices = await _printerService.bluetooth.getPairedDevices();
      state = state.copyWith(isScanning: false, clearError: true);
      return devices;
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Scan failed: $e',
      );
      return [];
    }
  }

  Future<bool> connectBluetooth(BluetoothInfo device) async {
    state = state.copyWith(
      connectionState: PrinterConnectionState.connecting,
      clearError: true,
    );
    try {
      final connected = await _printerService.bluetooth.connect(device);
      if (connected) {
        final newSettings = state.settings.copyWith(
          printerName: device.name.isNotEmpty ? device.name : 'Bluetooth Printer',
          macAddress: device.macAdress, // upstream package typo — single 's'
          connectionType: 'bluetooth',
        );
        await _repo.saveSettings(newSettings);
        state = state.copyWith(
          connectionState: PrinterConnectionState.connected,
          settings: newSettings,
          connectedDeviceName: newSettings.printerName,
        );
        return true;
      } else {
        state = state.copyWith(
          connectionState: PrinterConnectionState.error,
          errorMessage:
              'Could not connect to ${device.name}. Make sure it is powered on and nearby.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        connectionState: PrinterConnectionState.error,
        errorMessage: 'Connection failed: $e',
      );
      return false;
    }
  }

  // ── USB ───────────────────────────────────────────────────────────────────

  Future<List<UsbPrinterDevice>> scanUsb() async {
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final devices = await _printerService.usb.getDevices();
      state = state.copyWith(isScanning: false);
      return devices;
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'USB scan failed: $e',
      );
      return [];
    }
  }

  Future<bool> connectUsb(UsbPrinterDevice device) async {
    state = state.copyWith(
      connectionState: PrinterConnectionState.connecting,
      clearError: true,
    );
    try {
      final connected = await _printerService.usb.connect(device);
      if (connected) {
        final newSettings = state.settings.copyWith(
          printerName: device.displayName,
          usbVendorId: '${device.vendorId}',
          usbProductId: '${device.productId}',
          connectionType: 'usb',
        );
        await _repo.saveSettings(newSettings);
        state = state.copyWith(
          connectionState: PrinterConnectionState.connected,
          settings: newSettings,
          connectedDeviceName: device.displayName,
        );
        return true;
      } else {
        state = state.copyWith(
          connectionState: PrinterConnectionState.error,
          errorMessage: 'Could not connect to ${device.displayName}.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        connectionState: PrinterConnectionState.error,
        errorMessage: 'USB connection failed: $e',
      );
      return false;
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    try {
      await _printerService.disconnectAll();
    } catch (_) {}
    await _repo.clearPrinterInfo();
    final cleared = state.settings.copyWith(
      connectionType: 'none',
      clearPrinterName: true,
      clearMac: true,
      clearUsbIds: true,
    );
    state = state.copyWith(
      connectionState: PrinterConnectionState.disconnected,
      settings: cleared,
      clearDeviceName: true,
      clearError: true,
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> updateSettings(PrinterSettings settings) async {
    await _repo.saveSettings(settings);
    state = state.copyWith(settings: settings);
  }

  // ── Printing ──────────────────────────────────────────────────────────────

  Future<bool> testPrint() async {
    if (!state.isConnected) return false;
    try {
      final bytes = await EscPosBuilder.buildTestPage(state.settings);
      return await _printerService.sendBytes(
          bytes, state.settings.connectionType);
    } catch (_) {
      return false;
    }
  }

  Future<bool> printInvoice(PrintInvoiceData data) async {
    if (!state.isConnected) return false;
    try {
      final bytes = await EscPosBuilder.buildInvoice(data, state.settings);
      return await _printerService.sendBytes(
          bytes, state.settings.connectionType);
    } catch (_) {
      return false;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final printerProvider =
    StateNotifierProvider<PrinterNotifier, PrinterState>(
  (ref) => PrinterNotifier(),
);
