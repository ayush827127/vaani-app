import 'package:flutter_test/flutter_test.dart';
import 'package:vaani/features/subscription/models/usage_stat.dart';
import 'package:vaani/features/subscription/models/plan.dart';

void main() {
  group('UsageStat.fromJson', () {
    test('parses a capped usage figure', () {
      final usage = UsageStat.fromJson({'used': 12, 'limit': 50, 'unlimited': false});
      expect(usage.used, 12);
      expect(usage.limit, 50);
      expect(usage.unlimited, isFalse);
    });

    test('parses an unlimited usage figure (limit null)', () {
      final usage = UsageStat.fromJson({'used': 500, 'limit': null, 'unlimited': true});
      expect(usage.limit, isNull);
      expect(usage.unlimited, isTrue);
    });
  });

  group('Plan.fromJson', () {
    test('parses real resource-limit numbers', () {
      final plan = Plan.fromJson({
        'id': 'plan-basic',
        'name': 'Basic',
        'price': '0.00',
        'billingCycle': 'MONTHLY',
        'modules': ['billing'],
        'voiceInvoiceLimit': 50,
        'staffLimit': 0,
        'manualInvoiceMonthlyLimit': 50,
      });

      expect(plan.voiceInvoiceLimit, 50);
      expect(plan.staffLimit, 0);
      expect(plan.manualInvoiceMonthlyLimit, 50);
    });

    test('a plan with no limit fields at all (unlimited) parses to null, not an error', () {
      final plan = Plan.fromJson({
        'id': 'plan-pro',
        'name': 'Pro',
        'price': '99.00',
        'billingCycle': 'MONTHLY',
        'modules': ['billing', 'reports'],
      });

      expect(plan.voiceInvoiceLimit, isNull);
      expect(plan.staffLimit, isNull);
      expect(plan.manualInvoiceMonthlyLimit, isNull);
    });
  });
}
