import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/shop_setup_screen.dart';
import '../../features/auth/screens/profile_screen.dart';
import '../../features/auth/screens/edit_profile_screen.dart';
import '../../features/auth/screens/change_phone_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/billing/screens/bills_screen.dart';
import '../../features/billing/screens/bill_detail_screen.dart';
import '../../features/billing/screens/voice_billing_screen.dart';
import '../../features/billing/screens/invoice_preview_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/inventory/screens/add_item_screen.dart';
import '../../features/inventory/screens/item_details_screen.dart';
import '../../features/inventory/screens/barcode_preview_screen.dart';
import '../../features/customers/screens/customer_list_screen.dart';
import '../../features/customers/screens/customer_details_screen.dart';
import '../../features/customers/screens/edit_customer_screen.dart';
import '../../shared/models/customer.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/ai_manager/screens/ai_manager_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/settings/screens/backup_restore_screen.dart';
import '../../features/printer/screens/printer_settings_screen.dart';
import '../../features/subscription/screens/subscription_screen.dart';
import '../../shared/widgets/main_shell.dart';
import '../utils/constants.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

GoRouter createRouter() => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/setup',
          builder: (_, __) => const ShopSetupScreen(),
        ),

        ShellRoute(
          navigatorKey: _shellKey,
          builder: (_, __, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, __) => const HomeScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'edit',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const EditProfileScreen(),
                ),
                GoRoute(
                  path: 'change-phone',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const ChangePhoneScreen(),
                ),
                GoRoute(
                  path: 'printer',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const PrinterSettingsScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const BackupRestoreScreen(),
                ),
                GoRoute(
                  path: 'subscription',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const SubscriptionScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/billing',
              builder: (context, state) =>
                  BillingScreen(initialCustomer: state.extra as Customer?),
              routes: [
                GoRoute(
                  path: 'voice',
                  parentNavigatorKey: _rootKey,
                  builder: (_, __) => const VoiceBillingScreen(),
                ),
                GoRoute(
                  path: 'invoice',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>?;
                    return InvoicePreviewScreen(invoiceData: extra);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/inventory',
              builder: (_, __) => const InventoryScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) {
                    final itemId = state.extra as int?;
                    return AddItemScreen(itemId: itemId);
                  },
                ),
                GoRoute(
                  path: 'item/:id',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) {
                    final id = int.parse(state.pathParameters['id']!);
                    return ItemDetailsScreen(itemId: id);
                  },
                ),
                GoRoute(
                  path: 'barcode-preview',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) {
                    final args = state.extra as Map<String, String>;
                    return BarcodePreviewScreen(
                      barcode: args['barcode']!,
                      itemName: args['itemName']!,
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/customers',
              builder: (_, __) => const CustomerListScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) {
                    final id = int.parse(state.pathParameters['id']!);
                    return CustomerDetailsScreen(customerId: id);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: _rootKey,
                      builder: (context, state) {
                        final customer = state.extra as Customer;
                        return EditCustomerScreen(customer: customer);
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/bills',
              builder: (_, __) => const BillsScreen(),
            ),
            GoRoute(
              path: '/reports',
              builder: (_, __) => const ReportsScreen(),
            ),
            GoRoute(
              path: '/ai-manager',
              builder: (_, __) => const AIManagerScreen(),
            ),
          ],
        ),

        GoRoute(
          path: '/bills/:id',
          parentNavigatorKey: _rootKey,
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return BillDetailScreen(invoiceId: id);
          },
        ),

        GoRoute(
          path: '/notifications',
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const NotificationsScreen(),
        ),
      ],
    );

Future<String> getInitialRoute() async {
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
  final isSetupComplete = prefs.getBool(AppConstants.keyIsSetupComplete) ?? false;
  if (!isLoggedIn) return '/onboarding';
  if (!isSetupComplete) return '/setup';
  return '/home';
}
