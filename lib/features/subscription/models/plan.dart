/// A subscribable plan, as returned by `GET /api/shop/plans`. Deliberately
/// data-driven rather than an enum of hardcoded plan names — adding a new
/// plan or moving a module between plans is a backend/seed change only,
/// nothing in the app needs to know plan names or module lists ahead of
/// time (see subscription_screen.dart, which just renders whatever this
/// list contains).
class Plan {
  final String id;
  final String name;
  final double price;
  final String billingCycle;
  final List<String> modules;

  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.billingCycle,
    required this.modules,
  });

  bool get isFree => price == 0;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        id: json['id'] as String,
        name: json['name'] as String,
        // Prisma serializes Decimal columns (this is @db.Decimal(10,2)) as
        // JSON strings, not numbers, so this needs to parse either shape
        // rather than a straight `as num` cast.
        price: num.parse(json['price'].toString()).toDouble(),
        billingCycle: json['billingCycle'] as String? ?? 'MONTHLY',
        modules: (json['modules'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}
