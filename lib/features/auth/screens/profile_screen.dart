import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/auth/logout_helper.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/shop.dart';
import '../repositories/shop_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Shop? _shop;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    setState(() {
      _shop = shop;
      _loading = false;
    });
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
                  padding: const EdgeInsets.all(20),
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
                    const SizedBox(height: 28),

                    // Address
                    if (_shop!.address != null && _shop!.address!.isNotEmpty) ...[
                      _InfoTile(
                        icon: Icons.location_on_rounded,
                        label: l10n.address,
                        value: _shop!.address!,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Account
                    _SectionLabel(l10n.account),
                    _ActionTile(
                      icon: Icons.edit_rounded,
                      label: l10n.editProfile,
                      onTap: () => context.push('/profile/edit').then((_) => _load()),
                    ),
                    const SizedBox(height: 8),
                    _ActionTile(
                      icon: Icons.phone_rounded,
                      label: l10n.changeMobileNumber,
                      onTap: () => context.push('/profile/change-phone').then((_) => _load()),
                    ),
                    const SizedBox(height: 20),

                    // App
                    _SectionLabel('APP'),
                    _ActionTile(
                      icon: Icons.receipt_long_rounded,
                      label: l10n.bills,
                      onTap: () => context.go('/bills'),
                    ),
                    const SizedBox(height: 8),
                    _ActionTile(
                      icon: Icons.print_rounded,
                      label: 'Printer Management',
                      onTap: () => context.push('/profile/printer'),
                    ),
                    const SizedBox(height: 8),
                    _ActionTile(
                      icon: Icons.settings_rounded,
                      label: l10n.settings,
                      onTap: () => context.push('/settings'),
                    ),
                    const SizedBox(height: 8),
                    _ActionTile(
                      icon: Icons.backup_rounded,
                      label: l10n.backupRestore,
                      onTap: () => context.push('/settings/backup'),
                    ),
                    const SizedBox(height: 20),

                    // Danger zone
                    _SectionLabel('ACCOUNT'),
                    _ActionTile(
                      icon: Icons.logout_rounded,
                      label: l10n.logout,
                      color: context.colors.danger,
                      onTap: _logout,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
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
      margin: const EdgeInsets.only(bottom: 8),
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

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color != null ? color!.withValues(alpha: 0.3) : cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? cs.primary, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right_rounded, color: c.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
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
