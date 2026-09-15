import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_settings.dart';

class PrinterRepository {
  static const _key = 'printer_settings_v1';

  Future<PrinterSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const PrinterSettings();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PrinterSettings.fromMap(map);
    } catch (_) {
      return const PrinterSettings();
    }
  }

  Future<void> saveSettings(PrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toMap()));
  }

  Future<void> clearPrinterInfo() async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(
      connectionType: 'none',
      clearPrinterName: true,
      clearMac: true,
      clearUsbIds: true,
    ));
  }
}
