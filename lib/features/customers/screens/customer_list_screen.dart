import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../repositories/customer_repository.dart';
import '../../../l10n/l10n_extensions.dart';

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
    final l10n = context.l10n;
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
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : _customers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 64, color: context.colors.textSecondary),
                            const SizedBox(height: 16),
                            Text(l10n.noCustomersYet, style: TextStyle(color: context.colors.textSecondary)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showAddCustomer,
                              icon: const Icon(Icons.person_add_rounded),
                              label: Text(l10n.addCustomer),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final cust = _customers[i];
                            final sc = context.colors;
                            return GestureDetector(
                              onTap: () => context.push('/customers/${cust.id}'),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: sc.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: sc.surfaceBorder),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: AppColors.primary.withOpacity(0.3),
                                      child: Text(
                                        cust.name[0].toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(cust.name, style: TextStyle(color: sc.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                                          if (cust.phone != null)
                                            Text(cust.phone!, style: TextStyle(color: sc.textSecondary, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          AppFormatters.formatCurrencyCompact(cust.totalPurchases),
                                          style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Text(l10n.billsCountLabel('${cust.totalBills}'), style: TextStyle(color: sc.textSecondary, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
