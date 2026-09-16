import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/injector.dart';
import '../utils/constants.dart';
import '../../features/sync/repositories/data_sync_repository.dart';

/// Shared "sync then clear session" logout sequence — call after the caller
/// has already shown its own confirmation dialog. All three logout entry
/// points (Settings, drawer, Profile) call this so they can't drift out of
/// sync with each other again.
///
/// Shows a brief "Syncing…" dialog while a final sync runs, bounded by
/// [syncTimeout] and skippable — logout must never be a dead end just
/// because the shop is offline (nothing pushed is lost; it syncs next login).
Future<void> performLogout(
  BuildContext context, {
  Duration syncTimeout = const Duration(seconds: 10),
}) async {
  final skipped = Completer<void>();
  final dialogShown = context.mounted;

  if (dialogShown) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            const Expanded(child: Text('Syncing before logout…')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (!skipped.isCompleted) skipped.complete();
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  // Data safety over speed at a deliberate logout — worth a short wait, but
  // bounded by a timeout and a visible Skip action so an offline shop is
  // never stuck here. The sync itself keeps running in the background if it
  // loses this race; that's fine, it just finishes after logout completes.
  await Future.any([
    getIt<DataSyncRepository>().syncNow(),
    Future.delayed(syncTimeout),
    skipped.future,
  ]);

  if (dialogShown && context.mounted) {
    Navigator.of(context).pop(); // dismiss the syncing dialog
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(AppConstants.keyIsLoggedIn, false);
  await prefs.setBool(AppConstants.keyIsSetupComplete, false);
  await prefs.remove(AppConstants.keyShopPhone);
  await prefs.remove(AppConstants.keyShopId);
  await prefs.remove(AppConstants.keyIsDemoMode);
  // Full session-scoped clear — without this, setting up a *different* shop
  // later on this device could reuse this account's backend token or cached
  // subscription status, and worse, its stale pull cursor: the next shop's
  // first pull would silently skip any cloud data older than this account's
  // last successful sync.
  await prefs.remove(AppConstants.keyShopBackendToken);
  await prefs.remove(AppConstants.keySubscriptionStatusJson);
  await prefs.remove(AppConstants.keyLastFullSyncAt);
  await prefs.remove(AppConstants.keyLastPullSyncAt);

  if (context.mounted) context.go('/login');
}
