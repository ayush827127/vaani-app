import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/printer_provider.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  // ── Bluetooth scan sheet ─────────────────────────────────────────────────

  Future<void> _showBluetoothSheet() async {
    final devices = await ref.read(printerProvider.notifier).scanBluetooth();
    if (!mounted) return;

    final state = ref.read(printerProvider);
    if (state.errorMessage != null && devices.isEmpty) {
      _snack(state.errorMessage!, error: true);
      return;
    }

    if (devices.isEmpty) {
      _snack('No paired Bluetooth printers found.\nPair your printer in System Settings → Bluetooth first.');
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BluetoothDeviceSheet(devices: devices, onSelect: _connectBluetooth),
    );
  }

  Future<void> _connectBluetooth(BluetoothInfo device) async {
    Navigator.pop(context); // close sheet
    final ok = await ref.read(printerProvider.notifier).connectBluetooth(device);
    if (!mounted) return;
    if (ok) {
      _snack('Connected to ${device.name.isNotEmpty ? device.name : 'printer'}');
    } else {
      final err = ref.read(printerProvider).errorMessage ?? 'Connection failed.';
      _snack(err, error: true);
    }
  }

  // ── USB scan sheet ────────────────────────────────────────────────────────

  Future<void> _showUsbSheet() async {
    final devices = await ref.read(printerProvider.notifier).scanUsb();
    if (!mounted) return;

    if (devices.isEmpty) {
      _snack('No USB printers found. Connect your printer via OTG cable.');
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UsbDeviceSheet(devices: devices, onSelect: _connectUsb),
    );
  }

  Future<void> _connectUsb(UsbPrinterDevice device) async {
    Navigator.pop(context);
    final ok = await ref.read(printerProvider.notifier).connectUsb(device);
    if (!mounted) return;
    if (ok) {
      _snack('Connected to ${device.displayName}');
    } else {
      final err = ref.read(printerProvider).errorMessage ?? 'Connection failed.';
      _snack(err, error: true);
    }
  }

  // ── Test print ────────────────────────────────────────────────────────────

  Future<void> _testPrint() async {
    _snack('Sending test print...');
    final ok = await ref.read(printerProvider.notifier).testPrint();
    if (!mounted) return;
    _snack(ok ? 'Test print sent!' : 'Test print failed. Check printer connection.', error: !ok);
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect Printer', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to disconnect the current printer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(printerProvider.notifier).disconnect();
      if (mounted) _snack('Printer disconnected.');
    }
  }

  // ── Settings toggles ──────────────────────────────────────────────────────

  void _toggleSetting(PrinterSettings updated) {
    ref.read(printerProvider.notifier).updateSettings(updated);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printerProvider);
    final s = state.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Management', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connect section ───────────────────────────────────────
          _SectionHeader('Printer Connection'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ConnectButton(
                  icon: Icons.bluetooth_rounded,
                  label: 'Bluetooth',
                  onTap: state.isBusy ? null : _showBluetoothSheet,
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ConnectButton(
                  icon: Icons.usb_rounded,
                  label: 'USB',
                  onTap: state.isBusy ? null : _showUsbSheet,
                  color: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),

          if (state.isBusy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
          ],

          const SizedBox(height: 16),

          // ── Status card ───────────────────────────────────────────
          _SectionHeader('Connection Status'),
          const SizedBox(height: 10),
          _StatusCard(state: state, s: s),

          // ── Actions (only when connected) ─────────────────────────
          if (state.isConnected) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testPrint,
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Test Print'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off_rounded, size: 18, color: Colors.red),
                    label: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ── Paper width ───────────────────────────────────────────
          _SectionHeader('Paper Settings'),
          const SizedBox(height: 10),
          _card(
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text('Paper Width', style: TextStyle(fontWeight: FontWeight.w500))),
                _PaperWidthToggle(
                  current: s.paperWidth,
                  onChanged: (w) => _toggleSetting(s.copyWith(paperWidth: w)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Print settings ────────────────────────────────────────
          _SectionHeader('Print Settings'),
          const SizedBox(height: 10),
          _card(
            child: Column(
              children: [
                _ToggleRow(
                  label: 'Auto Print',
                  subtitle: 'Print automatically after saving invoice',
                  value: s.autoPrint,
                  onChanged: (v) => _toggleSetting(s.copyWith(autoPrint: v)),
                ),
                _divider(),
                _ToggleRow(
                  label: 'Print Duplicate',
                  subtitle: 'Print 2 copies of each invoice',
                  value: s.printDuplicate,
                  onChanged: (v) => _toggleSetting(s.copyWith(printDuplicate: v)),
                ),
                _divider(),
                _ToggleRow(
                  label: 'Show GST',
                  subtitle: 'Include GST amount on invoice',
                  value: s.showGst,
                  onChanged: (v) => _toggleSetting(s.copyWith(showGst: v)),
                ),
                _divider(),
                _ToggleRow(
                  label: 'Print Logo',
                  subtitle: 'Print shop logo at top (PDF only)',
                  value: s.printLogo,
                  onChanged: (v) => _toggleSetting(s.copyWith(printLogo: v)),
                ),
                _divider(),
                _ToggleRow(
                  label: 'Print QR Code',
                  subtitle: 'Print UPI QR code for payment',
                  value: s.printQrCode,
                  onChanged: (v) => _toggleSetting(s.copyWith(printQrCode: v)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Reconnect settings ────────────────────────────────────
          _SectionHeader('Reconnect'),
          const SizedBox(height: 10),
          _card(
            child: _ToggleRow(
              label: 'Auto Reconnect',
              subtitle: 'Reconnect to saved printer on app startup',
              value: s.autoReconnect,
              onChanged: (v) => _toggleSetting(s.copyWith(autoReconnect: v)),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: child,
      );

  Widget _divider() => const Divider(height: 1, indent: 0, endIndent: 0);
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );
}

class _ConnectButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  const _ConnectButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

class _StatusCard extends StatelessWidget {
  final PrinterState state;
  final PrinterSettings s;
  const _StatusCard({required this.state, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected = state.isConnected;
    final dotColor = isConnected ? AppColors.success : Colors.grey;
    final statusText = switch (state.connectionState) {
      PrinterConnectionState.connected => 'Connected',
      PrinterConnectionState.connecting => 'Connecting...',
      PrinterConnectionState.error => 'Error',
      PrinterConnectionState.disconnected => 'Not Connected',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? AppColors.success.withValues(alpha: 0.4)
              : cs.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle,
                    boxShadow: isConnected ? [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 6)] : null),
              ),
              const SizedBox(width: 10),
              Text(statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isConnected ? AppColors.success : cs.onSurface.withValues(alpha: 0.6),
                  )),
            ],
          ),
          if (isConnected) ...[
            const SizedBox(height: 12),
            _infoRow('Printer Name', state.connectedDeviceName ?? s.printerName ?? '—'),
            const SizedBox(height: 4),
            _infoRow('Connection', s.connectionType == 'bluetooth' ? 'Bluetooth' : 'USB'),
            const SizedBox(height: 4),
            _infoRow('Paper Width', '${s.paperWidth} mm'),
          ] else if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(state.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ] else ...[
            const SizedBox(height: 8),
            Text('No printer connected. Tap Connect above.',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      );
}

class _PaperWidthToggle extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChanged;
  const _PaperWidthToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [58, 80].map((w) {
          final active = current == w;
          return GestureDetector(
            onTap: () => onChanged(w),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryLight.withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.primaryLight : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text('$w mm',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? AppColors.primaryLight : null,
                  )),
            ),
          );
        }).toList(),
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primaryLight,
            ),
          ],
        ),
      );
}

