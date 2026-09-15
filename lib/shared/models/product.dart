class Product {
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
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> aliases;

  const Product({
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
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.aliases = const [],
  });

  bool get isLowStock => stockQuantity <= reorderLevel && stockQuantity > 0;
  bool get isOutOfStock => stockQuantity == 0;
  bool get isInStock => stockQuantity > reorderLevel;

  /// image_url is deliberately excluded — it's a sync-managed field written
  /// only by ProductRepository.setImageUrl()/the image-change-detection in
  /// updateProduct(), never by this general write path. Including it here
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
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> map, {List<String> aliases = const []}) => Product(
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
        isActive: (map['is_active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        aliases: aliases,
      );

  Product copyWith({
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
    bool? isActive,
    List<String>? aliases,
  }) =>
      Product(
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
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        aliases: aliases ?? this.aliases,
      );
}
