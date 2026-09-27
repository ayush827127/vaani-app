import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/member.dart';

class UserAuthResult {
  final String token;
  final String? activeShopId;
  final List<Map<String, dynamic>> memberships;
  const UserAuthResult({required this.token, required this.activeShopId, required this.memberships});
}

/// Thrown when the backend rejects the user token, or a member action is
/// denied (missing permission, last-owner guard, etc.) — carries the
/// backend's own message straight through, since it's already written to be
/// shown to a shop owner (see requirePermission/ownerProtection.js).
class MemberApiException implements Exception {
  final String message;
  final int statusCode;
  const MemberApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

/// Mirrors SubscriptionApiClient's conventions exactly (health-poll retry
/// on cold start, `{success,data}`/`{success,error}` envelope handling) —
/// see that file's doc comments for why each piece exists.
class MemberApiClient {
  final String _baseUrl;
  final http.Client _client;

  MemberApiClient(this._baseUrl) : _client = http.Client();

  static const _tag = '[Members]';

  bool _looksLikeJson(String body) {
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  Future<void> _waitForBackendHealth() async {
    final deadline = DateTime.now().add(const Duration(seconds: 50));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final r = await _client.get(Uri.parse('$_baseUrl/health')).timeout(const Duration(seconds: 5));
        if (r.statusCode == 200 && _looksLikeJson(r.body)) return;
      } catch (e) {
        debugPrint('$_tag [health-poll] threw ${e.runtimeType}: $e');
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<http.Response> _sendWithRetry(Future<http.Response> Function() attempt) async {
    var response = await attempt();
    if (response.statusCode >= 500 || !_looksLikeJson(response.body)) {
      await _waitForBackendHealth();
      response = await attempt();
    }
    return response;
  }

  Map<String, String> _authHeaders(String token) =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

  Future<UserAuthResult> loginAsUser(String phone, String otpToken) async {
    final response = await _sendWithRetry(() => _client
        .post(
          Uri.parse('$_baseUrl/api/user/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone, 'otpToken': otpToken}),
        )
        .timeout(const Duration(seconds: 60)));
    final data = _unwrap(response) as Map<String, dynamic>;
    return UserAuthResult(
      token: data['token'] as String,
      activeShopId: data['activeShopId'] as String?,
      memberships: (data['memberships'] as List? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }

  Future<List<Member>> listMembers(String token) async {
    final response =
        await _sendWithRetry(() => _client.get(Uri.parse('$_baseUrl/api/shop/members'), headers: _authHeaders(token))
            .timeout(const Duration(seconds: 60)));
    final data = _unwrap(response) as List;
    return data.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> inviteMember(String token, String phone, String role) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/members/invite'),
          headers: _authHeaders(token),
          body: jsonEncode({'phone': phone, 'role': role}),
        )
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  Future<void> revokeInvite(String token, String invitationId) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/shop/members/invite/$invitationId/revoke'),
          headers: _authHeaders(token),
        )
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  Future<void> changeRole(String token, String shopUserId, String role) async {
    final response = await _client
        .patch(
          Uri.parse('$_baseUrl/api/shop/members/$shopUserId/role'),
          headers: _authHeaders(token),
          body: jsonEncode({'role': role}),
        )
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  Future<void> removeMember(String token, String shopUserId) async {
    final response = await _client
        .delete(Uri.parse('$_baseUrl/api/shop/members/$shopUserId'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  Future<void> leaveShop(String token) async {
    final response = await _client
        .post(Uri.parse('$_baseUrl/api/shop/members/leave'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 60));
    _unwrap(response);
  }

  dynamic _unwrap(http.Response response) {
    if (!_looksLikeJson(response.body)) {
      throw MemberApiException(
        'Server is temporarily unavailable (HTTP ${response.statusCode}). Please try again in a moment.',
        response.statusCode,
      );
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>?;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (envelope?['error'] as Map<String, dynamic>?)?['message'] as String?;
      throw MemberApiException(message ?? 'Request failed: HTTP ${response.statusCode}', response.statusCode);
    }
    return envelope?['data'];
  }
}
