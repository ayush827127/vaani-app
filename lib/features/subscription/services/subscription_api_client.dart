import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subscription_status.dart';

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
