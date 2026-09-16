/// A shop's claim to have paid for a plan via UPI — never itself proof of
/// payment, just a record awaiting admin verification. See the matching
/// PaymentClaim doc comment in the backend's schema.prisma for the full
/// reasoning: UPI has no server-verifiable callback for a plain VPA, so
/// nothing on the client can ever safely flip this to "paid" on its own.
class PaymentClaim {
  final String id;
  final String planId;
  final String planName;
  final double amount;
  final String reference;
  final String status; // PENDING | CONFIRMED | REJECTED
  final DateTime createdAt;

  const PaymentClaim({
    required this.id,
    required this.planId,
    required this.planName,
    required this.amount,
    required this.reference,
    required this.status,
    required this.createdAt,
  });

  bool get isPending => status == 'PENDING';

  factory PaymentClaim.fromJson(Map<String, dynamic> json) => PaymentClaim(
        id: json['id'] as String,
        planId: json['planId'] as String,
        planName: (json['plan'] as Map<String, dynamic>)['name'] as String,
        amount: (json['amount'] as num).toDouble(),
        reference: json['reference'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
