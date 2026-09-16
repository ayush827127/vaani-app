/// Server-computed voice-invoice usage, from `GET
/// /api/shop/subscription/voice-usage` — see that endpoint's doc comment
/// for why the count comes from the server rather than the phone.
class VoiceUsage {
  final int used;
  final int? limit;
  final bool unlimited;

  const VoiceUsage({required this.used, this.limit, required this.unlimited});

  factory VoiceUsage.fromJson(Map<String, dynamic> json) => VoiceUsage(
        used: json['used'] as int,
        limit: json['limit'] as int?,
        unlimited: json['unlimited'] as bool? ?? true,
      );
}
