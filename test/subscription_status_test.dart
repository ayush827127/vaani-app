import 'package:flutter_test/flutter_test.dart';
import 'package:vaani/features/subscription/models/subscription_status.dart';

/// SubscriptionStatus.isModuleEnabled is what both the home screen's Quick
/// Actions gating and the router-level redirect in app_router.dart rely on
/// to keep a Basic-plan shop out of paid-only modules (reports, ai_manager)
/// — this is the one place that logic lives, so a bug here would silently
/// desync what a button shows from what the router actually allows.
void main() {
  SubscriptionStatus statusAsOf(DateTime fetchedAt, List<String> modules) =>
      SubscriptionStatus(
        shopStatus: 'ACTIVE',
        effectivePlanName: 'Basic',
        enabledModules: modules,
        fetchedAt: fetchedAt,
      );

  test('a module present in enabledModules is enabled right after a fresh check-in', () {
    final status = statusAsOf(DateTime.now(), ['billing', 'inventory']);
    expect(status.isModuleEnabled('billing'), isTrue);
  });

  test('a module absent from enabledModules (Basic plan, paid-only module) is blocked', () {
    final status = statusAsOf(DateTime.now(), ['billing', 'inventory']);
    expect(status.isModuleEnabled('reports'), isFalse);
    expect(status.isModuleEnabled('ai_manager'), isFalse);
  });

  test('stays open within the grace period even if slightly stale', () {
    final status = statusAsOf(DateTime.now().subtract(const Duration(days: 2)), ['reports']);
    expect(status.isModuleEnabled('reports'), isTrue);
  });

  test('fails closed once the grace period has fully lapsed without a re-check', () {
    final status = statusAsOf(DateTime.now().subtract(const Duration(days: 4)), ['reports']);
    expect(status.isModuleEnabled('reports'), isFalse);
  });

  group('resource limits', () {
    test('fromJson parses real numeric caps straight through', () {
      final status = SubscriptionStatus.fromJson({
        'shopStatus': 'ACTIVE',
        'effectivePlanName': 'Basic',
        'modules': ['billing'],
        'invoiceMonthlyLimit': 50,
        'staffLimit': 0,
      });

      expect(status.invoiceMonthlyLimit, 50);
      expect(status.staffLimit, 0);
    });

    test('fromJson treats a missing/null limit as unlimited (null), not a parse error', () {
      final status = SubscriptionStatus.fromJson({
        'shopStatus': 'ACTIVE',
        'effectivePlanName': 'Pro',
        'modules': ['billing', 'reports'],
      });

      expect(status.invoiceMonthlyLimit, isNull);
      expect(status.staffLimit, isNull);
    });

    test('round-trips through toCacheJson/fromCacheJson without losing the limits', () {
      final original = statusAsOf(DateTime.now(), ['billing']);
      final withLimits = SubscriptionStatus(
        shopStatus: original.shopStatus,
        effectivePlanName: original.effectivePlanName,
        enabledModules: original.enabledModules,
        fetchedAt: original.fetchedAt,
        invoiceMonthlyLimit: 50,
        staffLimit: 0,
      );

      final restored = SubscriptionStatus.fromCacheJson(withLimits.toCacheJson());

      expect(restored.invoiceMonthlyLimit, 50);
      expect(restored.staffLimit, 0);
    });
  });

  group('trial fields', () {
    test('fromJson parses real trial state straight through', () {
      final status = SubscriptionStatus.fromJson({
        'shopStatus': 'ACTIVE',
        'effectivePlanName': 'Pro',
        'modules': ['billing', 'reports'],
        'trialUsed': true,
        'trialAvailable': false,
        'trialEndsAt': '2026-10-22T00:00:00.000Z',
      });

      expect(status.trialUsed, isTrue);
      expect(status.trialAvailable, isFalse);
      expect(status.trialEndsAt, DateTime.parse('2026-10-22T00:00:00.000Z'));
    });

    test('fromJson defaults trialUsed/trialAvailable to false and trialEndsAt to null when absent', () {
      final status = SubscriptionStatus.fromJson({
        'shopStatus': 'ACTIVE',
        'effectivePlanName': 'Basic',
        'modules': ['billing'],
      });

      expect(status.trialUsed, isFalse);
      expect(status.trialAvailable, isFalse);
      expect(status.trialEndsAt, isNull);
    });

    test('round-trips through toCacheJson/fromCacheJson without losing trial state', () {
      final original = statusAsOf(DateTime.now(), ['billing']);
      final endsAt = DateTime.now().add(const Duration(days: 5));
      final withTrial = SubscriptionStatus(
        shopStatus: original.shopStatus,
        effectivePlanName: 'Pro',
        enabledModules: original.enabledModules,
        fetchedAt: original.fetchedAt,
        trialUsed: true,
        trialAvailable: false,
        trialEndsAt: endsAt,
      );

      final restored = SubscriptionStatus.fromCacheJson(withTrial.toCacheJson());

      expect(restored.trialUsed, isTrue);
      expect(restored.trialAvailable, isFalse);
      expect(restored.trialEndsAt, endsAt);
    });
  });
}
