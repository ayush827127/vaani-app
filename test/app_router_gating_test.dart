import 'package:flutter_test/flutter_test.dart';
import 'package:vaani/core/router/app_router.dart';

/// moduleForGatedLocation is the pure lookup the router's redirect callback
/// uses — every catalog module that has a real screen behind it must gate
/// correctly here, or a plan/override change silently stops taking effect
/// for that screen (see the doc comment on _gatedRoutePrefixes).
void main() {
  group('exact top-level routes', () {
    final cases = {
      '/billing': 'billing',
      '/bills': 'billing',
      '/inventory': 'inventory',
      '/customers': 'customers',
      '/reports': 'reports',
      '/ai-manager': 'ai_manager',
      '/notifications': 'notifications',
    };
    for (final entry in cases.entries) {
      test('${entry.key} is gated by "${entry.value}"', () {
        expect(moduleForGatedLocation(entry.key), entry.value);
      });
    }
  });

  group('sub-routes inherit their parent module', () {
    final cases = {
      '/billing/voice': 'billing',
      '/billing/invoice': 'billing',
      '/bills/42': 'billing',
      '/inventory/add': 'inventory',
      '/inventory/item/7': 'inventory',
      '/inventory/barcode-preview': 'inventory',
      '/customers/3': 'customers',
      '/customers/3/edit': 'customers',
    };
    for (final entry in cases.entries) {
      test('${entry.key} is gated by "${entry.value}"', () {
        expect(moduleForGatedLocation(entry.key), entry.value);
      });
    }
  });

  test('/profile/printer is gated by "printer", but /profile itself is not', () {
    expect(moduleForGatedLocation('/profile/printer'), 'printer');
    expect(moduleForGatedLocation('/profile'), isNull);
  });

  group('never gated', () {
    final locations = [
      '/splash',
      '/onboarding',
      '/login',
      '/setup',
      '/home',
      '/profile',
      '/profile/edit',
      '/profile/change-phone',
      '/profile/backup',
      '/profile/subscription',
      '/profile/members',
      '/join-business',
      '/select-business',
    ];
    for (final location in locations) {
      test('$location is never gated', () {
        expect(moduleForGatedLocation(location), isNull);
      });
    }
  });

  test('a route that merely shares a prefix string is not a false-positive match', () {
    // A hypothetical unrelated route starting with the same characters as a
    // gated prefix must not match — only an exact prefix or "prefix/..." does.
    expect(moduleForGatedLocation('/billingsomethingelse'), isNull);
    expect(moduleForGatedLocation('/inventory-report'), isNull);
    expect(moduleForGatedLocation('/customersX'), isNull);
  });
}
