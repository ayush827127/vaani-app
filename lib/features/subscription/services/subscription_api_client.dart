import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subscription_status.dart';
import '../models/plan.dart';
import '../models/payment_claim.dart';
import '../models/voice_usage.dart';

class ShopAuthResult {
  final String token;
  final Map<String, dynamic> shop;
  const ShopAuthResult({required this.token, required this.shop});
}

/// Thrown when the backend rejects the shop token (expired/invalid) so the
/// repository can clear it and re-register.
class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException(this.message);
  @override
  String toString() => message;
}

/// Thrown by [SubscriptionApiClient.changePhone] when the new number is
/// already registered to a different shop on the backend.
class PhoneAlreadyRegisteredException implements Exception {
  const PhoneAlreadyRegisteredException();
  @override
  String toString() => 'This phone number is already registered to another shop';
}

/// Thrown by any subscription/plan/payment-claim call that gets back a
/// non-2xx response — carries the backend's own error message (e.g. "This
/// plan requires payment", "This claim was already confirmed") straight
/// through, since those are already written to be shown to a shop owner.
class SubscriptionApiException implements Exception {
  final String message;
  final int statusCode;
  const SubscriptionApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

class SubscriptionApiClient {
  final String _baseUrl;
  final http.Client _client;

  SubscriptionApiClient(this._baseUrl) : _client = http.Client();

  Future<ShopAuthResult> register({
    required String name,
    required String ownerName,
    required String phone,
    required String otpToken,
    String? address,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'ownerName': ownerName,
            'phone': phone,
            'otpToken': otpToken,
            if (address != null && address.isNotEmpty) 'address': address,
          }),
        )
        .timeout(const Duration(seconds: 60));
    return _parseAuthResponse(response);
  }

  /// Checks whether the backend already has a shop for [phone]. Returns
  /// `null` specifically for a 404 ("no shop registered for this phone") so
  /// callers can treat that as "genuinely new user" rather than an error —
  /// any other failure (network, 5xx) still throws.
  Future<ShopAuthResult?> login(String phone, String otpToken) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'otpToken': otpToken}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 404) return null;
    return _parseAuthResponse(response);
  }

  /// Updates the shop's phone number on the backend and returns a fresh
  /// token (the old one embeds the old phone — see signShopToken on the
  /// backend). [newPhone] must already be OTP-verified via [otpToken].
  /// Throws [PhoneAlreadyRegisteredException] if another shop already has
  /// that number (HTTP 409).
  Future<ShopAuthResult> changePhone(
    String currentToken,
    String newPhone,
    String otpToken,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/auth/change-phone'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $currentToken',
          },
          body: jsonEncode({'phone': newPhone, 'otpToken': otpToken}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 401) {
      throw const UnauthorizedException('Shop token rejected by backend');
    }
    if (response.statusCode == 409) {
      throw const PhoneAlreadyRegisteredException();
    }
    return _parseAuthResponse(response);
  }

  Future<SubscriptionStatus> getStatus(String token) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/shop/me/status'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      throw const UnauthorizedException('Shop token rejected by backend');
    }
    if (response.statusCode != 200) {
      throw Exception('Status fetch failed: HTTP ${response.statusCode}');
    }

    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    return SubscriptionStatus.fromJson(envelope['data'] as Map<String, dynamic>);
  }

  Future<List<Plan>> listPlans(String token) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/shop/plans'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));
    final data = _unwrap(response) as List;
    return data.map((e) => Plan.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Switches the shop straight to a free (₹0) plan — no payment claim
  /// needed. The backend independently re-checks the plan is actually free
  /// before applying this, so passing a paid plan's id here just throws
  /// rather than granting it.
  Future<void> switchToFreePlan(String token, String planId) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/subscription/switch-free'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'planId': planId}),
        )
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  /// Submits a payment claim — see PaymentClaim's doc comment on the
  /// backend for why this never activates anything by itself. [reference]
  /// must be the same value used for every retry of the *same* intended
  /// payment (the backend treats it as an idempotency key), and should be
  /// the exact transaction note embedded in the UPI intent so an admin can
  /// match the two up.
  Future<PaymentClaim> createPaymentClaim(
    String token, {
    required String planId,
    required String reference,
    required double amount,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/payment-claims'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'planId': planId, 'reference': reference, 'amount': amount}),
        )
        .timeout(const Duration(seconds: 60));
    return PaymentClaim.fromJson(_unwrap(response) as Map<String, dynamic>);
  }

  Future<List<PaymentClaim>> listMyPaymentClaims(String token) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/shop/payment-claims'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));
    final data = _unwrap(response) as List;
    return data.map((e) => PaymentClaim.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Server-computed voice-invoice usage for the current plan — see
  /// getVoiceUsage on the backend for why this is trusted over any local
  /// count for *display*, even though checkout itself still gates on the
  /// local count for instant, offline-friendly feedback.
  Future<VoiceUsage> getVoiceUsage(String token) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/shop/subscription/voice-usage'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));
    return VoiceUsage.fromJson(_unwrap(response) as Map<String, dynamic>);
  }

  /// Unwraps `{success, data}`/`{success, error}` envelopes, throwing
  /// [UnauthorizedException] for a 401 and [SubscriptionApiException] (with
  /// the backend's own message) for any other non-2xx response.
  dynamic _unwrap(http.Response response) {
    final envelope = jsonDecode(response.body) as Map<String, dynamic>?;
    if (response.statusCode == 401) {
      throw const UnauthorizedException('Shop token rejected by backend');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (envelope?['error'] as Map<String, dynamic>?)?['message'] as String?;
      throw SubscriptionApiException(
        message ?? 'Request failed: HTTP ${response.statusCode}',
        response.statusCode,
      );
    }
    return envelope?['data'];
  }

  ShopAuthResult _parseAuthResponse(http.Response response) {
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Shop auth failed: HTTP ${response.statusCode}');
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    return ShopAuthResult(
      token: data['token'] as String,
      shop: data['shop'] as Map<String, dynamic>,
    );
  }
}
