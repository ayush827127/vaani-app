import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/widgets/customer_avatar.dart';
import '../customer_ledger.dart';
import '../repositories/customer_repository.dart';
import '../../../l10n/l10n_extensions.dart';

/// Customers as a ledger: who owes money, who has credit with us, and a fast
/// way into each account. Search, filter and sort all run over the loaded
/// list in memory, so every keystroke or tap updates instantly.
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  List<Customer> _all = [];
  bool _isLoading = true;
  int _shopId = 1;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  LedgerFilter _filter = LedgerFilter.all;
  LedgerSort _sort = LedgerSort.recent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final customers = await getIt<CustomerRepository>().getAllCustomers(_shopId);
    if (!mounted) return;
    setState(() {
      _all = customers;
      _isLoading = false;
    });
  }

  String _sortLabel(LedgerSort s) {
    final l10n = context.l10n;
    switch (s) {
      case LedgerSort.recent:
        return l10n.sortRecent;
      case LedgerSort.oldest:
        return l10n.sortOldest;
      case LedgerSort.highestDue:
        return l10n.sortHighestDue;
      case LedgerSort.highestAdvance:
        return l10n.sortHighestAdvance;
      case LedgerSort.nameAZ:
        return l10n.sortNameAZ;
    }
  }

  String _filterLabel(LedgerFilter f) {
    final l10n = context.l10n;
    switch (f) {
      case LedgerFilter.all:
        return l10n.all;
      case LedgerFilter.withDue:
        return l10n.ledgerFilterWithDue;
      case LedgerFilter.withAdvance:
        return l10n.ledgerFilterWithAdvance;
      case LedgerFilter.settled:
        return l10n.ledgerFilterSettled;
    }
  }

  List<PopupMenuEntry<LedgerSort>> _sortItems(BuildContext context) {
    final c = context.colors;
    return [
      for (final s in LedgerSort.values)
        PopupMenuItem<LedgerSort>(
          value: s,
          child: Row(
            children: [
              Expanded(
                child: Text(_sortLabel(s),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: s == _sort ? FontWeight.w700 : FontWeight.w400,
                        color: s == _sort ? AppColors.primaryLight : c.textPrimary)),
              ),
              if (s == _sort)
                const Icon(Icons.check_rounded, size: 18, color: AppColors.primaryLight),
            ],
          ),
        ),
    ];
  }

  void _showAddCustomer() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final c = context.colors;
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (dialogCtx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(dialogCtx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.addCustomer, style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: c.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.nameRequired),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.phone),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final phone = phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim();
                // No DB-level uniqueness on phone — without this check the
                // same number could be saved on any number of customer
                // records with nothing anywhere to catch it.
                if (phone != null) {
                  final dup = await getIt<CustomerRepository>().getCustomerByPhone(_shopId, phone);
                  if (dup != null) {
                    if (dialogCtx.mounted) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                        content: Text('${dup.name} already has this phone number'),
                        backgroundColor: c.danger,
                      ));
                    }
                    return;
                  }
                }
                final customer = Customer(
                  shopId: _shopId,
                  name: nameCtrl.text.trim(),
                  phone: phone,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await getIt<CustomerRepository>().insertCustomer(customer);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                _load();
              },
              child: Text(l10n.addCustomer),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final summary = summarize(_all);
    final visible = applyLedgerView(_all, query: _query, filter: _filter, sort: _sort);
    int countFor(LedgerFilter f) => _all.where((x) => matchesFilter(x, f)).length;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.groups_rounded, size: 19, color: AppColors.primaryLight),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.customers,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary)),
                  Text(l10n.customersSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: l10n.search,
            onPressed: () => _searchFocus.requestFocus(),
          ),
          PopupMenuButton<LedgerSort>(
            icon: const Icon(Icons.tune_rounded),
            tooltip: l10n.sortLabel,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: _sortItems,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomer,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 24),
            Text(l10n.addLabel,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Key ledger figures, computed over every customer (not just the
          // ones currently searched/filtered) — tapping one jumps to that
          // group.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MetricCard(
                      amount: AppFormatters.formatCurrency(summary.totalDue),
                      label: l10n.totalDueLabel,
                      secondary: l10n.customersCount(summary.dueCount),
                      color: c.danger,
                      icon: Icons.arrow_upward_rounded,
                      onTap: () => setState(() => _filter = LedgerFilter.withDue),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      amount: AppFormatters.formatCurrency(summary.totalAdvance),
                      label: l10n.totalAdvanceLabel,
                      secondary: l10n.customersCount(summary.advanceCount),
                      color: c.success,
                      icon: Icons.arrow_downward_rounded,
                      onTap: () => setState(() => _filter = LedgerFilter.withAdvance),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.searchNameOrPhoneHint,
                hintStyle: TextStyle(color: c.textHint),
                prefixIcon: Icon(Icons.search_rounded, color: c.textHint),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded, color: c.textHint, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.inputBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.inputBorder)),
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in LedgerFilter.values) ...[
                  _FilterChip(
                    label: '${_filterLabel(f)} (${countFor(f)})',
                    active: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _filter == LedgerFilter.all
                        ? l10n.allCustomersHeading(visible.length)
                        : '${_filterLabel(_filter)} (${visible.length})',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary),
                  ),
                ),
                PopupMenuButton<LedgerSort>(
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: _sortItems,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_sortLabel(_sort),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLight)),
                        const Icon(Icons.arrow_drop_down_rounded,
                            size: 20, color: AppColors.primaryLight),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 60, color: c.textHint),
                            const SizedBox(height: 14),
                            Text(
                              _all.isEmpty ? l10n.noCustomersYet : l10n.noCustomersFound,
                              style: TextStyle(color: c.textSecondary),
                            ),
                            if (_all.isEmpty) ...[
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _showAddCustomer,
                                icon: const Icon(Icons.person_add_rounded),
                                label: Text(l10n.addCustomer),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          // Bottom padding keeps the last card clear of the
                          // floating Add button.
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _CustomerCard(
                            customer: visible[i],
                            onReturn: _load,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String amount;
  final String label;
  final String secondary;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _MetricCard({
    required this.amount,
    required this.label,
    required this.secondary,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(amount,
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
                    Text(secondary,
                        style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryLight : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primaryLight : c.inputBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : c.textPrimary),
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onReturn;
  const _CustomerCard({required this.customer, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final net = netBalance(customer);
    final recent = customer.lastVisit != null &&
        DateTime.now().difference(customer.lastVisit!).inDays <= 30;

    // ONE balance per customer, netted — and nothing at all when settled
    // (Settled exists only as a filter, never as a badge).
    Widget? balance;
    if (net != 0) {
      final isDue = net > 0;
      final color = isDue ? c.danger : c.success;
      balance = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isDue ? '↑' : '↓'} ${AppFormatters.formatCurrency(net.abs())}',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            Text(isDue ? l10n.due : l10n.advanceLabel,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await context.push('/customers/${customer.id}');
            onReturn();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomerAvatar(customer: customer, size: 44, color: AppColors.primary),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: recent ? c.success : c.textHint,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name,
                          style: TextStyle(
                              color: c.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.phone_rounded, size: 12, color: c.textHint),
                            const SizedBox(width: 5),
                            Text(customer.phone!,
                                style: TextStyle(color: c.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 12, color: c.textHint),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              customer.lastVisit != null
                                  ? AppFormatters.formatDate(customer.lastVisit!)
                                  : l10n.noPurchasesYet,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (balance != null) ...[
                  const SizedBox(width: 8),
                  balance,
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 22, color: c.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
