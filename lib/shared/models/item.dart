/// PRODUCT: a physical good — inventory-tracked by default.
/// SERVICE: labour/work with nothing to stock — never inventory-tracked by
/// default. [Item.inventoryEnabled] (not this type) is what billing actually
/// gates stock validation/deduction on — see the note on that field.
enum ItemType {
  product,
  service;

  String get dbValue => this == ItemType.service ? 'SERVICE' : 'PRODUCT';

  static ItemType fromDbValue(String? value) =>
      value == 'SERVICE' ? ItemType.service : ItemType.product;
}

class Item {
  final int? id;
  final int shopId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? category;
  final double costPrice;
  final double sellingPrice;
  final double gstRate;
  final int stockQuantity;
  final int reorderLevel;
  final String? imagePath;
  final String? imageUrl;
  final ItemType itemType;
  // The actual authority billing checks before touching stock — independent
  // of [itemType] so a shop can, e.g., sell a physical item without tracking
  // its stock, or (less commonly) track stock for something typed as a
  // service. New items default this from their type (product→true,
  // service→false) but it's a real, separately-stored field, never inferred
  // from itemType at read time.
  final bool inventoryEnabled;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> aliases;

  const Item({
    this.id,
    required this.shopId,
    required this.name,
    this.sku,
    this.barcode,
    this.category,
    this.costPrice = 0,
    required this.sellingPrice,
    this.gstRate = 5.0,
    this.stockQuantity = 0,
    this.reorderLevel = 10,
    this.imagePath,
    this.imageUrl,
    this.itemType = ItemType.product,
    this.inventoryEnabled = true,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.aliases = const [],
  });

  // All three are meaningless (and default false) for a service — it never
  // carries stock, so it's neither "low", "out" nor "in stock", it simply
  // doesn't track stock at all.
  bool get isLowStock =>
      inventoryEnabled && stockQuantity <= reorderLevel && stockQuantity > 0;
  bool get isOutOfStock => inventoryEnabled && stockQuantity == 0;
  bool get isInStock => inventoryEnabled && stockQuantity > reorderLevel;

  /// image_url is deliberately excluded — it's a sync-managed field written
  /// only by ItemRepository.setImageUrl()/the image-change-detection in
  /// updateItem(), never by this general write path. Including it here
  /// would wipe the already-uploaded Cloudinary URL on every unrelated edit
  /// (e.g. changing the price), since callers never carry it forward.
  Map<String, dynamic> toMap() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'category': category,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'gst_rate': gstRate,
        'stock_quantity': stockQuantity,
        'reorder_level': reorderLevel,
        'image_path': imagePath,
        'item_type': itemType.dbValue,
        'inventory_enabled': inventoryEnabled ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Item.fromMap(Map<String, dynamic> map, {List<String> aliases = const []}) => Item(
        id: map['id'] as int?,
        shopId: map['shop_id'] as int,
        name: map['name'] as String,
        sku: map['sku'] as String?,
        barcode: map['barcode'] as String?,
        category: map['category'] as String?,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        sellingPrice: (map['selling_price'] as num).toDouble(),
        gstRate: (map['gst_rate'] as num?)?.toDouble() ?? 5.0,
        stockQuantity: map['stock_quantity'] as int? ?? 0,
        reorderLevel: map['reorder_level'] as int? ?? 10,
        imagePath: map['image_path'] as String?,
        imageUrl: map['image_url'] as String?,
        itemType: ItemType.fromDbValue(map['item_type'] as String?),
        inventoryEnabled: (map['inventory_enabled'] as int? ?? 1) == 1,
        isActive: (map['is_active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        aliases: aliases,
      );

  Item copyWith({
    int? id,
    String? name,
    String? sku,
    String? barcode,
    String? category,
    double? costPrice,
    double? sellingPrice,
    double? gstRate,
    int? stockQuantity,
    int? reorderLevel,
    String? imagePath,
    String? imageUrl,
    ItemType? itemType,
    bool? inventoryEnabled,
    bool? isActive,
    List<String>? aliases,
  }) =>
      Item(
        id: id ?? this.id,
        shopId: shopId,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        barcode: barcode ?? this.barcode,
        category: category ?? this.category,
        costPrice: costPrice ?? this.costPrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        gstRate: gstRate ?? this.gstRate,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        imagePath: imagePath ?? this.imagePath,
        imageUrl: imageUrl ?? this.imageUrl,
        itemType: itemType ?? this.itemType,
        inventoryEnabled: inventoryEnabled ?? this.inventoryEnabled,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        aliases: aliases ?? this.aliases,
      );
}
