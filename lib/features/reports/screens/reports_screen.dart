import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/widgets/app_card.dart';
import '../repositories/report_repository.dart';
import '../../../l10n/l10n_extensions.dart';
import 'package:go_router/go_router.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _shopId = 1;
  bool _isLoading = true;
  String _period = 'This Month';
  SalesSummary? _summary;
  List<TopProduct> _topProducts = [];
  List<DailyData> _chartData = [];

  final _periods = ['Today', 'This Week', 'This Month', 'This Year'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;

    final repo = getIt<ReportRepository>();
    final now = DateTime.now();
    String start, end;

    switch (_period) {
      case 'Today':
        start = end = AppFormatters.formatDbDate(now);
        break;
      case 'This Week':
        start = AppFormatters.formatDbDate(now.subtract(Duration(days: now.weekday - 1)));
        end = AppFormatters.formatDbDate(now);
        break;
      case 'This Year':
        start = '${now.year}-01-01';
        end = AppFormatters.formatDbDate(now);
        break;
      default: // This Month
        start = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        end = AppFormatters.formatDbDate(now);
    }

    final summary = await repo.getPeriodSales(_shopId, start, end);
    final topProducts = await repo.getTopProducts(_shopId, start, end);
    final chart = await repo.getMonthSales(_shopId);

    setState(() {
      _summary = summary;
      _topProducts = topProducts;
      _chartData = chart;
      _isLoading = false;
    });
  }

  String _periodLabel(String period, AppLocalizations l10n) {
    switch (period) {
      case 'Today':
        return l10n.periodToday;
      case 'This Week':
        return l10n.periodThisWeek;
      case 'This Year':
        return l10n.periodThisYear;
      default:
        return l10n.periodThisMonth;
    }
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
        title: Text(l10n.reports),
        actions: [
          DropdownButton<String>(
            value: _period,
            underline: const SizedBox(),
            dropdownColor: context.colors.surface,
            style: const TextStyle(color: AppColors.primaryLight, fontSize: 13),
            items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(_periodLabel(p, l10n)))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _period = v);
                _loadData();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary cards
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: l10n.totalSales,
                          value: AppFormatters.formatCurrency(_summary?.totalSales ?? 0),
                          icon: Icons.currency_rupee_rounded,
                          accentColor: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricCard(
                          title: l10n.totalProfit,
                          value: AppFormatters.formatCurrency(_summary?.totalProfit ?? 0),
                          icon: Icons.trending_up_rounded,
                          accentColor: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: l10n.totalBills,
                          value: '${_summary?.totalBills ?? 0}',
                          icon: Icons.receipt_rounded,
                          accentColor: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricCard(
                          title: l10n.itemsSold,
                          value: '${_summary?.totalItemsSold ?? 0}',
                          icon: Icons.shopping_bag_rounded,
                          accentColor: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sales chart
                  if (_chartData.isNotEmpty) _buildChart(),
                  const SizedBox(height: 16),
                  // Top products
                  if (_topProducts.isNotEmpty) _buildTopProducts(),
                ],
              ),
            ),
    );
  }

  Widget _buildChart() {
    final c = context.colors;
    final spots = _chartData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sales)).toList();
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
          Text(context.l10n.salesOverview, style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
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
                        if (idx < 0 || idx >= _chartData.length) return const SizedBox.shrink();
                        final date = _chartData[idx].date;
                        final day = date.substring(8);
                        return Text(day, style: TextStyle(color: c.textSecondary, fontSize: 10));
                      },
                      interval: (_chartData.length / 5).ceil().toDouble(),
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
                    belowBarData: BarAreaData(show: true, color: AppColors.primaryLight.withOpacity(0.1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProducts() {
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
          Text(l10n.topProducts, style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
          const SizedBox(height: 16),
          ..._topProducts.take(5).toList().asMap().entries.map((e) {
            final product = e.value;
            final rank = e.key + 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? c.warning.withOpacity(0.2)
                          : c.divider,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: rank == 1 ? c.warning : c.textHint,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name, style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                        Text(
                          l10n.unitsSoldSummary('${product.totalQty}', AppFormatters.formatCurrency(product.totalRevenue)),
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.pcsCount('${product.totalQty}'),
                      style: TextStyle(color: c.success, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
