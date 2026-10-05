import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles runtime permissions (camera, microphone) with a single ask-once
/// pattern.  Android caches a granted permission — once the user taps
/// "Allow", this function returns true immediately on every future call
/// without showing any dialog.
class PermissionService {
  static Future<bool> requestCamera(BuildContext context) => _request(
        context,
        Permission.camera,
        'Camera Permission Required',
        'Camera access is needed to scan barcodes and QR codes.',
      );

  static Future<bool> requestMicrophone(BuildContext context) => _request(
        context,
        Permission.microphone,
        'Microphone Permission Required',
        'Microphone access is needed for voice billing.',
      );

  // The contact *picker* itself (openExternalPick) needs no permission —
  // the OS Contacts app does the picking. But flutter_contacts then fetches
  // that one contact's details with a direct ContentResolver query on a
  // background thread with no permission check of its own, which throws an
  // uncaught SecurityException (crashing the app, not a catchable Dart
  // exception) if this isn't granted. Must be requested before calling
  // openExternalPick, not after.
  static Future<bool> requestContacts(BuildContext context) => _request(
        context,
        Permission.contacts,
        'Contacts Permission Required',
        'Contacts access is needed to pick a customer from your saved phone contacts.',
      );

  static Future<bool> _request(
    BuildContext context,
    Permission permission,
    String title,
    String reason,
  ) async {
    var status = await permission.status;

    // Already granted — return immediately, no dialog.
    if (status.isGranted) return true;

    // User clicked "Never ask again" — guide them to Settings.
    if (status.isPermanentlyDenied) {
      if (context.mounted) _showSettingsDialog(context, title, reason);
      return false;
    }

    // First time or "Denied once" — show the system dialog.
    status = await permission.request();
    if (status.isGranted) return true;

    // User clicked "Never ask again" after this prompt.
    if (status.isPermanentlyDenied && context.mounted) {
      _showSettingsDialog(context, title, reason);
    }
    return false;
  }

  static void _showSettingsDialog(
      BuildContext context, String title, String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          '$reason\n\nPlease enable it from:\nApp Settings → Permissions.',
          style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.75),
              height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Not Now',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
