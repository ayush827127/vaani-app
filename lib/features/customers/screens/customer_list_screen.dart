import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/widgets/customer_avatar.dart';
import '../repositories/customer_repository.dart';
import '../../../l10n/l10n_extensions.dart';

/// Categorizes a customer for the filter tabs — purely a display-time
/// computation over fields the app already tracks (totalBills, createdAt,
/// lastVisit), no new data or business logic. A customer falls into exactly
/// one bucket so the tab counts stay intuitive: a lapsed repeat customer
/// reads as "Inactive" (the more actionable signal) rather than "Regular".
enum _CustomerCategory { regular, newCustomer, inactive, none }

_CustomerCategory _categorize(Customer c) {
  final now = DateTime.now();
  final daysSinceVisit = c.lastVisit != null ? now.difference(c.lastVisit!).inDays : null;
  final daysSinceCreated = now.difference(c.createdAt).inDays;

  if (c.totalBills > 0 && (daysSinceVisit == null || daysSinceVisit > 60)) {
    return _CustomerCategory.inactive;
  }
  if (daysSinceCreated <= 30) return _CustomerCategory.newCustomer;
  if (c.totalBills >= 2) return _CustomerCategory.regular;
  return _CustomerCategory.none;
}

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  List<Customer> _customers = [];
  bool _isLoading = true;
  int _shopId = 1;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  _CustomerCategory? _categoryFilter; // null = All

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final repo = getIt<CustomerRepository>();
    final customers = await repo.getAllCustomers(_shopId);
    setState(() {
      _customers = customers;
      _isLoading = false;
    });
  }

  // Was firing a full DB query on every keystroke — debounced so a query
  // only runs once typing pauses.
  void _search(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      _load();
      return;
    }
    final repo = getIt<CustomerRepository>();
    final results = await repo.searchCustomers(_shopId, q);
    if (mounted) setState(() => _customers = results);
  }

  List<Customer> get _visibleCustomers => _categoryFilter == null
      ? _customers
      : _customers.where((c) => _categorize(c) == _categoryFilter).toList();

  int _countFor(_CustomerCategory? category) => category == null
      ? _customers.length
      : _customers.where((c) => _categorize(c) == category).length;

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
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = _visibleCustomers;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: Text(l10n.customers),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomer,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.person_add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                hintStyle: TextStyle(color: c.textHint),
                prefixIcon: Icon(Icons.search_rounded, color: c.textHint),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.inputBorder)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
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
                _FilterChip(
                  label: l10n.customerFilterAll,
                  count: _countFor(null),
                  active: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l10n.customerFilterRegular,
                  count: _countFor(_CustomerCategory.regular),
                  active: _categoryFilter == _CustomerCategory.regular,
                  onTap: () => setState(() => _categoryFilter = _CustomerCategory.regular),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l10n.customerFilterNew,
                  count: _countFor(_CustomerCategory.newCustomer),
                  active: _categoryFilter == _CustomerCategory.newCustomer,
                  onTap: () => setState(() => _categoryFilter = _CustomerCategory.newCustomer),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l10n.customerFilterInactive,
                  count: _countFor(_CustomerCategory.inactive),
                  active: _categoryFilter == _CustomerCategory.inactive,
                  onTap: () => setState(() => _categoryFilter = _CustomerCategory.inactive),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 64, color: context.colors.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              _categoryFilter != null ? l10n.noMatchingBills : l10n.noCustomersYet,
                              style: TextStyle(color: context.colors.textSecondary),
                            ),
                            if (_categoryFilter == null) ...[
                              const SizedBox(height: 24),
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _CustomerCard(customer: visible[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.count, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryLight : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primaryLight : c.inputBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : c.textSecondary),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white.withValues(alpha: 0.8) : c.textHint),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  (Color, String)? _categoryBadge(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    switch (_categorize(customer)) {
      case _CustomerCategory.regular:
        return (AppColors.primaryLight, l10n.customerFilterRegular);
      case _CustomerCategory.newCustomer:
        return (c.success, l10n.customerFilterNew);
      case _CustomerCategory.inactive:
        return (c.warning, l10n.customerFilterInactive);
      case _CustomerCategory.none:
        return null;
    }
  }

  String _lastBillLabel(BuildContext context) {
    final l10n = context.l10n;
    if (customer.lastVisit == null) return l10n.noPurchasesYet;
    return l10n.lastVisit(AppFormatters.formatDate(customer.lastVisit!));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final badge = _categoryBadge(context);

    return InkWell(
      onTap: () => context.push('/customers/${customer.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomerAvatar(customer: customer, size: 46, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(customer.name,
                            style: TextStyle(color: c.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badge.$1.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(badge.$2,
                              style: TextStyle(
                                  color: badge.$1, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  if (customer.phone != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 12, color: c.textSecondary),
                        const SizedBox(width: 4),
                        Text(customer.phone!, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(_lastBillLabel(context),
                      style: TextStyle(color: c.textHint, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.formatCurrencyCompact(customer.totalPurchases),
                  style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(l10n.billsCountLabel(customer.totalBills),
                    style: TextStyle(color: c.textSecondary, fontSize: 11)),
                if (customer.totalOutstanding > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${l10n.outstanding} ${AppFormatters.formatCurrency(customer.totalOutstanding)}',
                      style: TextStyle(color: c.danger, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
