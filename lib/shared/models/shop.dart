class Shop {
  final int? id;
  final String name;
  final String ownerName;
  final String phone;
  final String? gstNumber;
  final String? address;
  final String? logoPath;
  final String? logoUrl;
  final String? upiId;
  final String currency;
  final bool gstEnabled;
  final double defaultGstRate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Shop({
    this.id,
    required this.name,
    required this.ownerName,
    required this.phone,
    this.gstNumber,
    this.address,
    this.logoPath,
    this.logoUrl,
    this.upiId,
    this.currency = 'INR',
    this.gstEnabled = true,
    this.defaultGstRate = 5.0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// logo_url is deliberately excluded — see the matching note on
  /// Product.toMap(). It's written only by ShopRepository.setLogoUrl()/the
  /// logo-change-detection in updateShop().
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'owner_name': ownerName,
        'phone': phone,
        'gst_number': gstNumber,
        'address': address,
        'logo_path': logoPath,
        'upi_id': upiId,
        'currency': currency,
        'gst_enabled': gstEnabled ? 1 : 0,
        'default_gst_rate': defaultGstRate,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Shop.fromMap(Map<String, dynamic> map) => Shop(
        id: map['id'] as int?,
        name: map['name'] as String,
        ownerName: map['owner_name'] as String,
        phone: map['phone'] as String,
        gstNumber: map['gst_number'] as String?,
        address: map['address'] as String?,
        logoPath: map['logo_path'] as String?,
        logoUrl: map['logo_url'] as String?,
        upiId: map['upi_id'] as String?,
        currency: map['currency'] as String? ?? 'INR',
        gstEnabled: (map['gst_enabled'] as int? ?? 1) == 1,
        defaultGstRate: (map['default_gst_rate'] as num?)?.toDouble() ?? 5.0,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Shop copyWith({
    int? id,
    String? name,
    String? ownerName,
    String? phone,
    String? gstNumber,
    String? address,
    String? logoPath,
    String? logoUrl,
    String? upiId,
    String? currency,
    bool? gstEnabled,
    double? defaultGstRate,
  }) =>
      Shop(
        id: id ?? this.id,
        name: name ?? this.name,
        ownerName: ownerName ?? this.ownerName,
        phone: phone ?? this.phone,
        gstNumber: gstNumber ?? this.gstNumber,
        address: address ?? this.address,
        logoPath: logoPath ?? this.logoPath,
        logoUrl: logoUrl ?? this.logoUrl,
        upiId: upiId ?? this.upiId,
        currency: currency ?? this.currency,
        gstEnabled: gstEnabled ?? this.gstEnabled,
        defaultGstRate: defaultGstRate ?? this.defaultGstRate,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
