import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_transaction.dart';
import '../../../shared/widgets/app_card.dart';
import '../repositories/report_repository.dart';
import '../../inventory/repositories/item_repository.dart';
import '../../../shared/models/item.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../customers/customer_ledger.dart';
import '../../billing/repositories/payment_transaction_repository.dart';
import '../../../l10n/l10n_extensions.dart';
import 'package:go_router/go_router.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  int _shopId = 1;
  bool _isLoading = true;
  late final TabController _tabController;

  String _period = 'This Month'; // Today | This Week | This Month | Custom Range
  DateTime? _customStart;
  DateTime? _customEnd;

  SalesSummary _summary = const SalesSummary();
  SalesSummary _prevSummary = const SalesSummary();
  List<TopItem> _topItems = [];
  List<DailyData> _dailySales = [];
  List<CategorySales> _categorySales = [];
  List<Item> _lowStockItems = [];
  double _collections = 0;
  Map<String, double> _paymentModeBreakdown = {};
  List<PaymentTransaction> _recentPayments = [];
  List<Customer> _allCustomers = [];
  Map<int, Customer> _customersById = {};
  LedgerSummary _ledgerSummary = const LedgerSummary(totalDue: 0, dueCount: 0, totalAdvance: 0, advanceCount: 0);
  List<CustomerSales> _topCustomers = [];
  bool _showAllTopItems = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  (String, String) _dateRange() {
    final now = DateTime.now();
    switch (_period) {
      case 'Today':
        final d = AppFormatters.formatDbDate(now);
        return (d, d);
      case 'This Week':
        return (
          AppFormatters.formatDbDate(now.subtract(Duration(days: now.weekday - 1))),
          AppFormatters.formatDbDate(now)
        );
      case 'Custom Range':
        if (_customStart != null && _customEnd != null) {
          return (AppFormatters.formatDbDate(_customStart!), AppFormatters.formatDbDate(_customEnd!));
        }
        final d = AppFormatters.formatDbDate(now);
        return (d, d);
      default: // This Month
        return ('${now.year}-${now.month.toString().padLeft(2, '0')}-01', AppFormatters.formatDbDate(now));
    }
  }

  /// The immediately-preceding range of the same length as [start]..[end] —
  /// used only to phrase the Insights tab's "sales increased/decreased
  /// compared with the previous period" comparison.
  (String, String) _previousDateRange(String start, String end) {
    final s = DateTime.parse(start);
    final e = DateTime.parse(end);
    final lengthDays = e.difference(s).inDays + 1;
    final prevEnd = s.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: lengthDays - 1));
    return (AppFormatters.formatDbDate(prevStart), AppFormatters.formatDbDate(prevEnd));
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;

    final reportRepo = getIt<ReportRepository>();
    final itemRepo = getIt<ItemRepository>();
    final customerRepo = getIt<CustomerRepository>();
    final paymentRepo = getIt<PaymentTransactionRepository>();

    final (start, end) = _dateRange();
    final (prevStart, prevEnd) = _previousDateRange(start, end);

    final summary = await reportRepo.getPeriodSales(_shopId, start, end);
    final prevSummary = await reportRepo.getPeriodSales(_shopId, prevStart, prevEnd);
    final topItems = await reportRepo.getTopItems(_shopId, start, end, limit: 10);
    final dailySales = await reportRepo.getDailySales(_shopId, start, end);
    final categorySales = await reportRepo.getCategorySales(_shopId, start, end);
    final lowStockItems = await itemRepo.getLowStockItems(_shopId);
    final collections = await paymentRepo.getPeriodCollections(_shopId, start, end);
    final paymentModes = await paymentRepo.getPaymentModeBreakdown(_shopId, start, end);
    final recentPayments = await paymentRepo.getRecentByShop(
      _shopId,
      types: const ['bill_payment', 'outstanding_collection', 'advance_deposit'],
      limit: 8,
    );
    final allCustomers = await customerRepo.getAllCustomers(_shopId);
    final topCustomers = await reportRepo.getTopCustomers(_shopId, start, end, limit: 10);

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _prevSummary = prevSummary;
      _topItems = topItems;
      _dailySales = dailySales;
      _categorySales = categorySales;
      _lowStockItems = lowStockItems;
      _collections = collections;
      _paymentModeBreakdown = paymentModes;
      _recentPayments = recentPayments;
      _allCustomers = allCustomers;
      _customersById = {for (final c in allCustomers) if (c.id != null) c.id!: c};
      _ledgerSummary = summarize(allCustomers);
      _topCustomers = topCustomers;
      _showAllTopItems = false;
      _isLoading = false;
    });
  }

  int get _newCustomersInPeriod {
    final (start, end) = _dateRange();
    return _allCustomers.where((c) {
      final d = AppFormatters.formatDbDate(c.createdAt);
      return d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
    }).length;
  }

  List<Customer> get _topCustomersByDue {
    final withDue = _allCustomers.where((c) => netBalance(c) > 0).toList()
      ..sort((a, b) => netBalance(b).compareTo(netBalance(a)));
    return withDue.take(5).toList();
  }

  String _periodLabel(String period, AppLocalizations l10n) {
    switch (period) {
      case 'Today':
        return l10n.periodToday;
      case 'This Week':
        return l10n.periodThisWeek;
      case 'Custom Range':
        return l10n.periodCustomRange;
      default:
        return l10n.periodThisMonth;
    }
  }

  String _shortDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _periodDisplayLabel(AppLocalizations l10n) {
    if (_period == 'Custom Range' && _customStart != null && _customEnd != null) {
      return '${_shortDate(_customStart!)} - ${_shortDate(_customEnd!)}';
    }
    return _periodLabel(_period, l10n);
  }

  Future<void> _pickPeriod() async {
    final l10n = context.l10n;
    final c = context.colors;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: c.surfaceBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            for (final p in const ['Today', 'This Week', 'This Month', 'Custom Range'])
              ListTile(
                title: Text(_periodLabel(p, l10n), style: TextStyle(color: c.textPrimary)),
                trailing: _period == p ? const Icon(Icons.check_rounded, color: AppColors.primaryLight) : null,
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    if (selected == 'Custom Range') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _customStart != null && _customEnd != null
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : DateTimeRange(start: DateTime.now().subtract(const Duration(days: 6)), end: DateTime.now()),
      );
      if (range == null || !mounted) return;
      setState(() {
        _period = 'Custom Range';
        _customStart = range.start;
        _customEnd = range.end;
      });
    } else {
      setState(() => _period = selected);
    }
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(l10n.reports),
        actions: [
          InkWell(
            onTap: _pickPeriod,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_periodDisplayLabel(l10n),
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w600)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primaryLight),
              ]),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: c.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primaryLight,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: l10n.tabOverview),
                Tab(text: l10n.tabSales),
                Tab(text: l10n.tabItems),
                Tab(text: l10n.tabPayments),
                Tab(text: l10n.tabCustomers),
                Tab(text: l10n.tabInsights),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildSalesTab(),
                _buildItemsTab(),
                _buildPaymentsTab(),
                _buildCustomersTab(),
                _buildInsightsTab(),
              ],
            ),
    );
  }

  // ── Shared small pieces ──────────────────────────────────────────────

  Widget _emptyState(AppSemanticColors c, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.surfaceBorder)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 34, color: c.textSecondary),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(color: c.textSecondary, fontSize: 13)),
      ]),
    );
  }

  Widget _cardWrap(AppSemanticColors c, {Color? borderColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? c.surfaceBorder),
      ),
      child: child,
    );
  }

  Widget _cardTitle(AppSemanticColors c, String text) => Text(text,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary));

  Widget _summaryRow(AppSemanticColors c, String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast ? null : BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
        Text(value, style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _rankBadge(AppSemanticColors c, int rank) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: rank == 1 ? c.warning.withValues(alpha: 0.2) : c.divider, shape: BoxShape.circle),
      child: Center(
        child: Text('$rank',
            style: TextStyle(color: rank == 1 ? c.warning : c.textHint, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _metricPairs(List<Widget> cards) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: cards[i]),
        const SizedBox(width: 12),
        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
      ]));
      if (i + 2 < cards.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  Widget _buildMoneyAtGlanceCard(AppSemanticColors c, AppLocalizations l10n) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.moneyAtGlanceLabel),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _StatBlock(
                  label: l10n.toCollectLabel,
                  value: AppFormatters.formatCurrency(_ledgerSummary.totalDue),
                  color: c.success)),
          Container(width: 1, height: 40, color: c.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _StatBlock(
                  label: l10n.toPayLabel,
                  value: AppFormatters.formatCurrency(_ledgerSummary.totalAdvance),
                  color: c.warning)),
        ]),
      ],
    ));
  }

  Widget _buildSalesSummaryCard(AppSemanticColors c, AppLocalizations l10n, double avgBill) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.salesSummaryLabel),
        const SizedBox(height: 6),
        _summaryRow(c, l10n.totalSales, AppFormatters.formatCurrency(_summary.totalSales)),
        _summaryRow(c, l10n.totalProfit, AppFormatters.formatCurrency(_summary.totalProfit)),
        _summaryRow(c, l10n.totalBills, '${_summary.totalBills}'),
        _summaryRow(c, l10n.averageBillValueLabel, AppFormatters.formatCurrency(avgBill)),
        _summaryRow(c, l10n.collectionsLabel, AppFormatters.formatCurrency(_collections)),
        _summaryRow(c, l10n.pendingAmountLabel, AppFormatters.formatCurrency(_ledgerSummary.totalDue), isLast: true),
      ],
    ));
  }

  // ── Overview tab ──────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    final c = context.colors;
    final l10n = context.l10n;
    final avgBill = _summary.totalBills > 0 ? _summary.totalSales / _summary.totalBills : 0.0;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _metricPairs([
            MetricCard(
                title: l10n.totalSales,
                value: AppFormatters.formatCurrency(_summary.totalSales),
                icon: Icons.currency_rupee_rounded,
                accentColor: AppColors.primaryLight),
            MetricCard(
                title: l10n.totalProfit,
                value: AppFormatters.formatCurrency(_summary.totalProfit),
                icon: Icons.trending_up_rounded,
                accentColor: AppColors.success),
            MetricCard(
                title: l10n.totalBills,
                value: '${_summary.totalBills}',
                icon: Icons.receipt_rounded,
                accentColor: AppColors.info),
            MetricCard(
                title: l10n.itemsSold,
                value: '${_summary.totalItemsSold}',
                icon: Icons.shopping_bag_rounded,
                accentColor: AppColors.warning),
            MetricCard(
                title: l10n.collectionsLabel,
                value: AppFormatters.formatCurrency(_collections),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: AppColors.success),
            MetricCard(
                title: l10n.amountToCollectLabel,
                value: AppFormatters.formatCurrency(_ledgerSummary.totalDue),
                icon: Icons.request_page_rounded,
                accentColor: AppColors.warning),
          ]),
          const SizedBox(height: 16),
          _buildMoneyAtGlanceCard(c, l10n),
          const SizedBox(height: 16),
          _buildSalesSummaryCard(c, l10n, avgBill),
        ],
      ),
    );
  }

  // ── Sales tab ─────────────────────────────────────────────────────────

  Widget _buildSalesTab() {
    final c = context.colors;
    final l10n = context.l10n;
    final avgBill = _summary.totalBills > 0 ? _summary.totalSales / _summary.totalBills : 0.0;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_dailySales.isEmpty)
            _emptyState(c, Icons.show_chart_rounded, l10n.noSalesYet)
          else
            _buildSalesTrendCard(c, l10n),
          const SizedBox(height: 16),
          _buildSalesSummaryCard(c, l10n, avgBill),
          if (_dailySales.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDailySalesCard(c, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildSalesTrendCard(AppSemanticColors c, AppLocalizations l10n) {
    final spots = _dailySales.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sales)).toList();
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.salesTrendLabel),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                getDrawingHorizontalLine: (_) => FlLine(color: c.divider, strokeWidth: 1),
                drawVerticalLine: false,
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, _) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= _dailySales.length) return const SizedBox.shrink();
                      final date = _dailySales[idx].date;
                      final day = date.length >= 10 ? date.substring(8) : '';
                      return Text(day, style: TextStyle(color: c.textSecondary, fontSize: 10));
                    },
                    interval: (_dailySales.length / 5).ceil().clamp(1, 999).toDouble(),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.primaryLight,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppColors.primaryLight.withValues(alpha: 0.1)),
                ),
              ],
            ),
          ),
        ),
      ],
    ));
  }

  String _dayLabel(String isoDate, AppLocalizations l10n) {
    final today = AppFormatters.formatDbDate(DateTime.now());
    final yesterday = AppFormatters.formatDbDate(DateTime.now().subtract(const Duration(days: 1)));
    if (isoDate == today) return l10n.today;
    if (isoDate == yesterday) return l10n.yesterdayLabel;
    return _shortDate(DateTime.parse(isoDate));
  }

  Widget _buildDailySalesCard(AppSemanticColors c, AppLocalizations l10n) {
    final reversed = _dailySales.reversed.toList();
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.dailySalesLabel),
        const SizedBox(height: 6),
        for (var i = 0; i < reversed.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
            child: Row(children: [
              Expanded(
                child: Text(_dayLabel(reversed[i].date, l10n),
                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500)),
              ),
              Text(AppFormatters.formatCurrency(reversed[i].sales),
                  style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              SizedBox(
                width: 62,
                child: Text(
                  reversed[i].bills == 1 ? '1 bill' : '${reversed[i].bills} bills',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ),
            ]),
          ),
      ],
    ));
  }

  // ── Items tab ─────────────────────────────────────────────────────────

  Widget _buildItemsTab() {
    final c = context.colors;
    final l10n = context.l10n;
    final shown = _showAllTopItems ? _topItems : _topItems.take(5).toList();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_topItems.isEmpty)
            _emptyState(c, Icons.inventory_2_outlined, l10n.noItemSalesYet)
          else
            _buildTopItemsCard(c, l10n, shown),
          if (_categorySales.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCategorySalesCard(c, l10n),
          ],
          if (_lowStockItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildLowStockCard(c, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildTopItemsCard(AppSemanticColors c, AppLocalizations l10n, List<TopItem> items) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _cardTitle(c, l10n.topItems),
            if (!_showAllTopItems && _topItems.length > 5)
              TextButton(
                onPressed: () => setState(() => _showAllTopItems = true),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(l10n.viewAll,
                      style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.primaryLight),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((e) {
          final item = e.value;
          final rank = e.key + 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _rankBadge(c, rank),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        l10n.unitsSoldSummary('${item.totalQty}', AppFormatters.formatCurrency(item.totalRevenue)),
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: c.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(l10n.pcsCount('${item.totalQty}'),
                      style: TextStyle(color: c.success, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }),
      ],
    ));
  }

  Widget _buildCategorySalesCard(AppSemanticColors c, AppLocalizations l10n) {
    final total = _categorySales.fold<double>(0, (s, e) => s + e.revenue);
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.salesByCategoryLabel),
        const SizedBox(height: 14),
        for (final cat in _categorySales)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(cat.category.isEmpty ? l10n.uncategorized : localizedCategory(l10n, cat.category),
                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(AppFormatters.formatCurrency(cat.revenue),
                        style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(total > 0 ? '${(cat.revenue / total * 100).toStringAsFixed(0)}%' : '0%',
                          textAlign: TextAlign.right, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? (cat.revenue / total).clamp(0.0, 1.0) : 0,
                    minHeight: 6,
                    backgroundColor: c.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primaryLight),
                  ),
                ),
              ],
            ),
          ),
      ],
    ));
  }

  Widget _buildLowStockCard(AppSemanticColors c, AppLocalizations l10n) {
    final items = _lowStockItems.take(5).toList();
    return _cardWrap(
      c,
      borderColor: c.warning.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
            const SizedBox(width: 8),
            _cardTitle(c, l10n.lowStockItemsLabel),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(items[i].name,
                        style: TextStyle(color: c.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${items[i].stockQuantity} / ${items[i].reorderLevel}',
                      style: TextStyle(color: c.warning, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Payments tab ──────────────────────────────────────────────────────

  Widget _buildPaymentsTab() {
    final c = context.colors;
    final l10n = context.l10n;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPaymentModeCard(c, l10n),
          const SizedBox(height: 16),
          _buildCollectionVsPendingCard(c, l10n),
          const SizedBox(height: 16),
          if (_recentPayments.isEmpty)
            _emptyState(c, Icons.payments_outlined, l10n.noPaymentsRecordedYet)
          else
            _buildRecentPaymentsCard(c, l10n),
        ],
      ),
    );
  }

  Widget _buildPaymentModeCard(AppSemanticColors c, AppLocalizations l10n) {
    final total = _paymentModeBreakdown.values.fold<double>(0, (s, v) => s + v);
    final entries = _paymentModeBreakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.paymentSummaryLabel),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          Text(l10n.noPaymentsRecordedYet, style: TextStyle(color: c.textSecondary, fontSize: 13))
        else
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(localizedPaymentMode(l10n, e.key),
                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(AppFormatters.formatCurrency(e.value),
                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? (e.value / total).clamp(0.0, 1.0) : 0,
                      minHeight: 6,
                      backgroundColor: c.divider,
                      valueColor: const AlwaysStoppedAnimation(AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
      ],
    ));
  }

  Widget _buildCollectionVsPendingCard(AppSemanticColors c, AppLocalizations l10n) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.collectionVsPendingLabel),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _StatBlock(
                  label: l10n.collectedLabel, value: AppFormatters.formatCurrency(_collections), color: c.success)),
          Container(width: 1, height: 40, color: c.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _StatBlock(
                  label: l10n.pendingAmountLabel,
                  value: AppFormatters.formatCurrency(_ledgerSummary.totalDue),
                  color: c.warning)),
        ]),
      ],
    ));
  }

  String _formatDateTime(DateTime dt, AppLocalizations l10n) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    if (isToday) return '${l10n.today}, $h:$m $ampm';
    return '${_shortDate(dt)}, $h:$m $ampm';
  }

  Widget _buildRecentPaymentsCard(AppSemanticColors c, AppLocalizations l10n) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.recentPaymentsLabel),
        const SizedBox(height: 6),
        for (var i = 0; i < _recentPayments.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_customersById[_recentPayments[i].customerId]?.name ?? l10n.walkInCustomer,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(_formatDateTime(_recentPayments[i].createdAt, l10n),
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(AppFormatters.formatCurrency(_recentPayments[i].amount),
                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(l10n.received, style: TextStyle(color: c.success, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
      ],
    ));
  }

  // ── Customers tab ─────────────────────────────────────────────────────

  Widget _buildCustomersTab() {
    final c = context.colors;
    final l10n = context.l10n;
    final topDue = _topCustomersByDue;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCustomerSummaryCard(c, l10n),
          const SizedBox(height: 16),
          if (_topCustomers.isEmpty)
            _emptyState(c, Icons.people_outline_rounded, l10n.noSalesYet)
          else
            _buildTopCustomersBySalesCard(c, l10n),
          const SizedBox(height: 16),
          if (topDue.isEmpty)
            _emptyState(c, Icons.check_circle_outline_rounded, l10n.noCustomerDuesYet)
          else
            _buildTopCustomersByDueCard(c, l10n, topDue),
        ],
      ),
    );
  }

  Widget _buildCustomerSummaryCard(AppSemanticColors c, AppLocalizations l10n) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.customerSummaryLabel),
        const SizedBox(height: 6),
        _summaryRow(c, l10n.totalCustomersLabel, '${_allCustomers.length}'),
        _summaryRow(c, l10n.newCustomers, '$_newCustomersInPeriod'),
        _summaryRow(c, l10n.customersWithDuesLabel, '${_ledgerSummary.dueCount}'),
        _summaryRow(c, l10n.totalDuesLabel, AppFormatters.formatCurrency(_ledgerSummary.totalDue), isLast: true),
      ],
    ));
  }

  Widget _buildTopCustomersBySalesCard(AppSemanticColors c, AppLocalizations l10n) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.topCustomersBySalesLabel),
        const SizedBox(height: 12),
        for (var i = 0; i < _topCustomers.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
            child: Row(children: [
              _rankBadge(c, i + 1),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_topCustomers[i].customerName,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      _topCustomers[i].totalBills == 1 ? '1 bill' : '${_topCustomers[i].totalBills} bills',
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Text(AppFormatters.formatCurrency(_topCustomers[i].totalSales),
                  style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
            ]),
          ),
      ],
    ));
  }

  Widget _buildTopCustomersByDueCard(AppSemanticColors c, AppLocalizations l10n, List<Customer> list) {
    return _cardWrap(c, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardTitle(c, l10n.topCustomersByDueLabel),
        const SizedBox(height: 12),
        for (var i = 0; i < list.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(list[i].name,
                      style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text(AppFormatters.formatCurrency(netBalance(list[i])),
                    style: TextStyle(color: c.warning, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    ));
  }

  // ── Insights tab ──────────────────────────────────────────────────────

  List<String> _computeInsights(AppLocalizations l10n) {
    final list = <String>[];
    if (_summary.totalBills == 0) return list;

    if (_prevSummary.totalSales > 0) {
      final change = ((_summary.totalSales - _prevSummary.totalSales) / _prevSummary.totalSales) * 100;
      if (change.abs() >= 1) {
        list.add(change >= 0
            ? l10n.insightSalesIncreased(change.toStringAsFixed(1))
            : l10n.insightSalesDecreased(change.abs().toStringAsFixed(1)));
      }
    }
    if (_topItems.isNotEmpty) list.add(l10n.insightTopItem(_topItems.first.name));
    final avgBill = _summary.totalBills > 0 ? _summary.totalSales / _summary.totalBills : 0.0;
    list.add(l10n.insightAvgBillValue(AppFormatters.formatCurrency(avgBill)));
    list.add(l10n.insightBillCount('${_summary.totalBills}'));
    if (_ledgerSummary.totalDue > 0) list.add(l10n.insightPending(AppFormatters.formatCurrency(_ledgerSummary.totalDue)));
    final categorised = _categorySales.where((cat) => cat.category.isNotEmpty).toList();
    if (categorised.isNotEmpty) list.add(l10n.insightTopCategory(localizedCategory(l10n, categorised.first.category)));
    return list;
  }

  Widget _buildInsightsTab() {
    final c = context.colors;
    final l10n = context.l10n;
    final insights = _computeInsights(l10n);
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (insights.isEmpty)
            _emptyState(c, Icons.insights_rounded, l10n.noInsightsYet)
          else
            _cardWrap(c, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < insights.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i < insights.length - 1 ? 14 : 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: AppColors.primaryLight.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: const Icon(Icons.lightbulb_rounded, size: 15, color: AppColors.primaryLight),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(insights[i], style: TextStyle(color: c.textPrimary, fontSize: 13.5, height: 1.35)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )),
        ],
      ),
    );
  }
}

// ── Stat block (You'll Get/Give, Collected/Pending) ─────────────────────────

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBlock({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 9.5, color: c.textHint, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