// ── Bottom sheet: Bluetooth devices ──────────────────────────────────────────

class _BluetoothDeviceSheet extends StatelessWidget {
  final List<BluetoothInfo> devices;
  final ValueChanged<BluetoothInfo> onSelect;
  const _BluetoothDeviceSheet({required this.devices, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_rounded, color: AppColors.primaryLight),
                const SizedBox(width: 10),
                const Text('Select Bluetooth Printer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Paired Bluetooth devices:', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
            const SizedBox(height: 8),
            ...devices.map((d) => ListTile(
                  leading: const Icon(Icons.print_rounded, color: AppColors.primaryLight),
                  title: Text(d.name.isNotEmpty ? d.name : 'Unknown device'),
                  subtitle: Text(d.macAdress, style: const TextStyle(fontSize: 12)),
                  onTap: () => onSelect(d),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                )),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Don\'t see your printer? Pair it in System Settings → Bluetooth first, then return here.',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet: USB devices ─────────────────────────────────────────────────

class _UsbDeviceSheet extends StatelessWidget {
  final List<UsbPrinterDevice> devices;
  final ValueChanged<UsbPrinterDevice> onSelect;
  const _UsbDeviceSheet({required this.devices, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.usb_rounded, color: AppColors.primaryLight),
                const SizedBox(width: 10),
                const Text('Select USB Printer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            ...devices.map((d) => ListTile(
                  leading: const Icon(Icons.print_rounded, color: AppColors.primaryLight),
                  title: Text(d.displayName),
                  subtitle: Text('VID: ${d.vendorId}  PID: ${d.productId}',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => onSelect(d),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
