import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/shop.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../sync/repositories/data_sync_repository.dart';

/// Creates the local Shop row for a business this device has just joined or
/// selected, then does exactly what every other "this shop's data is
/// landing on this device for the first time" path already does: marks
/// logged in/setup complete, pulls everything else down, and goes home.
/// Extracted from JoinBusinessScreen's original `_accept` so
/// SelectBusinessScreen (picking among 2+ existing memberships) can share
/// the exact same tail sequence instead of it drifting between the two.
Future<void> completeShopJoin(
  BuildContext context, {
  required Shop shop,
  required String phone,
}) async {
  final shopId = await getIt<ShopRepository>().createShop(shop);

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(AppConstants.keyIsLoggedIn, true);
  await prefs.setBool(AppConstants.keyIsSetupComplete, true);
  await prefs.setString(AppConstants.keyShopPhone, phone);
  await prefs.setInt(AppConstants.keyShopId, shopId);

  // Await (don't fire-and-forget) — this is what actually pulls the shop's
  // data down, so the user shouldn't land on an empty dashboard while it
  // happens invisibly in the background.
  final syncResult = await getIt<DataSyncRepository>().syncNow();
  if (!context.mounted) return;
  if (!syncResult.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.joinedSyncPending)),
    );
  }
  context.go('/home');
}
