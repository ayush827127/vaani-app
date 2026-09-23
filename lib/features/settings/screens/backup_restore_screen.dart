import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n_extensions.dart';

const _kLastBackupAtKey = 'last_local_backup_at';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isCreating = false;
  bool _isRestoring = false;
  DateTime? _lastBackupAt;

  @override
  void initState() {
    super.initState();
    _loadLastBackupTime();
  }

  Future<void> _loadLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackupAtKey);
    if (raw != null && mounted) {
      setState(() => _lastBackupAt = DateTime.tryParse(raw));
    }
  }

  // Backups are handed off via the share sheet (Drive, Files app, email,
  // WhatsApp, …) rather than written to app-private external storage —
  // storage under the app's own folder is wiped the moment the app is
  // uninstalled, defeating the entire point of a backup. Wherever the user
  // chooses to save it in the share sheet survives that.
  Future<void> _createBackup() async {
    setState(() => _isCreating = true);
    try {
      // Flush anything still sitting only in the WAL file into vaani.db
      // itself — otherwise a copy taken right after recent activity could
      // silently miss the most recent bills/payments.
      await DatabaseHelper.instance.checkpoint();

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(appDir.path, 'vaani.db');

      final now = DateTime.now();
      final fileName = 'Vaani_Backup_${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.db';

      final tempDir = await getTemporaryDirectory();
      final exportPath = p.join(tempDir.path, fileName);
      await File(dbPath).copy(exportPath);

      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(exportPath, mimeType: 'application/octet-stream')],
        subject: fileName,
      ));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastBackupAtKey, now.toIso8601String());
      if (mounted) setState(() => _lastBackupAt = now);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupCreated(fileName)), backgroundColor: context.colors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupFailed('$e')), backgroundColor: context.colors.danger),
        );
      }
    }
    if (mounted) setState(() => _isCreating = false);
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final pickedPath = result?.files.single.path;
    if (pickedPath == null || !mounted) return;

    final confirmed = await _confirmRestore();
    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);
    try {
      // Validate before touching the live database: open the picked file
      // read-only and check it actually has Vaani's schema, so a wrong file
      // fails loudly here instead of bricking the app's own database.
      final pickedDb = await openDatabase(pickedPath, readOnly: true);
      final tables = await pickedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'shops'");
      await pickedDb.close();
      if (tables.isEmpty) {
        throw Exception('This file is not a valid Vaani backup');
      }

      await DatabaseHelper.instance.close();

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(appDir.path, 'vaani.db');
      // Clear any leftover WAL/SHM sidecar files from the *current* database
      // — otherwise SQLite would try to replay them against the freshly
      // restored main file on next open.
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      }
      await File(pickedPath).copy(dbPath);

      // The restored data's state relative to the cloud is unknown — it
      // could be older (this backup predates some cloud-side edits) or
      // newer (it has local changes never pushed). Clearing both sync
      // cursors makes the next sync do a full push and a full pull instead
      // of comparing against cursors that describe a database that no
      // longer exists on this device; without this, anything the cloud
      // changed after the backup's timestamp would never come back down,
      // and any restored row older than the stale push cursor would never
      // go back up — a silent, permanent gap in both directions.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.keyLastFullSyncAt);
      await prefs.remove(AppConstants.keyLastPullSyncAt);

      if (mounted) await _showRestoredDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: context.colors.danger),
        );
      }
    }
    if (mounted) setState(() => _isRestoring = false);
  }

  Future<bool?> _confirmRestore() {
    final c = context.colors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Restore this backup?', style: TextStyle(color: c.textPrimary)),
        content: Text(
          'This replaces ALL current items, customers, bills and payments with '
          "what's in the selected backup file. Anything recorded since that backup "
          'was made will be lost. This cannot be undone.',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Restore', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _showRestoredDialog() {
    final c = context.colors;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Backup restored', style: TextStyle(color: c.textPrimary)),
        content: Text(
          'Close Vaani completely and reopen it to load the restored data — '
          "the app can't safely reload its database while running.",
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () => SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
            child: Text('Exit App Now', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.backupRestore),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Create backup
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.backup_rounded, color: AppColors.primaryLight, size: 24),
                    const SizedBox(width: 12),
                    Text(l10n.createBackup, style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Saves a copy of everything — items, customers, bills, payments — '
                  'then lets you choose where to keep it (Google Drive, Files, email, etc.). '
                  "Save it somewhere outside this app so it survives an uninstall.",
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                if (_lastBackupAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last backup: ${AppFormatters.formatDateTime(_lastBackupAt!)}',
                    style: TextStyle(color: c.textHint, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isCreating ? null : _createBackup,
                  icon: _isCreating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.backup_rounded, size: 18),
                  label: Text(_isCreating ? l10n.creating : l10n.createBackup),
                ),
              ],
            ),
          ),
          // Restore section
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.danger.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restore_rounded, color: c.danger, size: 24),
                    const SizedBox(width: 12),
                    Text(l10n.restore, style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.danger)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.restoreWarning,
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isRestoring ? null : _restoreBackup,
                  icon: _isRestoring
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: c.danger, strokeWidth: 2))
                      : Icon(Icons.folder_open_rounded, color: c.danger),
                  label: Text(_isRestoring ? 'Restoring…' : l10n.selectBackupFile, style: TextStyle(color: c.danger)),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: c.danger)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
