class NotificationItem {
  final int? id;
  final String type;
  final String title;
  final String message;
  final int? referenceId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationItem({
    this.id,
    required this.type,
    required this.title,
    required this.message,
    this.referenceId,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'title': title,
        'message': message,
        'reference_id': referenceId,
        'is_read': isRead ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory NotificationItem.fromMap(Map<String, dynamic> map) => NotificationItem(
        id: map['id'] as int?,
        type: map['type'] as String,
        title: map['title'] as String,
        message: map['message'] as String,
        referenceId: map['reference_id'] as int?,
        isRead: (map['is_read'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
        id: id,
        type: type,
        title: title,
        message: message,
        referenceId: referenceId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}
