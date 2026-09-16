class SubscriptionStatus {
  final String shopStatus;
  final String? subscriptionStatus;
  final String? planName;
  // The plan actually granting the current module set right now — the paid
  // subscription's plan if one is in force, otherwise the free Basic
  // fallback (or null if the shop is suspended/cancelled). Distinct from
  // [planName] above, which is billing history and can point at a plan
  // (e.g. an expired Pro) that isn't what's actually active.
  final String? effectivePlanName;
  final DateTime? endDate;
  final List<String> enabledModules;
  final DateTime fetchedAt;

  const SubscriptionStatus({
    required this.shopStatus,
    this.subscriptionStatus,
    this.planName,
    this.effectivePlanName,
    this.endDate,
    required this.enabledModules,
    required this.fetchedAt,
  });

  // Strict equality (not a "default to Basic" fallback) deliberately — when
  // the plan isn't known yet (fresh install, offline before the first
  // successful check-in), this should fail open like isModuleEnabled()
  // does, not preemptively block voice billing. The server-side check in
  // shop-voice.service.js is the real backstop regardless of what this says.
  bool get isOnBasicPlan => effectivePlanName == 'Basic';

  /// Parses the `data` object returned by `GET /api/shop/me/status`.
  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final subscription = json['subscription'] as Map<String, dynamic>?;
    return SubscriptionStatus(
      shopStatus: json['shopStatus'] as String? ?? 'TRIAL',
      subscriptionStatus: subscription?['status'] as String?,
      planName: subscription?['planName'] as String?,
      effectivePlanName: json['effectivePlanName'] as String?,
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
        'effectivePlanName': effectivePlanName,
        'endDate': endDate?.toIso8601String(),
        'enabledModules': enabledModules,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory SubscriptionStatus.fromCacheJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        shopStatus: json['shopStatus'] as String? ?? 'TRIAL',
        subscriptionStatus: json['subscriptionStatus'] as String?,
        planName: json['planName'] as String?,
        effectivePlanName: json['effectivePlanName'] as String?,
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
