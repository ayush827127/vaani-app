import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/invoice.dart';
import '../../reports/repositories/report_repository.dart';
import '../../inventory/repositories/product_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../../../shared/widgets/hamburger_icon.dart';
import '../../../shared/widgets/shell_scaffold_key.dart';
import '../../../l10n/l10n_extensions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _shopId = 1;
  String _ownerName = '';
  String _shopName = '';
  String? _logoPath;
  bool _isLoading = true;

  SalesSummary? _todaySummary;
  SalesSummary? _yesterdaySummary;
  int _todayBills = 0;
  int _newCustomers = 0;
  List<DailyData> _chartData = [];
  int _lowStockCount = 0;
  List<Invoice> _recentBills = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;

    // Picks up whatever DataSyncRepository.syncNow() last wrote to the
    // subscription cache (manual sync, periodic background sync, etc.) —
    // that repository has no Riverpod ref of its own to push updates here.
    unawaited(ref.read(subscriptionProvider.notifier).reloadFromCache());

    final shop = await getIt<ShopRepository>().getShop();

    final reportRepo = getIt<ReportRepository>();
    final productRepo = getIt<ProductRepository>();
    final customerRepo = getIt<CustomerRepository>();
    final invoiceRepo = getIt<InvoiceRepository>();

    final today = await reportRepo.getTodaySummary(_shopId);
    final yesterday = await reportRepo.getYesterdaySummary(_shopId);
    final chart = await reportRepo.getLast7DaysSales(_shopId);
    final bills = await invoiceRepo.getTodayBillCount(_shopId);
    final newCustomers = await customerRepo.getNewCustomersThisMonth(_shopId);
    final lowStock = await productRepo.getLowStockProducts(_shopId);
    final recentBills = await invoiceRepo.getInvoicesByShop(_shopId, limit: 3);

    if (!mounted) return;
    setState(() {
      _ownerName = shop?.ownerName ?? '';
      _shopName = shop?.name ?? '';
      _logoPath = shop?.logoPath;
      _todaySummary = today;
      _yesterdaySummary = yesterday;
      _chartData = chart;
      _todayBills = bills;
      _newCustomers = newCustomers;
      _lowStockCount = lowStock.length;
      _recentBills = recentBills;
      _isLoading = false;
    });
  }

  double get _growthPercent {
    if (_yesterdaySummary == null || _yesterdaySummary!.totalSales == 0) return 0;
    return ((_todaySummary!.totalSales - _yesterdaySummary!.totalSales) /
            _yesterdaySummary!.totalSales) *
        100;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),
                    _buildSalesCard(),
                    const SizedBox(height: 16),
                    _buildMetricsRow(),
                    const SizedBox(height: 16),
                    _buildRecentBills(),
                    const SizedBox(height: 16),
                    _buildQuickActions(),
                    const SizedBox(height: 16),
                    _buildChart(),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final c = context.colors;
    final l10n = context.l10n;
    final initial = _ownerName.isNotEmpty ? _ownerName[0].toUpperCase() : 'U';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 8, 0),
      child: Row(
        children: [
          // Hamburger menu
          IconButton(
            icon: const HamburgerIcon(),
            onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppFormatters.getGreeting(morning: l10n.greetingMorning, afternoon: l10n.greetingAfternoon, evening: l10n.greetingEvening)}, '
                  '${_ownerName.isNotEmpty ? _ownerName.split(' ').first : l10n.greetingFallbackName} '
                  '${AppFormatters.getGreetingEmoji()}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _shopName.isNotEmpty ? _shopName : l10n.homeSubtitleFallback,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          // Low-stock badge
          if (_lowStockCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.danger.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Icon(Icons.warning_rounded, size: 14, color: c.danger),
                const SizedBox(width: 4),
                Text(l10n.lowStockBadge('$_lowStockCount'),
                    style: TextStyle(fontSize: 11, color: c.danger)),
              ]),
            ),
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: c.textSecondary),
            onPressed: () => context.push('/notifications'),
          ),
          GestureDetector(
            onTap: () => context.push('/profile').then((_) => _loadData()),
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryLight, width: 1.5),
              ),
              child: ClipOval(
                child: _logoPath != null && _logoPath!.isNotEmpty && File(_logoPath!).existsSync()
                    ? Image.file(File(_logoPath!), width: 38, height: 38, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                              child: Text(initial,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                            ))
                    : Center(
                        child: Text(initial,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's Sales Card ────────────────────────────────────────────────────

  Widget _buildSalesCard() {
    final growth = _growthPercent;
    final isPositive = growth >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: context.colors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.todaysSales, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            AppFormatters.formatCurrency(_todaySummary?.totalSales ?? 0),
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(
                  isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 14,
                  color: isPositive ? AppColors.successLight : AppColors.errorLight,
                ),
                const SizedBox(width: 4),
                Text(
                  AppFormatters.formatGrowth(growth),
                  style: TextStyle(
                      fontSize: 12,
                      color: isPositive ? AppColors.successLight : AppColors.errorLight,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Text(context.l10n.fromYesterday, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
        ],
      ),
    );
  }

  // ── Metrics Row ───────────────────────────────────────────────────────────

  Widget _buildMetricsRow() {
    final c = context.colors;
    final l10n = context.l10n;
    return Row(children: [
      Expanded(
          child: _MetricTile(
              title: l10n.bills, value: '$_todayBills', icon: Icons.receipt_rounded, color: c.info)),
      const SizedBox(width: 12),
      Expanded(
          child: _MetricTile(
              title: l10n.newCustomers,
              value: '$_newCustomers',
              icon: Icons.person_add_rounded,
              color: c.success)),
      const SizedBox(width: 12),
      Expanded(
          child: _MetricTile(
              title: l10n.todaysProfit,
              value: AppFormatters.formatCurrencyCompact(_todaySummary?.totalProfit ?? 0),
              icon: Icons.trending_up_rounded,
              color: c.warning)),
    ]);
  }

  // ── Recent Bills ──────────────────────────────────────────────────────────

  Widget _buildRecentBills() {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.recentBills,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
              TextButton(
                onPressed: () => context.go('/bills'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.viewAll,
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (_recentBills.isEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Column(children: [
                Icon(Icons.receipt_long_outlined, size: 36, color: c.textSecondary),
                const SizedBox(height: 8),
                Text(l10n.noBillsToday,
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 8),
          ] else
            ...(_recentBills.map((bill) => _BillTile(
                  bill: bill,
                  onTap: () => context.push('/bills/${bill.id}'),
                ))),
        ],
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final c = context.colors;
    final l10n = context.l10n;
    ref.watch(subscriptionProvider); // rebuild this section when status changes
    final subscription = ref.read(subscriptionProvider.notifier);

    Widget gated({
      required String moduleKey,
      required String label,
      required IconData icon,
      required VoidCallback onTap,
      Color? color,
    }) {
      final enabled = subscription.isModuleEnabled(moduleKey);
      return _QuickAction(
        icon: icon,
        label: label,
        color: color,
        enabled: enabled,
        onTap: enabled
            ? onTap
            : () => _showUpgradeMessage(label),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.quickActions,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 90,
          ),
          children: [
            gated(moduleKey: 'billing',    icon: Icons.receipt_long_rounded, label: l10n.newBill,   onTap: () => context.go('/billing')),
            gated(moduleKey: 'inventory',  icon: Icons.inventory_2_rounded,  label: l10n.products,  onTap: () => context.go('/inventory')),
            gated(moduleKey: 'customers',  icon: Icons.people_rounded,       label: l10n.customers, onTap: () => context.go('/customers')),
            gated(moduleKey: 'inventory',  icon: Icons.add_box_rounded,      label: l10n.addProduct, onTap: () => context.push('/inventory/add')),
            gated(moduleKey: 'reports',    icon: Icons.bar_chart_rounded,    label: l10n.reports,    onTap: () => context.go('/reports')),
            gated(moduleKey: 'ai_manager', icon: Icons.smart_toy_rounded,    label: l10n.aiManager,  color: AppColors.primaryLight, onTap: () => context.go('/ai-manager')),
          ],
        ),
      ],
    );
  }

  void _showUpgradeMessage(String moduleLabel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Upgrade your plan to unlock $moduleLabel'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // ── 7-Day Revenue Chart ───────────────────────────────────────────────────

  Widget _buildChart() {
    if (_chartData.isEmpty) return const SizedBox.shrink();
    final spots = _chartData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.sales))
        .toList();

    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.sevenDayRevenue,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
              TextButton(
                onPressed: () => context.go('/reports'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.viewReports,
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 108, // reduced ~23% from 140
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primaryLight,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent Bill Tile ──────────────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  final Invoice bill;
  final VoidCallback? onTap;
  const _BillTile({required this.bill, this.onTap});

  Color? _paymentColor(String mode, AppSemanticColors c) {
    switch (mode) {
      case 'cash':
        return c.success;
      case 'upi':
        return c.info;
      case 'card':
        return c.warning;
      case 'credit':
        return const Color(0xFFEC4899);
      default:
        return null;
    }
  }

  String _formatTime(DateTime dt, String todayLabel) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    if (isToday) return '$todayLabel $h:$m $ampm';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final modeColor = _paymentColor(bill.paymentMode, c) ?? c.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.receipt_rounded, size: 18, color: AppColors.primaryLight),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bill.invoiceNumber,
                style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            Text(
              '${bill.customerName} · ${_formatTime(bill.createdAt, l10n.today)}',
              style: TextStyle(color: c.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            AppFormatters.formatCurrency(bill.grandTotal),
            style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              localizedPaymentMode(l10n, bill.paymentMode).toUpperCase(),
              style: TextStyle(color: modeColor, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ]),
      ),
    );
  }
}

// ── Metric Tile ───────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricTile({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: c.textPrimary)),
        Text(title, style: TextStyle(fontSize: 10, color: c.textSecondary)),
      ]),
    );
  }
}

// ── Quick Action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.surfaceBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: color ?? AppColors.primaryLight),
                  const SizedBox(height: 6),
                  Text(label,
                      style: TextStyle(fontSize: 10, color: c.textSecondary),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!enabled)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}
