/// One entry from POST /api/user/auth/login's `memberships` list — every
/// ACTIVE shop this phone's User account currently belongs to (see
/// user-auth.service.js's membershipView()).
class Membership {
  final String shopId;
  final String shopName;
  final String role;
  final String status;

  const Membership({
    required this.shopId,
    required this.shopName,
    required this.role,
    required this.status,
  });

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        shopId: json['shopId'] as String,
        shopName: json['shopName'] as String,
        role: json['role'] as String,
        status: json['status'] as String,
      );
}
