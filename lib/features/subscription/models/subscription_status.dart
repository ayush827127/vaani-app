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
  // Resource caps in force right now, straight from the backend's Plan row
  // — null means unlimited. Read directly by the local, offline-first
  // pre-check in payment_bottom_sheet.dart (invoiceMonthlyLimit) and
  // manage_members_screen.dart (staffLimit) instead of a hardcoded
  // constant, so a cap changed via the admin panel takes effect without an
  // app release. The backend remains the authoritative enforcement point
  // for the voice-billing path and staff invites (see invoiceQuota.js /
  // shop-members.service.js) — these cached numbers can go briefly stale
  // between check-ins, same as enabledModules above.
  //
  // invoiceMonthlyLimit counts voice- and manually-created invoices
  // TOGETHER against one combined monthly quota (previously two separate
  // fields here — a lifetime voice cap and a monthly manual cap).
  final int? invoiceMonthlyLimit;
  final int? staffLimit;
  // Whether this shop has ever started its one-time 14-day Pro trial —
  // permanent once true, drives the "Start Trial" CTA's visibility
  // alongside trialAvailable.
  final bool trialUsed;
  // Whether tapping "Start Trial" right now would actually succeed —
  // mirrors the backend's trial.service.js canStartTrial exactly (not
  // simply !trialUsed: an in-force paid Pro subscription or an in-force
  // trial also block it). A null/stale cached value fails closed here
  // (defaults to false via the JSON parse below) rather than open, since
  // showing the CTA when it would just fail server-side is worse UX than
  // briefly hiding it.
  final bool trialAvailable;
  // Only set while the shop's current in-force subscription is itself a
  // TRIAL — null the rest of the time (including once it's expired; see
  // shop-status.service.js's lazy TRIAL->EXPIRED flip).
  final DateTime? trialEndsAt;

  const SubscriptionStatus({
    required this.shopStatus,
    this.subscriptionStatus,
    this.planName,
    this.effectivePlanName,
    this.endDate,
    required this.enabledModules,
    required this.fetchedAt,
    this.invoiceMonthlyLimit,
    this.staffLimit,
    this.trialUsed = false,
    this.trialAvailable = false,
    this.trialEndsAt,
  });

  // Strict equality (not a "default to Basic" fallback) deliberately — when
  // the plan isn't known yet (fresh install, offline before the first
  // successful check-in), this should fail open like isModuleEnabled()
  // does, not preemptively block voice billing. The server-side check in
  // shop-voice.service.js is the real backstop regardless of what this says.
  bool get isOnBasicPlan => effectivePlanName == 'Basic';

  // How long a cached status keeps being trusted before a gated module
  // defaults to blocked rather than open — see isModuleEnabled below.
  static const _gracePeriod = Duration(days: 3);

  /// Whether [moduleKey] should be accessible right now, given this cached
  /// status. Stays open for [_gracePeriod] past the last successful
  /// check-in (so a brief offline spell doesn't lock someone out of a
  /// module they're actually entitled to), then fails closed once that
  /// window lapses without a re-check. Callers with no cached status at all
  /// (never checked in) should fail open instead — see
  /// SubscriptionNotifier.isModuleEnabled and the router redirect in
  /// app_router.dart, the two places that decide what to do before a
  /// status even exists.
  bool isModuleEnabled(String moduleKey) {
    final withinGrace = DateTime.now().difference(fetchedAt) <= _gracePeriod;
    if (!withinGrace) return false;
    return enabledModules.contains(moduleKey);
  }

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
      invoiceMonthlyLimit: json['invoiceMonthlyLimit'] as int?,
      staffLimit: json['staffLimit'] as int?,
      trialUsed: json['trialUsed'] as bool? ?? false,
      trialAvailable: json['trialAvailable'] as bool? ?? false,
      trialEndsAt: json['trialEndsAt'] != null
          ? DateTime.tryParse(json['trialEndsAt'] as String)
          : null,
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
        'invoiceMonthlyLimit': invoiceMonthlyLimit,
        'staffLimit': staffLimit,
        'trialUsed': trialUsed,
        'trialAvailable': trialAvailable,
        'trialEndsAt': trialEndsAt?.toIso8601String(),
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
        invoiceMonthlyLimit: json['invoiceMonthlyLimit'] as int?,
        staffLimit: json['staffLimit'] as int?,
        trialUsed: json['trialUsed'] as bool? ?? false,
        trialAvailable: json['trialAvailable'] as bool? ?? false,
        trialEndsAt: json['trialEndsAt'] != null
            ? DateTime.tryParse(json['trialEndsAt'] as String)
            : null,
      );
}
