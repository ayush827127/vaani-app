import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../core/auth/logout_helper.dart';
import '../../../shared/models/shop.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../../../l10n/l10n_extensions.dart';

const _kNotifKey = 'notif_enabled';
const _kLanguages = ['English', 'Hindi'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Shop? _shop;
  bool _notifsEnabled = true;
  bool _exporting = false;
  DateTime? _lastSyncedAt;
  bool _syncingData = false;

  @override
  void initState() {
    super.initState();
    _loadShop();
    _loadPrefs();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    final lastSyncedAt = await getIt<DataSyncRepository>().getLastSyncedAt();
    if (!mounted) return;
    setState(() => _lastSyncedAt = lastSyncedAt);
  }

  Future<void> _syncDataNow() async {
    setState(() => _syncingData = true);
    final result = await getIt<DataSyncRepository>().syncNow();
    await ref.read(subscriptionProvider.notifier).reloadFromCache();
    if (!mounted) return;
    setState(() => _syncingData = false);
    await _loadSyncStatus();
    if (!mounted) return;
    final message = result.success
        ? 'Synced ${result.totalRecords} record(s) to the cloud'
        : result.sessionExpired
            ? 'Your session expired — log out and log back in to resume cloud sync'
            : "Couldn't reach the server — will retry automatically";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          // The friendly message above is a guess at *why* sync failed —
          // showing the actual exception too is what makes a wrong guess
          // diagnosable instead of a dead end (see network_error.dart).
          if (result.error != null) ...[
            const SizedBox(height: 4),
            Text(
              '${result.error.runtimeType}: ${result.error}'
              '${result.errorDetail != null ? '\n${result.errorDetail}' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ],
      ),
      backgroundColor: result.success ? AppColors.success : AppColors.error,
    ));
  }

  String _syncSubtitle() {
    if (_syncingData) return 'Syncing…';
    if (_lastSyncedAt == null) return 'Never synced';
    final diff = DateTime.now().difference(_lastSyncedAt!);
    if (diff.inMinutes < 1) return 'Last synced: just now';
    if (diff.inMinutes < 60) return 'Last synced: ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last synced: ${diff.inHours}h ago';
    return 'Last synced: ${diff.inDays}d ago';
  }

  Future<void> _loadShop() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    setState(() => _shop = shop);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifsEnabled = prefs.getBool(_kNotifKey) ?? true;
    });
  }

  Future<void> _setNotifs(bool v) async {
    setState(() => _notifsEnabled = v);
    (await SharedPreferences.getInstance()).setBool(_kNotifKey, v);
  }

  Future<void> _logout() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.logout,
            style:
                TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(l10n.logoutConfirm,
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel,
                style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await performLogout(context);
    }
  }

  void _showThemePicker() {
    final current = ref.read(themeModeProvider);
    final c = context.colors;
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.chooseTheme,
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThemeOption(
                label: l10n.themeDark,
                icon: Icons.dark_mode_rounded,
                selected: current == ThemeMode.dark,
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
                  Navigator.pop(dialogCtx);
                }),
            _ThemeOption(
                label: l10n.themeLight,
                icon: Icons.light_mode_rounded,
                selected: current == ThemeMode.light,
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(ThemeMode.light);
                  Navigator.pop(dialogCtx);
                }),
            _ThemeOption(
                label: l10n.themeSystem,
                icon: Icons.brightness_auto_rounded,
                selected: current == ThemeMode.system,
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(ThemeMode.system);
                  Navigator.pop(dialogCtx);
                }),
          ],
        ),
      ),
    );
  }

  static String _languageDisplayName(String lang) =>
      lang == 'Hindi' ? 'हिन्दी' : 'English';

  void _showLanguagePicker() {
    final currentLang = ref.read(localeProvider.notifier).currentLanguage;
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.chooseLanguage,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold)),
        content: RadioGroup<String>(
          groupValue: currentLang,
          onChanged: (v) {
            if (v == null) return;
            ref.read(localeProvider.notifier).setLanguage(v);
            Navigator.pop(dialogCtx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _kLanguages.map((lang) {
              return RadioListTile<String>(
                value: lang,
                title: Text(_languageDisplayName(lang),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;

      final invoices = await getIt<InvoiceRepository>()
          .getInvoicesByShop(shopId, limit: 10000);

      final sb = StringBuffer();
      sb.writeln(
          'Invoice Number,Date,Customer,Payment Mode,Subtotal,GST,Discount,Grand Total,Status');

      for (final inv in invoices) {
        sb.writeln([
          inv.invoiceNumber,
          AppFormatters.formatDateTime(inv.createdAt),
          '"${inv.customerName}"',
          inv.paymentMode,
          inv.subtotal.toStringAsFixed(2),
          inv.gstAmount.toStringAsFixed(2),
          inv.discountAmount.toStringAsFixed(2),
          inv.grandTotal.toStringAsFixed(2),
          inv.status,
        ].join(','));
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/vaani_export.csv');
      await file.writeAsString(sb.toString());

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Vaani Billing Export',
          text: 'Exported ${invoices.length} invoices from Vaani',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.exportFailed('$e')),
        backgroundColor: context.colors.danger,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeLabel = ref.watch(themeModeProvider.notifier).label;
    final c = context.colors;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: const TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          if (_shop != null)
            GestureDetector(
              // go(), not push() — Settings lives outside the bottom-nav
              // shell (its own route, parentNavigatorKey: _rootKey), while
              // /profile is one of the shell's tabs. Pushing a shell route
              // from outside the shell tries to build a second instance of
              // the shell's Navigator with the same GlobalKey the one
              // already underneath is using, which crashes. go() replaces
              // the stack instead of layering on top of it, so it doesn't
              // collide — same reason every other tab switch in the app
              // already uses go() rather than push().
              onTap: () => context.go('/profile'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: isDark ? AppColors.cardGradient : null,
                  color: isDark ? null : c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color:
                            AppColors.primaryLight.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primaryLight, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          _shop!.name.isNotEmpty
                              ? _shop!.name[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_shop!.name,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          Text(_shop!.ownerName,
                              style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13)),
                          Text('+91 ${_shop!.phone}',
                              style: TextStyle(
                                  color: c.textHint, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: c.textSecondary),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Subscription
          _SettingsCard(children: [
            const _SectionHeader('Subscription'),
            _SettingsTile(
              icon: Icons.workspace_premium_rounded,
              title: ref.watch(subscriptionProvider)?.planName ?? 'Free trial',
              subtitle: ref.watch(subscriptionProvider)?.subscriptionStatus ?? 'Checking status…',
              onTap: () => context.push('/settings/subscription'),
            ),
          ]),

          const SizedBox(height: 12),

          // Business
          _SettingsCard(children: [
            _SectionHeader(l10n.business),
            _SettingsTile(
              icon: Icons.receipt_long_rounded,
              title: l10n.gstTaxes,
              subtitle: l10n.configureTaxHint,
              onTap: () =>
                  context.push('/profile/edit').then((_) => _loadShop()),
            ),
            _SettingsTile(
              icon: Icons.store_rounded,
              title: l10n.shopDetails,
              subtitle: l10n.updateShopHint,
              onTap: () =>
                  context.push('/profile/edit').then((_) => _loadShop()),
            ),
          ]),

          const SizedBox(height: 12),

          // Data
          _SettingsCard(children: [
            _SectionHeader(l10n.data),
            _SettingsTile(
              icon: Icons.backup_rounded,
              title: l10n.backupRestore,
              subtitle: l10n.exportImportHint,
              onTap: () => context.push('/settings/backup'),
            ),
            _SettingsTile(
              icon: Icons.cloud_sync_rounded,
              title: 'Cloud Sync',
              subtitle: _syncSubtitle(),
              onTap: _syncingData ? () {} : _syncDataNow,
            ),
            ListTile(
              leading: _exporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight))
                  : const Icon(Icons.download_rounded,
                      color: AppColors.primaryLight, size: 22),
              title: Text(l10n.exportData,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(l10n.shareInvoicesCsv,
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: c.textSecondary, size: 20),
              onTap: _exportData,
              contentPadding: EdgeInsets.zero,
            ),
          ]),

          const SizedBox(height: 12),

          // Preferences
          _SettingsCard(children: [
            _SectionHeader(l10n.preferences),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_rounded,
                  color: AppColors.primaryLight, size: 22),
              title: Text(l10n.notifications,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(
                  _notifsEnabled ? l10n.enabled : l10n.disabled,
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12)),
              value: _notifsEnabled,
              onChanged: _setNotifs,
              activeThumbColor: AppColors.primaryLight,
              contentPadding: EdgeInsets.zero,
            ),
            _SettingsTile(
              icon: Icons.dark_mode_rounded,
              title: l10n.theme,
              subtitle: themeLabel == 'Light'
                  ? l10n.themeLight
                  : themeLabel == 'System'
                      ? l10n.themeSystem
                      : l10n.themeDark,
              onTap: _showThemePicker,
            ),
            _SettingsTile(
              icon: Icons.language_rounded,
              title: l10n.language,
              subtitle: _languageDisplayName(
                  ref.watch(localeProvider).languageCode == 'hi'
                      ? 'Hindi'
                      : 'English'),
              onTap: _showLanguagePicker,
            ),
          ]),

          const SizedBox(height: 12),

          // Account Actions
          _SettingsCard(children: [
            _SectionHeader(l10n.accountActions),
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: l10n.logout,
              color: c.danger,
              onTap: _logout,
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: Text(
              l10n.appFooter,
              style: TextStyle(color: c.textDisabled, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      leading:
          Icon(icon, color: selected ? AppColors.primaryLight : c.textHint),
      title: Text(label,
          style: TextStyle(
              color: selected ? AppColors.primaryLight : c.textPrimary,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal)),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded,
              color: AppColors.primaryLight)
          : null,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            color: context.colors.textSecondary,
            letterSpacing: 1,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final semantic = context.colors;
    final titleColor = color ?? semantic.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.primaryLight, size: 22),
      title: Text(title,
          style: TextStyle(
              color: titleColor, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(
                  color: semantic.textSecondary, fontSize: 12))
          : null,
      trailing: Icon(Icons.chevron_right_rounded,
          color:
              (color ?? semantic.textSecondary).withValues(alpha: 0.6),
          size: 20),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}
