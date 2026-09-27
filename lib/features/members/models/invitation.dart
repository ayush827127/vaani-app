/// One row from GET /api/shop/invitations — pending invitations addressed
/// to the current user's own phone (see shop-members.service.js's
/// listMyInvitations()).
class Invitation {
  final String id;
  final String shopId;
  final String shopName;
  final String role;

  const Invitation({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.role,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        shopName: (json['shop'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        role: json['role'] as String,
      );
}

/// The enriched response from POST /api/shop/invitations/:id/accept — a
/// ShopUser membership row plus enough of the shop's own profile to create
/// a local Shop row from it directly (see acceptInvitation's doc comment
/// on the backend for why this device has no other way to learn it).
class AcceptedMembership {
  final String shopId;
  final String shopName;
  final String ownerName;
  final String? address;
  final String? gstNumber;
  final String currency;
  final bool gstEnabled;
  final double defaultGstRate;
  final String? upiId;

  const AcceptedMembership({
    required this.shopId,
    required this.shopName,
    required this.ownerName,
    required this.address,
    required this.gstNumber,
    required this.currency,
    required this.gstEnabled,
    required this.defaultGstRate,
    required this.upiId,
  });

  factory AcceptedMembership.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>;
    return AcceptedMembership(
      shopId: json['shopId'] as String,
      shopName: shop['name'] as String,
      ownerName: shop['ownerName'] as String,
      address: shop['address'] as String?,
      gstNumber: shop['gstNumber'] as String?,
      currency: shop['currency'] as String? ?? 'INR',
      gstEnabled: shop['gstEnabled'] as bool? ?? true,
      defaultGstRate: (shop['defaultGstRate'] as num?)?.toDouble() ?? 5.0,
      upiId: shop['upiId'] as String?,
    );
  }
}
