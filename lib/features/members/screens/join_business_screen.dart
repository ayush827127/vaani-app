import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/shop.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../models/invitation.dart';
import '../repositories/member_repository.dart';

/// Shown instead of ShopSetupScreen when a brand-new phone (no local shop,
/// no legacy cloud shop) turns out to have one or more pending invitations
/// — see login_screen.dart's "no local shop, no cloud shop" branch. [phone]
/// and [otpToken] are only needed for the "create instead" escape hatch,
/// which mirrors that branch's own existing behavior exactly.
class JoinBusinessScreen extends StatefulWidget {
  final String phone;
  final String otpToken;
  const JoinBusinessScreen({super.key, required this.phone, required this.otpToken});

  @override
  State<JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends State<JoinBusinessScreen> {
  bool _loading = true;
  List<Invitation> _invitations = [];
  String? _actingOnId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invitations = await getIt<MemberRepository>().listMyInvitations();
      if (!mounted) return;
      setState(() {
        _invitations = invitations;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createInstead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyPendingOtpToken, widget.otpToken);
    if (!mounted) return;
    context.go('/setup');
  }

  Future<void> _accept(Invitation invitation) async {
    setState(() => _actingOnId = invitation.id);
    final memberRepo = getIt<MemberRepository>();
    try {
      final accepted = await memberRepo.acceptInvitation(invitation.id);
      await memberRepo.selectShopAndRefresh(accepted.shopId);

      final now = DateTime.now();
      final shop = Shop(
        name: accepted.shopName,
        ownerName: accepted.ownerName,
        phone: widget.phone,
        gstNumber: accepted.gstNumber,
        address: accepted.address,
        upiId: accepted.upiId,
        currency: accepted.currency,
        gstEnabled: accepted.gstEnabled,
        defaultGstRate: accepted.defaultGstRate,
        createdAt: now,
        updatedAt: now,
      );
      final shopId = await getIt<ShopRepository>().createShop(shop);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);
      await prefs.setBool(AppConstants.keyIsSetupComplete, true);
      await prefs.setString(AppConstants.keyShopPhone, widget.phone);
      await prefs.setInt(AppConstants.keyShopId, shopId);

      // Await (don't fire-and-forget), same reasoning as the "returning
      // shop, new device" branch in login_screen.dart — this is what
      // actually pulls the shop's data down, so the user shouldn't land on
      // an empty dashboard while it happens invisibly in the background.
      final syncResult = await getIt<DataSyncRepository>().syncNow();
      if (!mounted) return;
      if (!syncResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.joinedSyncPending)),
        );
      }
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingOnId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _reject(Invitation invitation) async {
    setState(() => _actingOnId = invitation.id);
    try {
      await getIt<MemberRepository>().rejectInvitation(invitation.id);
      if (!mounted) return;
      setState(() {
        _invitations = _invitations.where((i) => i.id != invitation.id).toList();
        _actingOnId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingOnId = null);
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
      appBar: AppBar(title: Text(l10n.joinBusinessTitle), automaticallyImplyLeading: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_invitations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(l10n.noInvitationsFound,
                          textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
                    )
                  else
                    ..._invitations.map((invitation) => Card(
                          color: c.surface,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(invitation.shopName,
                                    style: TextStyle(
                                        color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(l10n.roleValue(invitation.role), style: TextStyle(color: c.textSecondary)),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _actingOnId == null ? () => _reject(invitation) : null,
                                        child: Text(l10n.reject),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _actingOnId == null ? () => _accept(invitation) : null,
                                        child: _actingOnId == invitation.id
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2, color: Colors.white))
                                            : Text(l10n.join),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _actingOnId == null ? _createInstead : null,
                    child: Text(l10n.createBusinessInstead),
                  ),
                ],
              ),
            ),
    );
  }
}
