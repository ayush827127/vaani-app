import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaani/core/utils/constants.dart';
import 'package:vaani/features/members/models/member.dart';
import 'package:vaani/features/members/models/invitation.dart';
import 'package:vaani/features/members/repositories/member_repository.dart';
import 'package:vaani/features/members/services/member_api_client.dart';

/// A hand-rolled fake rather than a mocking package (none is used elsewhere
/// in this codebase's tests) — implements every method MemberRepository
/// actually calls, scripted per test via the fields below.
class _FakeMemberApiClient implements MemberApiClient {
  UserAuthResult? loginResult;
  Object? loginError;
  List<Member> members = const [];
  List<Invitation> invitations = const [];
  AcceptedMembership? acceptResult;
  String selectShopTokenReturned = 'refreshed-token';

  @override
  Future<UserAuthResult> loginAsUser(String phone, String otpToken) async {
    if (loginError != null) throw loginError!;
    return loginResult!;
  }

  @override
  Future<List<Member>> listMembers(String token) async => members;

  @override
  Future<void> inviteMember(String token, String phone, String role) async {}
  @override
  Future<void> revokeInvite(String token, String invitationId) async {}
  @override
  Future<void> changeRole(String token, String shopUserId, String role) async {}
  @override
  Future<void> removeMember(String token, String shopUserId) async {}
  @override
  Future<void> leaveShop(String token) async {}

  @override
  Future<List<Invitation>> listMyInvitations(String token) async => invitations;

  @override
  Future<AcceptedMembership> acceptInvitation(String token, String invitationId) async => acceptResult!;

  @override
  Future<void> rejectInvitation(String token, String invitationId) async {}

  @override
  Future<String> selectShop(String token, String shopId) async => selectShopTokenReturned;
}

void main() {
  late _FakeMemberApiClient fakeClient;
  late MemberRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeClient = _FakeMemberApiClient();
    repo = MemberRepository(fakeClient);
  });

  test('ensureUserSession caches the token and activeShopId on success', () async {
    fakeClient.loginResult =
        const UserAuthResult(token: 'user-token-1', activeShopId: 'shop-1', memberships: []);

    await repo.ensureUserSession('9876543210', 'otp-token');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.keyUserBackendToken), 'user-token-1');
    expect(prefs.getString(AppConstants.keyActiveShopId), 'shop-1');
    expect(await repo.hasUserSession(), isTrue);
  });

  test('ensureUserSession never throws, even when the API call fails', () async {
    fakeClient.loginError = Exception('network down');

    await expectLater(repo.ensureUserSession('9876543210', 'otp-token'), completes);
    expect(await repo.hasUserSession(), isFalse);
  });

  test('with no cached session, every pass-through method throws NoUserSessionException', () async {
    await expectLater(repo.listMembers(), throwsA(isA<NoUserSessionException>()));
    await expectLater(repo.inviteMember('9876543210', 'CASHIER'), throwsA(isA<NoUserSessionException>()));
    await expectLater(repo.leaveShop(), throwsA(isA<NoUserSessionException>()));
  });

  test('once a session is cached, listMembers uses it against the client', () async {
    fakeClient.loginResult =
        const UserAuthResult(token: 'user-token-1', activeShopId: 'shop-1', memberships: []);
    fakeClient.members = const [
      Member(shopUserId: 'su-1', userId: 'user-1', name: 'Ravi', phone: '9999900001', role: 'OWNER'),
    ];
    await repo.ensureUserSession('9876543210', 'otp-token');

    final members = await repo.listMembers();
    expect(members, hasLength(1));
    expect(members.single.name, 'Ravi');
  });

  test('checkForPendingInvitations caches the session and returns the invitation list', () async {
    fakeClient.loginResult =
        const UserAuthResult(token: 'user-token-1', activeShopId: null, memberships: []);
    fakeClient.invitations = const [
      Invitation(id: 'inv-1', shopId: 'shop-1', shopName: 'ABC Store', role: 'CASHIER'),
    ];

    final check = await repo.checkForPendingInvitations('9876543210', 'otp-token');

    expect(check.invitations, hasLength(1));
    expect(check.memberships, isEmpty);
    expect(await repo.hasUserSession(), isTrue);
  });

  test('checkForPendingInvitations also surfaces 2+ active memberships for the select-business picker', () async {
    fakeClient.loginResult = const UserAuthResult(token: 'user-token-1', activeShopId: null, memberships: [
      {'shopId': 'shop-1', 'shopName': 'ABC Store', 'role': 'CASHIER', 'status': 'ACTIVE'},
      {'shopId': 'shop-2', 'shopName': 'XYZ Store', 'role': 'MANAGER', 'status': 'ACTIVE'},
    ]);

    final check = await repo.checkForPendingInvitations('9876543210', 'otp-token');

    expect(check.memberships, hasLength(2));
    expect(check.memberships.first.shopName, 'ABC Store');
    expect(check.invitations, isEmpty);
  });

  test('checkForPendingInvitations returns empty (never throws) on failure', () async {
    fakeClient.loginError = Exception('network down');

    final check = await repo.checkForPendingInvitations('9876543210', 'otp-token');

    expect(check.invitations, isEmpty);
    expect(check.memberships, isEmpty);
  });

  test('selectShopAndRefresh caches the fresh token and the new activeShopId', () async {
    fakeClient.loginResult =
        const UserAuthResult(token: 'user-token-1', activeShopId: null, memberships: []);
    await repo.ensureUserSession('9876543210', 'otp-token');
    fakeClient.selectShopTokenReturned = 'user-token-2';

    await repo.selectShopAndRefresh('shop-1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.keyUserBackendToken), 'user-token-2');
    expect(prefs.getString(AppConstants.keyActiveShopId), 'shop-1');
  });

  test('acceptInvitation requires a session and returns the enriched membership', () async {
    fakeClient.loginResult =
        const UserAuthResult(token: 'user-token-1', activeShopId: null, memberships: []);
    await repo.ensureUserSession('9876543210', 'otp-token');
    fakeClient.acceptResult = const AcceptedMembership(
      shopId: 'shop-1',
      shopName: 'ABC Store',
      ownerName: 'Ramesh',
      address: null,
      gstNumber: null,
      currency: 'INR',
      gstEnabled: true,
      defaultGstRate: 5.0,
      upiId: null,
    );

    final result = await repo.acceptInvitation('inv-1');
    expect(result.shopName, 'ABC Store');
  });
}
