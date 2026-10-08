/// Server-computed usage against a plan's resource cap — the `{used, limit,
/// unlimited}` shape shared by `GET /api/shop/subscription/voice-usage`,
/// `GET /api/shop/subscription/manual-invoice-usage`, and `GET
/// /api/shop/members/quota`. Reused for all three rather than one model per
/// metric, since the shape and meaning are identical: `limit` is only
/// meaningful when `unlimited` is false.
class UsageStat {
  final int used;
  final int? limit;
  final bool unlimited;

  const UsageStat({required this.used, this.limit, required this.unlimited});

  factory UsageStat.fromJson(Map<String, dynamic> json) => UsageStat(
        used: json['used'] as int,
        limit: json['limit'] as int?,
        unlimited: json['unlimited'] as bool? ?? true,
      );
}
