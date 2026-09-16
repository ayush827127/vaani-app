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
import '../../../core/auth/logout_helper.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/shop.dart';
import '../repositories/shop_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../settings/providers/theme_provider.dart';
import '../../settings/providers/locale_provider.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../../../l10n/l10n_extensions.dart';

const _kNotifKey = 'notif_enabled';
const _kLanguages = ['English', 'Hindi'];

/// Profile + Settings combined — there used to be a separate Settings screen
/// reachable from here and from the drawer/home quick actions; it's gone now
/// and everything it had (Subscription, Cloud Sync, Export Data,
/// Preferences) lives directly on this screen instead, so there's one place
/// for account/shop/app configuration rather than two overlapping ones.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Shop? _shop;
  bool _loading = true;

  bool _notifsEnabled = true;
  bool _exporting = false;
  DateTime? _lastSyncedAt;
  bool _syncingData = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrefs();
    _loadSyncStatus();
  }

  Future<void> _load() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    setState(() {
      _shop = shop;
      _loading = false;
    });
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

  void _showThemePicker() {
    final current = ref.read(themeModeProvider);
    final c = context.colors;
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  Future<void> _logout() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.logout, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          l10n.logoutConfirmLong,
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await performLogout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final themeLabel = ref.watch(themeModeProvider.notifier).label;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(l10n.myProfile, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (_shop != null)
            TextButton(
              onPressed: () => context.push('/profile/edit').then((_) => _load()),
              child: Text(l10n.edit, style: const TextStyle(color: AppColors.primaryLight, fontSize: 15)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _shop == null
              ? Center(child: Text(l10n.noProfileFound, style: TextStyle(color: context.colors.textSecondary)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Avatar
                    Center(
                      child: _ShopAvatar(shop: _shop!, size: 90, fontSize: 36),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _shop!.name,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        _shop!.ownerName,
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_shop!.address != null && _shop!.address!.isNotEmpty) ...[
                      _InfoTile(
                        icon: Icons.location_on_rounded,
                        label: l10n.address,
                        value: _shop!.address!,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Account
                    _SettingsCard(children: [
                      _SectionHeader(l10n.account),
                      _SettingsTile(
                        icon: Icons.edit_rounded,
                        title: l10n.editProfile,
                        onTap: () => context.push('/profile/edit').then((_) => _load()),
                      ),
                      _SettingsTile(
                        icon: Icons.phone_rounded,
                        title: l10n.changeMobileNumber,
                        onTap: () => context.push('/profile/change-phone').then((_) => _load()),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // Subscription
                    _SettingsCard(children: [
                      const _SectionHeader('Subscription'),
                      _SettingsTile(
                        icon: Icons.workspace_premium_rounded,
                        title: ref.watch(subscriptionProvider)?.planName ?? 'Free trial',
                        subtitle: ref.watch(subscriptionProvider)?.subscriptionStatus ?? 'Checking status…',
                        onTap: () => context.push('/profile/subscription'),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // App
                    _SettingsCard(children: [
                      _SectionHeader('App'),
                      _SettingsTile(
                        icon: Icons.receipt_long_rounded,
                        title: l10n.bills,
                        onTap: () => context.go('/bills'),
                      ),
                      _SettingsTile(
                        icon: Icons.print_rounded,
                        title: 'Printer Management',
                        onTap: () => context.push('/profile/printer'),
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
                        onTap: () => context.push('/profile/backup'),
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
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

class _ShopAvatar extends StatelessWidget {
  final Shop shop;
  final double size;
  final double fontSize;
  const _ShopAvatar({required this.shop, required this.size, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final path = shop.logoPath ?? '';
    final hasFile = path.isNotEmpty && File(path).existsSync();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: hasFile ? null : context.colors.heroGradient,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryLight, width: 2),
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(File(path), fit: BoxFit.cover, width: size, height: size,
                errorBuilder: (_, __, ___) => _initial())
            : _initial(),
      ),
    );
  }

  Widget _initial() => Center(
        child: Text(
          shop.name.isNotEmpty ? shop.name[0].toUpperCase() : 'S',
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryLight),
        ),
      );
}
