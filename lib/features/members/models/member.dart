/// One row from GET /api/shop/members — see shop-members.service.js's
/// listMembers() on the backend for the exact shape this mirrors.
class Member {
  final String shopUserId;
  final String? userId;
  final String name;
  final String phone;
  final String role;

  const Member({
    required this.shopUserId,
    required this.userId,
    required this.name,
    required this.phone,
    required this.role,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        shopUserId: json['shopUserId'] as String,
        userId: json['userId'] as String?,
        name: json['name'] as String,
        phone: json['phone'] as String,
        role: json['role'] as String,
      );
}
