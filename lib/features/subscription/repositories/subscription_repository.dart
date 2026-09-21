import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/constants.dart';
import '../../auth/repositories/shop_repository.dart';
import '../models/subscription_status.dart';
import '../models/plan.dart';
import '../models/payment_claim.dart';
import '../models/voice_usage.dart';
import '../services/subscription_api_client.dart';

/// Thrown by the plan/payment-claim methods below when the shop has no
/// cached backend token yet (shouldn't happen once logged in — this is a
/// defensive guard, not a normal-flow error).
class NotLinkedToBackendException implements Exception {
  const NotLinkedToBackendException();
  @override
  String toString() => "This shop isn't linked to the server yet — try again after the next sync.";
}

class SubscriptionRepository {
  final SubscriptionApiClient _api;
  final ShopRepository _shopRepo;

  SubscriptionRepository(this._api, this._shopRepo);

  /// If this is ever false with no cached [SubscriptionStatus] either, the
  /// shop is stuck: [refreshStatus] silently no-ops forever without an
  /// [otpToken] (which only exists right after a fresh login/OTP verify —
  /// nothing else can safely re-prove identity to the backend), so nothing
  /// will ever populate the cache in the background. That combination is
  /// what a permanently-stuck "Checking status…" on the Profile screen
  /// means — see profile_screen.dart, which checks this to show something
  /// actionable instead of an endless loading label.
  Future<bool> hasBackendToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyShopBackendToken) != null;
  }

  Future<SubscriptionStatus?> getCachedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keySubscriptionStatusJson);
    if (raw == null) return null;
    try {
      return SubscriptionStatus.fromCacheJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort background sync with the backend. Never throws — on any
  /// failure (offline, backend down) it silently leaves the last-known cache
  /// in place, so it's always safe to call fire-and-forget.
  ///
  /// [otpToken] is required to *first* register the shop with the backend
  /// (register/login now require fresh OTP proof) — pass it right after a
  /// successful OTP verification. Calls made without it (splash/resume/
  /// periodic sync) simply skip registration if no token is cached yet, and
  /// succeed next time an explicit login/setup provides a fresh one.
  /// Checks whether the backend already has a shop for [phone] — used right
  /// after OTP verification when the *local* SQLite shop table is empty
  /// (fresh install, reinstall, or new device), to tell apart a genuinely
  /// new user from a returning one whose data only lives in the cloud.
  /// Returns `null` when the backend has no shop for this phone (safe to
  /// show the Setup screen); rethrows on a real network failure so the
  /// caller can ask the user to retry instead of risking a duplicate/empty
  /// shop getting created while the backend was merely unreachable.
  Future<ShopAuthResult?> checkExistingCloudShop(String phone, String otpToken) async {
    final result = await _api.login(phone, otpToken);
    if (result == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyShopBackendToken, result.token);
    return result;
  }

  Future<void> refreshStatus({String? otpToken}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConstants.keyIsDemoMode) ?? false) {
      return; // demo shops are a local sandbox, never registered with the backend
    }
    try {
      await _syncOnce(prefs, otpToken: otpToken);
    } catch (_) {
      // Offline or backend unreachable — keep last-known cache.
    }
  }

  /// Unlike [refreshStatus] (best-effort, silent on failure — it's called
  /// in the background all over the app), the methods below are all
  /// user-initiated actions on the Subscription screen: they let their
  /// exceptions propagate so the screen can show a real failure state
  /// instead of quietly doing nothing.
  Future<String> _requireToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyShopBackendToken);
    if (token == null) throw const NotLinkedToBackendException();
    return token;
  }

  Future<List<Plan>> listPlans() async => _api.listPlans(await _requireToken());

  Future<void> switchToFreePlan(String planId) async {
    await _api.switchToFreePlan(await _requireToken(), planId);
    await refreshStatus(); // re-check-in so enabledModules reflects the new plan immediately
  }

  Future<PaymentClaim> submitPaymentClaim({
    required String planId,
    required String reference,
    required double amount,
  }) async =>
      _api.createPaymentClaim(
        await _requireToken(),
        planId: planId,
        reference: reference,
        amount: amount,
      );

  Future<List<PaymentClaim>> listMyPaymentClaims() async =>
      _api.listMyPaymentClaims(await _requireToken());

  Future<VoiceUsage> getVoiceUsage() async => _api.getVoiceUsage(await _requireToken());

  Future<void> _syncOnce(SharedPreferences prefs,
      {String? otpToken, bool retryOnAuthFailure = true}) async {
    var token = prefs.getString(AppConstants.keyShopBackendToken);

    if (token == null) {
      if (otpToken == null) return; // no fresh OTP proof available yet
      final shop = await _shopRepo.getShop();
      if (shop == null) return; // shop not set up locally yet
      final result = await _api.register(
        name: shop.name,
        ownerName: shop.ownerName,
        phone: shop.phone,
        address: shop.address,
        otpToken: otpToken,
      );
      token = result.token;
      await prefs.setString(AppConstants.keyShopBackendToken, token);
    }

    try {
      final status = await _api.getStatus(token);
      await prefs.setString(
        AppConstants.keySubscriptionStatusJson,
        jsonEncode(status.toCacheJson()),
      );
    } on UnauthorizedException {
      if (!retryOnAuthFailure) rethrow;
      await prefs.remove(AppConstants.keyShopBackendToken);
      await _syncOnce(prefs, otpToken: otpToken, retryOnAuthFailure: false);
    }
  }
}
