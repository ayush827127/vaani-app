import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/injector.dart';
import '../../../l10n/l10n_extensions.dart';
import '../models/member.dart';
import '../repositories/member_repository.dart';

const _roles = ['OWNER', 'MANAGER', 'CASHIER'];

class ManageMembersScreen extends StatefulWidget {
  const ManageMembersScreen({super.key});

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  bool _loading = true;
  String? _loadError;
  List<Member> _members = [];
  bool _hasSession = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repo = getIt<MemberRepository>();
    final hasSession = await repo.hasUserSession();
    if (!hasSession) {
      if (!mounted) return;
      setState(() {
        _hasSession = false;
        _loading = false;
      });
      return;
    }
    try {
      final members = await repo.listMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _hasSession = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
    );
  }

  Future<void> _invite() async {
    final l10n = context.l10n;
    final phoneCtrl = TextEditingController();
    String role = 'CASHIER';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final c = dialogContext.colors;
          return AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(l10n.inviteMember, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: InputDecoration(labelText: l10n.phoneNumberLabel, counterText: ''),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: l10n.roleLabel),
                  items: _roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => role = v ?? role),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.sendInvite),
              ),
            ],
          );
        },
      ),
    );
    if (result != true) return;
    final phone = phoneCtrl.text.trim();
    if (phone.length != 10) {
      _showError(l10n.invalidPhoneNumber);
      return;
    }
    try {
      await getIt<MemberRepository>().inviteMember(phone, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.invitationSent), backgroundColor: AppColors.success),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _changeRole(Member member) async {
    final l10n = context.l10n;
    String role = member.role;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final c = dialogContext.colors;
          return AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(l10n.changeRole, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
            content: DropdownButtonFormField<String>(
              initialValue: role,
              items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setDialogState(() => role = v ?? role),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
    if (result != true) return;
    try {
      await getIt<MemberRepository>().changeRole(member.shopUserId, role);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _removeMember(Member member) async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.removeMemberTitle, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(l10n.removeMemberConfirm(member.name), style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await getIt<MemberRepository>().removeMember(member.shopUserId);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  void _openMemberActions(Member member) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.swap_horiz_rounded, color: c.textPrimary),
                title: Text(l10n.changeRole),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _changeRole(member);
                },
              ),
              ListTile(
                leading: Icon(Icons.person_remove_rounded, color: c.danger),
                title: Text(l10n.remove, style: TextStyle(color: c.danger)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeMember(member);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _leaveShop() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.leaveBusinessTitle, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(l10n.leaveBusinessConfirm, style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await getIt<MemberRepository>().leaveShop();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageMembers)),
      floatingActionButton: _hasSession && !_loading
          ? FloatingActionButton(onPressed: _invite, child: const Icon(Icons.person_add_rounded))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasSession
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.noUserSessionMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                )
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _members.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _members.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: TextButton(
                                onPressed: _leaveShop,
                                child: Text(l10n.leaveThisBusiness, style: TextStyle(color: c.danger)),
                              ),
                            );
                          }
                          final member = _members[index];
                          return Card(
                            color: c.surface,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(member.name, style: TextStyle(color: c.textPrimary)),
                              subtitle: Text(member.phone, style: TextStyle(color: c.textSecondary)),
                              trailing: Chip(label: Text(member.role)),
                              onTap: () => _openMemberActions(member),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
