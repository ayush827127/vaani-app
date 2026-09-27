import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/constants.dart';
import '../models/member.dart';
import '../services/member_api_client.dart';

/// Thrown by every pass-through method below when no user session has ever
/// been cached — there's no way to silently recover this outside the login
/// flow, since /api/user/auth/login requires a fresh OTP (the same
/// limitation SubscriptionRepository already documents for its own token).
class NoUserSessionException implements Exception {
  const NoUserSessionException();
  @override
  String toString() => 'Log out and log back in to enable this';
}

class MemberRepository {
  final MemberApiClient _client;
  MemberRepository(this._client);

  /// Best-effort — called right after the existing legacy login already
  /// succeeded, reusing the same otpToken (both /api/shop/auth/login and
  /// /api/user/auth/login accept the same generic requireOtpVerified check).
  /// Never throws: a failure here must never block or surface an error
  /// during the existing login flow, exactly like
  /// SubscriptionRepository.refreshStatus's own "silently no-ops" pattern.
  Future<void> ensureUserSession(String phone, String otpToken) async {
    try {
      final result = await _client.loginAsUser(phone, otpToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserBackendToken, result.token);
      if (result.activeShopId != null) {
        await prefs.setString(AppConstants.keyActiveShopId, result.activeShopId!);
      }
    } catch (e) {
      debugPrint('[MemberRepository] ensureUserSession failed (non-fatal): $e');
    }
  }

  Future<bool> hasUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyUserBackendToken);
    return token != null && token.isNotEmpty;
  }

  Future<String> _requireToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyUserBackendToken);
    if (token == null || token.isEmpty) throw const NoUserSessionException();
    return token;
  }

  Future<List<Member>> listMembers() async => _client.listMembers(await _requireToken());

  Future<void> inviteMember(String phone, String role) async =>
      _client.inviteMember(await _requireToken(), phone, role);

  Future<void> revokeInvite(String invitationId) async =>
      _client.revokeInvite(await _requireToken(), invitationId);

  Future<void> changeRole(String shopUserId, String role) async =>
      _client.changeRole(await _requireToken(), shopUserId, role);

  Future<void> removeMember(String shopUserId) async =>
      _client.removeMember(await _requireToken(), shopUserId);

  Future<void> leaveShop() async => _client.leaveShop(await _requireToken());
}
