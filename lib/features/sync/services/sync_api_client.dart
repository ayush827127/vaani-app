import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../subscription/services/subscription_api_client.dart' show UnauthorizedException;

class SyncApiClient {
  final String _baseUrl;
  final http.Client _client;

  SyncApiClient(this._baseUrl) : _client = http.Client();

  Future<Map<String, dynamic>> sync(String token, Map<String, dynamic> payload) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/sync'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        // Generous timeout: the backend runs on a free-tier host that can
        // take up to ~50s to wake up from sleep on the first request.
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      throw const UnauthorizedException('Shop token rejected by backend');
    }
    if (response.statusCode != 200) {
      throw Exception('Sync failed: HTTP ${response.statusCode}');
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pull(String token, DateTime? since) async {
    final uri = Uri.parse('$_baseUrl/api/shop/sync/pull').replace(
      queryParameters: since != null ? {'since': since.toIso8601String()} : null,
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      throw const UnauthorizedException('Shop token rejected by backend');
    }
    if (response.statusCode != 200) {
      throw Exception('Pull failed: HTTP ${response.statusCode}');
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }
}
