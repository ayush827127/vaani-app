import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/db/database_helper.dart';
import '../../../shared/models/notification_item.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('notifications', orderBy: 'created_at DESC', limit: 50);
    setState(() {
      _notifications = rows.map(NotificationItem.fromMap).toList();
      _isLoading = false;
    });
  }

  Future<void> _markAllRead() async {
    final db = await DatabaseHelper.instance.database;
    await db.update('notifications', {'is_read': 1});
    _load();
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'low_stock': return Icons.warning_amber_rounded;
      case 'milestone': return Icons.celebration_rounded;
      case 'record': return Icons.emoji_events_rounded;
      case 'update': return Icons.inventory_2_rounded;
      case 'daily_summary': return Icons.bar_chart_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getColor(String type, AppSemanticColors c) {
    switch (type) {
      case 'low_stock': return c.warning;
      case 'milestone': return c.success;
      case 'record': return c.info;
      case 'update': return AppColors.primaryLight;
      default: return c.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () => context.pop()),
        actions: [
          if (_notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: AppColors.primaryLight, fontSize: 12)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 64, color: c.textSecondary),
                      const SizedBox(height: 16),
                      Text('No notifications', style: TextStyle(color: c.textSecondary)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final n = _notifications[i];
                    final typeColor = _getColor(n.type, c);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: n.isRead ? c.surface : AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: n.isRead ? c.surfaceBorder : AppColors.primaryLight.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getIcon(n.type), size: 20, color: typeColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(n.message, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(AppFormatters.formatDateTime(n.createdAt),
                                    style: TextStyle(color: c.textHint, fontSize: 11)),
                              ],
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
