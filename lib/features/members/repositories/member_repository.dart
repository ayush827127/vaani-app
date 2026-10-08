import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/constants.dart';
import '../../subscription/models/usage_stat.dart';
import '../models/member.dart';
import '../models/invitation.dart';
import '../models/membership.dart';
import '../services/member_api_client.dart';

/// What checkForPendingInvitations found for a phone with no local shop and
/// no legacy cloud shop — everything the login screen needs to decide
/// between "genuinely new" (/setup), "one pending invite" (/join-business),
/// or "already belongs to 2+ businesses" (/select-business).
class PendingInvitationsCheck {
  final List<Invitation> invitations;
  final List<Membership> memberships;
  const PendingInvitationsCheck({required this.invitations, required this.memberships});
  static const empty = PendingInvitationsCheck(invitations: [], memberships: []);
}

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

  Future<void> _cacheSession(String token, String? activeShopId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUserBackendToken, token);
    if (activeShopId != null) {
      await prefs.setString(AppConstants.keyActiveShopId, activeShopId);
    } else {
      await prefs.remove(AppConstants.keyActiveShopId);
    }
  }

  /// Best-effort — called right after the existing legacy login already
  /// succeeded, reusing the same otpToken (both /api/shop/auth/login and
  /// /api/user/auth/login accept the same generic requireOtpVerified check).
  /// Never throws: a failure here must never block or surface an error
  /// during the existing login flow, exactly like
  /// SubscriptionRepository.refreshStatus's own "silently no-ops" pattern.
  Future<void> ensureUserSession(String phone, String otpToken) async {
    try {
      final result = await _client.loginAsUser(phone, otpToken);
      await _cacheSession(result.token, result.activeShopId);
    } catch (e) {
      debugPrint('[MemberRepository] ensureUserSession failed (non-fatal): $e');
    }
  }

  /// Same login call as [ensureUserSession], but for the login screen's
  /// "no local shop, no cloud shop" branch — also checks for pending
  /// invitations and existing active memberships before that branch assumes
  /// "genuinely new, go create a shop". Returns [PendingInvitationsCheck.empty]
  /// (never throws) on any failure, so the caller can simply fall through to
  /// today's existing behavior.
  Future<PendingInvitationsCheck> checkForPendingInvitations(String phone, String otpToken) async {
    try {
      final result = await _client.loginAsUser(phone, otpToken);
      await _cacheSession(result.token, result.activeShopId);
      final invitations = await _client.listMyInvitations(result.token);
      final memberships = result.memberships.map(Membership.fromJson).toList();
      return PendingInvitationsCheck(invitations: invitations, memberships: memberships);
    } catch (e) {
      debugPrint('[MemberRepository] checkForPendingInvitations failed (non-fatal): $e');
      return PendingInvitationsCheck.empty;
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

  Future<UsageStat> getStaffQuota() async => _client.getStaffQuota(await _requireToken());

  Future<void> inviteMember(String phone, String role) async =>
      _client.inviteMember(await _requireToken(), phone, role);

  Future<void> revokeInvite(String invitationId) async =>
      _client.revokeInvite(await _requireToken(), invitationId);

  Future<void> changeRole(String shopUserId, String role) async =>
      _client.changeRole(await _requireToken(), shopUserId, role);

  Future<void> removeMember(String shopUserId) async =>
      _client.removeMember(await _requireToken(), shopUserId);

  Future<void> leaveShop() async => _client.leaveShop(await _requireToken());

  Future<List<Invitation>> listMyInvitations() async => _client.listMyInvitations(await _requireToken());

  Future<AcceptedMembership> acceptInvitation(String invitationId) async =>
      _client.acceptInvitation(await _requireToken(), invitationId);

  Future<void> rejectInvitation(String invitationId) async =>
      _client.rejectInvitation(await _requireToken(), invitationId);

  /// Caches the fresh token this returns as the new active session — see
  /// MemberApiClient.selectShop's doc comment for why a new token is needed
  /// after accepting an invitation.
  Future<void> selectShopAndRefresh(String shopId) async {
    final token = await _client.selectShop(await _requireToken(), shopId);
    await _cacheSession(token, shopId);
  }
}
