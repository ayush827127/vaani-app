import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/injector.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/shop.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../models/membership.dart';
import '../repositories/member_repository.dart';
import '../utils/complete_shop_join.dart';

/// Shown instead of ShopSetupScreen/JoinBusinessScreen when login reports
/// 2+ active memberships for this phone — see login_screen.dart's "no local
/// shop, no cloud shop" branch. Picking one gets a fresh token carrying that
/// shopId (MemberRepository.selectShopAndRefresh), pulls the shop's profile
/// directly (DataSyncRepository.fetchShopProfile — syncNow() can't be used
/// yet, since it requires a local Shop row to already exist), creates the
/// local Shop row, and reuses JoinBusinessScreen's exact tail sequence via
/// completeShopJoin so the two paths can't drift apart.
class SelectBusinessScreen extends StatefulWidget {
  final String phone;
  final List<Membership> memberships;
  const SelectBusinessScreen({super.key, required this.phone, required this.memberships});

  @override
  State<SelectBusinessScreen> createState() => _SelectBusinessScreenState();
}

class _SelectBusinessScreenState extends State<SelectBusinessScreen> {
  String? _actingOnShopId;

  Future<void> _select(Membership membership) async {
    setState(() => _actingOnShopId = membership.shopId);
    try {
      final memberRepo = getIt<MemberRepository>();
      await memberRepo.selectShopAndRefresh(membership.shopId);

      final profile = await getIt<DataSyncRepository>().fetchShopProfile();
      if (profile == null) {
        throw Exception("Couldn't load this business's details — please try again.");
      }

      final now = DateTime.now();
      final updatedAt = DateTime.tryParse(profile['updatedAt'] as String? ?? '') ?? now;
      final shop = Shop(
        name: profile['name'] as String,
        ownerName: profile['ownerName'] as String,
        phone: widget.phone,
        gstNumber: profile['gstNumber'] as String?,
        address: profile['address'] as String?,
        upiId: profile['upiId'] as String?,
        currency: profile['currency'] as String? ?? 'INR',
        gstEnabled: profile['gstEnabled'] as bool? ?? true,
        defaultGstRate: (profile['defaultGstRate'] as num?)?.toDouble() ?? 5.0,
        logoUrl: profile['logoUrl'] as String?,
        createdAt: now,
        updatedAt: updatedAt,
      );
      if (!mounted) return;
      await completeShopJoin(context, shop: shop, phone: widget.phone);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingOnShopId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.selectBusinessTitle), automaticallyImplyLeading: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l10n.selectBusinessSubtitle, style: TextStyle(color: c.textSecondary)),
            ),
            ...widget.memberships.map((m) => Card(
                  color: c.surface,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(m.shopName,
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(l10n.roleValue(m.role), style: TextStyle(color: c.textSecondary)),
                    trailing: _actingOnShopId == m.shopId
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _actingOnShopId == null ? () => _select(m) : null,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
