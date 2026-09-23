/// One image in an item's gallery — see the item_images table's own doc
/// comment in database_helper.dart for how this relates to the legacy
/// single image_path/image_url on Item itself (kept as a denormalized cache
/// of whichever ItemImage here has isPrimary=true).
class ItemImage {
  final int? id;
  final int itemId;
  final String? imagePath;
  final String? imageUrl;
  final int sortOrder;
  final bool isPrimary;
  final DateTime createdAt;

  const ItemImage({
    this.id,
    required this.itemId,
    this.imagePath,
    this.imageUrl,
    this.sortOrder = 0,
    this.isPrimary = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'item_id': itemId,
        'image_path': imagePath,
        'image_url': imageUrl,
        'sort_order': sortOrder,
        'is_primary': isPrimary ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory ItemImage.fromMap(Map<String, dynamic> map) => ItemImage(
        id: map['id'] as int?,
        itemId: map['item_id'] as int,
        imagePath: map['image_path'] as String?,
        imageUrl: map['image_url'] as String?,
        sortOrder: map['sort_order'] as int? ?? 0,
        isPrimary: (map['is_primary'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  ItemImage copyWith({
    String? imagePath,
    String? imageUrl,
    int? sortOrder,
    bool? isPrimary,
  }) =>
      ItemImage(
        id: id,
        itemId: itemId,
        imagePath: imagePath ?? this.imagePath,
        imageUrl: imageUrl ?? this.imageUrl,
        sortOrder: sortOrder ?? this.sortOrder,
        isPrimary: isPrimary ?? this.isPrimary,
        createdAt: createdAt,
      );
}
