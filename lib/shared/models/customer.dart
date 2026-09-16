class Customer {
  final int? id;
  final int shopId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double totalPurchases;
  final int totalBills;
  final double totalOutstanding;
  final double advanceBalance;
  final DateTime? lastVisit;
  final String? imagePath;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Customer({
    this.id,
    required this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.totalPurchases = 0,
    this.totalBills = 0,
    this.totalOutstanding = 0,
    this.advanceBalance = 0,
    this.lastVisit,
    this.imagePath,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // deleted_at is deliberately excluded — see the matching note on
  // Product.toMap(). It's written only by CustomerRepository.upsertFromCloud().
  Map<String, dynamic> toMap() => {
        'id': id,
        'shop_id': shopId,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'total_purchases': totalPurchases,
        'total_bills': totalBills,
        'total_outstanding': totalOutstanding,
        'advance_balance': advanceBalance,
        'last_visit': lastVisit?.toIso8601String(),
        'image_path': imagePath,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as int?,
        shopId: map['shop_id'] as int,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        totalPurchases: (map['total_purchases'] as num?)?.toDouble() ?? 0,
        totalBills: map['total_bills'] as int? ?? 0,
        totalOutstanding: (map['total_outstanding'] as num?)?.toDouble() ?? 0,
        advanceBalance: (map['advance_balance'] as num?)?.toDouble() ?? 0,
        lastVisit: map['last_visit'] != null ? DateTime.parse(map['last_visit'] as String) : null,
        imagePath: map['image_path'] as String?,
        deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Customer copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    double? totalPurchases,
    int? totalBills,
    double? totalOutstanding,
    double? advanceBalance,
    DateTime? lastVisit,
    String? imagePath,
  }) =>
      Customer(
        id: id,
        shopId: shopId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        totalPurchases: totalPurchases ?? this.totalPurchases,
        totalBills: totalBills ?? this.totalBills,
        totalOutstanding: totalOutstanding ?? this.totalOutstanding,
        advanceBalance: advanceBalance ?? this.advanceBalance,
        lastVisit: lastVisit ?? this.lastVisit,
        imagePath: imagePath ?? this.imagePath,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
