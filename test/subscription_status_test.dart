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
}
