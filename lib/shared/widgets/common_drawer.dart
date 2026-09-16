import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/auth/logout_helper.dart';
import '../../core/di/injector.dart';
import '../../features/auth/repositories/shop_repository.dart';
import '../../l10n/l10n_extensions.dart';

/// Single reusable navigation drawer used by every screen.
/// Loads its own shop data. Fully theme-aware — works in both Light and Dark.
class CommonDrawer extends StatefulWidget {
  const CommonDrawer({super.key});

  @override
  State<CommonDrawer> createState() => _CommonDrawerState();
}

class _CommonDrawerState extends State<CommonDrawer> {
  String _shopName = '';
  String _ownerName = '';
  String? _logoPath;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    setState(() {
      _shopName = shop?.name ?? '';
      _ownerName = shop?.ownerName ?? '';
      _logoPath = shop?.logoPath;
      _phone = shop?.phone;
    });
  }

  Future<void> _logout(BuildContext ctx) async {
    final l10n = ctx.l10n;
    final cs = Theme.of(ctx).colorScheme;

    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.logout,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
        content: Text(l10n.logoutConfirm,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l10n.cancel,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: ctx.colors.danger,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      await performLogout(ctx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPath = GoRouterState.of(context).uri.path;

    final initial =
        _ownerName.isNotEmpty ? _ownerName[0].toUpperCase() : (_shopName.isNotEmpty ? _shopName[0].toUpperCase() : 'V');

    return Drawer(
      backgroundColor: cs.surface,
      child: Column(
        children: [
          // ── Gradient Header ──────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF4C1D95), Color(0xFF6B21A8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : AppColors.heroGradientLight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(logoPath: _logoPath, initial: initial, size: 60),
                const SizedBox(height: 12),
                Text(
                  _shopName.isNotEmpty ? _shopName : l10n.myShopFallback,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 2),
                Text(
                  _ownerName.isNotEmpty ? _ownerName : '',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                if (_phone != null && _phone!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+91 $_phone',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),

          // ── Nav Items ────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavTile(
                  icon: Icons.home_rounded,
                  label: l10n.home,
                  route: '/home',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/home'); },
                ),
                _NavTile(
                  icon: Icons.receipt_long_rounded,
                  label: l10n.billing,
                  route: '/billing',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/billing'); },
                ),
                _NavTile(
                  icon: Icons.inventory_2_rounded,
                  label: l10n.products,
                  route: '/inventory',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/inventory'); },
                ),
                _NavTile(
                  icon: Icons.people_rounded,
                  label: l10n.customers,
                  route: '/customers',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/customers'); },
                ),
                _NavTile(
                  icon: Icons.receipt_outlined,
                  label: l10n.bills,
                  route: '/bills',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/bills'); },
                ),
                _NavTile(
                  icon: Icons.bar_chart_rounded,
                  label: l10n.reports,
                  route: '/reports',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/reports'); },
                ),
                _NavTile(
                  icon: Icons.smart_toy_rounded,
                  label: l10n.aiManager,
                  route: '/ai-manager',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/ai-manager'); },
                ),
                Divider(color: cs.outlineVariant, indent: 16, endIndent: 16, height: 24),
                _NavTile(
                  icon: Icons.person_rounded,
                  label: l10n.profile,
                  route: '/profile',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.go('/profile'); },
                ),
                _NavTile(
                  icon: Icons.settings_rounded,
                  label: l10n.settings,
                  route: '/settings',
                  current: currentPath,
                  onTap: () { Navigator.pop(context); context.push('/settings'); },
                ),
                _NavTile(
                  icon: Icons.help_outline_rounded,
                  label: l10n.help,
                  route: '/help',
                  current: currentPath,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.helpComingSoon)),
                    );
                  },
                ),
                Divider(color: cs.outlineVariant, indent: 16, endIndent: 16, height: 24),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: cs.error, size: 22),
                  title: Text(
                    l10n.logout,
                    style: TextStyle(
                        color: cs.error, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  onTap: () => _logout(context),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ],
            ),
          ),

          // ── Footer ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${l10n.appName} — ${l10n.aiStoreManagerTagline}',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.25), fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drawer Nav Tile ────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String current;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.route,
    required this.current,
    required this.onTap,
  });

  bool get _active => current == route || current.startsWith('$route/');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: _active ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: _active ? cs.primary : cs.onSurface,
          fontSize: 14,
          fontWeight: _active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      tileColor: _active ? cs.primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

// ── Avatar ─────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? logoPath;
  final String initial;
  final double size;

  const _Avatar({required this.logoPath, required this.initial, required this.size});

  @override
  Widget build(BuildContext context) {
    final hasFile = logoPath != null &&
        logoPath!.isNotEmpty &&
        File(logoPath!).existsSync();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white54, width: 2),
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(File(logoPath!),
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _letter())
            : _letter(),
      ),
    );
  }

  Widget _letter() => Center(
        child: Text(
          initial,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
      );
}
