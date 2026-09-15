class PrinterSettings {
  final String? printerName;
  final String? macAddress;
  final String? usbVendorId;
  final String? usbProductId;
  final String connectionType; // 'none' | 'bluetooth' | 'usb'
  final int paperWidth; // 58 | 80
  final bool autoPrint;
  final bool printDuplicate;
  final bool showGst;
  final bool printLogo;
  final bool printQrCode;
  final bool autoReconnect;

  const PrinterSettings({
    this.printerName,
    this.macAddress,
    this.usbVendorId,
    this.usbProductId,
    this.connectionType = 'none',
    this.paperWidth = 58,
    this.autoPrint = false,
    this.printDuplicate = false,
    this.showGst = true,
    this.printLogo = true,
    this.printQrCode = true,
    this.autoReconnect = true,
  });

  bool get hasSavedPrinter => connectionType != 'none' && printerName != null;

  PrinterSettings copyWith({
    String? printerName,
    String? macAddress,
    String? usbVendorId,
    String? usbProductId,
    String? connectionType,
    int? paperWidth,
    bool? autoPrint,
    bool? printDuplicate,
    bool? showGst,
    bool? printLogo,
    bool? printQrCode,
    bool? autoReconnect,
    // Allow explicitly clearing nullable fields
    bool clearPrinterName = false,
    bool clearMac = false,
    bool clearUsbIds = false,
  }) =>
      PrinterSettings(
        printerName: clearPrinterName ? null : printerName ?? this.printerName,
        macAddress: clearMac ? null : macAddress ?? this.macAddress,
        usbVendorId: clearUsbIds ? null : usbVendorId ?? this.usbVendorId,
        usbProductId: clearUsbIds ? null : usbProductId ?? this.usbProductId,
        connectionType: connectionType ?? this.connectionType,
        paperWidth: paperWidth ?? this.paperWidth,
        autoPrint: autoPrint ?? this.autoPrint,
        printDuplicate: printDuplicate ?? this.printDuplicate,
        showGst: showGst ?? this.showGst,
        printLogo: printLogo ?? this.printLogo,
        printQrCode: printQrCode ?? this.printQrCode,
        autoReconnect: autoReconnect ?? this.autoReconnect,
      );

  Map<String, dynamic> toMap() => {
        'printerName': printerName,
        'macAddress': macAddress,
        'usbVendorId': usbVendorId,
        'usbProductId': usbProductId,
        'connectionType': connectionType,
        'paperWidth': paperWidth,
        'autoPrint': autoPrint,
        'printDuplicate': printDuplicate,
        'showGst': showGst,
        'printLogo': printLogo,
        'printQrCode': printQrCode,
        'autoReconnect': autoReconnect,
      };

  factory PrinterSettings.fromMap(Map<String, dynamic> m) => PrinterSettings(
        printerName: m['printerName'] as String?,
        macAddress: m['macAddress'] as String?,
        usbVendorId: m['usbVendorId'] as String?,
        usbProductId: m['usbProductId'] as String?,
        connectionType: (m['connectionType'] as String?) ?? 'none',
        paperWidth: (m['paperWidth'] as int?) ?? 58,
        autoPrint: (m['autoPrint'] as bool?) ?? false,
        printDuplicate: (m['printDuplicate'] as bool?) ?? false,
        showGst: (m['showGst'] as bool?) ?? true,
        printLogo: (m['printLogo'] as bool?) ?? true,
        printQrCode: (m['printQrCode'] as bool?) ?? true,
        autoReconnect: (m['autoReconnect'] as bool?) ?? true,
      );
}
