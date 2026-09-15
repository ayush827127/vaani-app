class SubscriptionStatus {
  final String shopStatus;
  final String? subscriptionStatus;
  final String? planName;
  final DateTime? endDate;
  final List<String> enabledModules;
  final DateTime fetchedAt;

  const SubscriptionStatus({
    required this.shopStatus,
    this.subscriptionStatus,
    this.planName,
    this.endDate,
    required this.enabledModules,
    required this.fetchedAt,
  });

  /// Parses the `data` object returned by `GET /api/shop/me/status`.
  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final subscription = json['subscription'] as Map<String, dynamic>?;
    return SubscriptionStatus(
      shopStatus: json['shopStatus'] as String? ?? 'TRIAL',
      subscriptionStatus: subscription?['status'] as String?,
      planName: subscription?['planName'] as String?,
      endDate: subscription?['endDate'] != null
          ? DateTime.tryParse(subscription!['endDate'] as String)
          : null,
      enabledModules:
          (json['modules'] as List?)?.map((e) => e.toString()).toList() ?? [],
      fetchedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'shopStatus': shopStatus,
        'subscriptionStatus': subscriptionStatus,
        'planName': planName,
        'endDate': endDate?.toIso8601String(),
        'enabledModules': enabledModules,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory SubscriptionStatus.fromCacheJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        shopStatus: json['shopStatus'] as String? ?? 'TRIAL',
        subscriptionStatus: json['subscriptionStatus'] as String?,
        planName: json['planName'] as String?,
        endDate: json['endDate'] != null
            ? DateTime.tryParse(json['endDate'] as String)
            : null,
        enabledModules: (json['enabledModules'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        fetchedAt:
            DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}
