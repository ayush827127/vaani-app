import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/widgets/shop_logo_image.dart';
import '../../reports/repositories/report_repository.dart';
import '../../inventory/repositories/item_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../customers/customer_ledger.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../billing/repositories/payment_transaction_repository.dart';
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
  String? _logoUrl;
  bool _isLoading = true;

  SalesSummary? _todaySummary;
  SalesSummary? _yesterdaySummary;
  int _todayBills = 0;
  double _todayCollections = 0;
  int _lowStockCount = 0;
  LedgerSummary _ledgerSummary = const LedgerSummary(totalDue: 0, dueCount: 0, totalAdvance: 0, advanceCount: 0);
  List<_ActivityEntry> _recentActivity = [];

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
    final itemRepo = getIt<ItemRepository>();
    final customerRepo = getIt<CustomerRepository>();
    final invoiceRepo = getIt<InvoiceRepository>();
    final paymentRepo = getIt<PaymentTransactionRepository>();

    final today = await reportRepo.getTodaySummary(_shopId);
    final yesterday = await reportRepo.getYesterdaySummary(_shopId);
    final bills = await invoiceRepo.getTodayBillCount(_shopId);
    final collections = await paymentRepo.getTodayCollections(_shopId);
    final lowStock = await itemRepo.getLowStockItems(_shopId);
    final customers = await customerRepo.getAllCustomers(_shopId);
    final ledger = summarize(customers);

    // Recent Activity merges two existing event sources — new bills, and
    // standalone ledger movements that aren't just a bill's own payment
    // (see getRecentByShop's doc comment for why 'bill_payment' is left
    // out: it would just duplicate the bill's own "Bill created" entry).
    final customersById = {for (final c in customers) if (c.id != null) c.id!: c};
    final recentInvoices = await invoiceRepo.getInvoicesByShopWithItemCounts(_shopId, limit: 5);
    final recentTxns = await paymentRepo.getRecentByShop(
      _shopId,
      types: const ['outstanding_collection', 'advance_deposit', 'manual_credit', 'refund'],
      limit: 5,
    );
    final activity = <_ActivityEntry>[
      for (final inv in recentInvoices)
        _ActivityEntry(
          type: _ActivityType.billCreated,
          customerName: inv.customerName,
          amount: inv.grandTotal,
          createdAt: inv.createdAt,
        ),
      for (final txn in recentTxns)
        _ActivityEntry(
          type: switch (txn.type) {
            'manual_credit' => _ActivityType.creditGiven,
            'refund' => _ActivityType.paymentMade,
            _ => _ActivityType.paymentReceived,
          },
          customerName: customersById[txn.customerId]?.name,
          amount: txn.amount,
          createdAt: txn.createdAt,
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!mounted) return;
    setState(() {
      _ownerName = shop?.ownerName ?? '';
      _shopName = shop?.name ?? '';
      _logoPath = shop?.logoPath;
      _logoUrl = shop?.logoUrl;
      _todaySummary = today;
      _yesterdaySummary = yesterday;
      _todayBills = bills;
      _todayCollections = collections;
      _lowStockCount = lowStock.length;
      _ledgerSummary = ledger;
      _recentActivity = activity.take(4).toList();
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
    // Free/Basic plan (or not yet fetched) → worth showing the upgrade
    // prompt; already on a paid plan → skip it entirely rather than
    // promoting an upgrade the shop already has.
    final planName = ref.watch(subscriptionProvider)?.effectivePlanName;
    final showUpgradeCard = planName == null || planName == 'Basic';

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
                    const SizedBox(height: 12),
                    _buildSalesCard(),
                    const SizedBox(height: 14),
                    _buildMetricsRow(),
                    const SizedBox(height: 14),
                    _buildMoneyAtGlance(),
                    if (showUpgradeCard) ...[
                      const SizedBox(height: 12),
                      _buildPlansCard(),
                    ],
                    const SizedBox(height: 14),
                    _buildQuickActions(),
                    const SizedBox(height: 14),
                    _buildRecentActivity(),
                    const SizedBox(height: 20),
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

    Widget avatar(double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryLight, width: 1.5),
          ),
          child: ClipOval(
            child: resolveShopLogoImage(
                  logoPath: _logoPath,
                  logoUrl: _logoUrl,
                  size: size,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(initial,
                        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                  ),
                ) ??
                Center(
                    child: Text(initial,
                        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                  ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hamburger menu
          IconButton(
            icon: const HamburgerIcon(),
            onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // Brand wordmark + tagline
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appName.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.appTagline,
                    style: TextStyle(fontSize: 10.5, color: c.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          // Notification bell + avatar, with the shop name (tap → Profile)
          // underneath — the low-stock alert that used to be its own pill
          // badge is now a small dot on the bell instead, to keep this
          // header compact.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: Icon(Icons.notifications_outlined, color: c.textSecondary),
                        onPressed: () => context.push('/notifications'),
                        tooltip: _lowStockCount > 0 ? l10n.lowStockBadge('$_lowStockCount') : null,
                      ),
                      if (_lowStockCount > 0)
                        Positioned(
                          top: 9,
                          right: 9,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: c.danger,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.surface, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: () => context.push('/profile').then((_) => _loadData()),
                    child: avatar(34),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => context.push('/profile').then((_) => _loadData()),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _shopName.isNotEmpty ? _shopName : l10n.myShopFallback,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: c.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Today's Sales Card ────────────────────────────────────────────────────

  Widget _buildSalesCard() {
    final l10n = context.l10n;
    final growth = _growthPercent;
    final isPositive = growth >= 0;
    final profit = _todaySummary?.totalProfit ?? 0;
    final isProfit = profit >= 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // The banner artwork (tagline + bill illustration) lives on the right
      // side of assets/icon/banner.jpeg — left untouched here. The scrim and
      // all coded content are confined to the left ~55% so nothing coded
      // ever sits on top of that artwork.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/icon/banner.jpeg', fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.82),
                      AppColors.primary.withValues(alpha: 0.45),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.32, 0.52],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Today's Sales leads, largest and boldest — the one
                      // figure a shopkeeper glances at first.
                      Text(l10n.todaysSales,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.formatCurrency(_todaySummary?.totalSales ?? 0),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Growth-vs-yesterday sits directly under Sales, on one
                      // line, since it's a qualifier on that figure — not a
                      // separate metric competing for attention.
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          size: 12,
                          color: isPositive ? AppColors.successLight : AppColors.errorLight,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${AppFormatters.formatGrowth(growth)} ${l10n.fromYesterday}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isPositive ? AppColors.successLight : AppColors.errorLight,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // Today's Profit — a clearly secondary, smaller block
                      // beneath Sales, same figure the Metrics Row below
                      // shows as a small tile, surfaced here too since this
                      // banner is the first thing a shopkeeper sees.
                      Text(isProfit ? l10n.todaysProfit : l10n.todaysLoss,
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isProfit ? AppColors.success : AppColors.error)
                              .withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isProfit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                              size: 13,
                              color: isProfit ? AppColors.successLight : AppColors.errorLight,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                AppFormatters.formatCurrency(profit.abs()),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isProfit ? AppColors.successLight : AppColors.errorLight),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
              title: l10n.bills,
              value: '$_todayBills',
              icon: Icons.receipt_rounded,
              color: c.info,
              onTap: () => context.push('/bills'))),
      const SizedBox(width: 12),
      Expanded(
          child: _MetricTile(
              title: l10n.collectionsLabel,
              value: AppFormatters.formatCurrencyCompact(_todayCollections),
              icon: Icons.account_balance_wallet_rounded,
              color: c.success,
              onTap: () => context.push('/customers'))),
      const SizedBox(width: 12),
      Expanded(
          child: _MetricTile(
              title: l10n.todaysProfit,
              value: AppFormatters.formatCurrencyCompact(_todaySummary?.totalProfit ?? 0),
              icon: Icons.trending_up_rounded,
              color: c.warning,
              onTap: () => context.push('/reports'))),
    ]);
  }

  // ── Money at a Glance ─────────────────────────────────────────────────────

  Widget _buildMoneyAtGlance() {
    final c = context.colors;
    final l10n = context.l10n;
    final net = _ledgerSummary.totalDue - _ledgerSummary.totalAdvance;
    // Net Balance's own color/tag flips with its sign, so it never claims a
    // payable balance is a "Due Amount" (receivable) or vice-versa.
    final netIsReceivable = net >= 0;
    final netColor = netIsReceivable ? c.success : c.warning;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Text(l10n.moneyAtGlanceLabel,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w600, color: c.textPrimary)),
              TextButton(
                onPressed: () => context.push('/customers'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(l10n.viewLedgerLabel,
                      style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.primaryLight),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _LedgerStat(
                    label: l10n.toCollectLabel,
                    value: AppFormatters.formatCurrencyCompact(_ledgerSummary.totalDue),
                    color: c.success)),
            Container(width: 1, height: 36, color: c.divider, margin: const EdgeInsets.symmetric(horizontal: 6)),
            Expanded(
                child: _LedgerStat(
                    label: l10n.toPayLabel,
                    value: AppFormatters.formatCurrencyCompact(_ledgerSummary.totalAdvance),
                    color: c.warning)),
            Container(width: 1, height: 36, color: c.divider, margin: const EdgeInsets.symmetric(horizontal: 6)),
            Expanded(
                child: _LedgerStat(
                    label: l10n.netBalanceLabel,
                    value: AppFormatters.formatCurrencyCompact(net.abs()),
                    color: netColor,
                    tag: netIsReceivable ? l10n.outstandingLabel : l10n.inAdvanceLabel)),
          ]),
        ],
      ),
    );
  }

  // ── Plans / Upgrade ───────────────────────────────────────────────────────

  Widget _buildPlansCard() {
    final c = context.colors;
    final l10n = context.l10n;
    return InkWell(
      onTap: () => context.push('/profile/subscription'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.workspace_premium_rounded, color: AppColors.primaryLight, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.upgradeToProTitle,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Text(l10n.viewPlansLabel,
                style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w700)),
            const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primaryLight),
          ],
        ),
      ),
    );
  }

  // ── Recent Activity ───────────────────────────────────────────────────────

  Widget _buildRecentActivity() {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Text(l10n.recentActivityLabel,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
              TextButton(
                onPressed: () => context.push('/customers'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(l10n.viewAll,
                      style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.primaryLight),
                ]),
              ),
            ],
          ),
          if (_recentActivity.isEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Column(children: [
                Icon(Icons.history_rounded, size: 36, color: c.textSecondary),
                const SizedBox(height: 8),
                Text(l10n.noRecentActivityYet,
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 8),
          ] else
            ...(_recentActivity.asMap().entries.map((entry) => _ActivityTile(
                  entry: entry.value,
                  showDivider: entry.key > 0,
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
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      Color? color,
    }) {
      final enabled = subscription.isModuleEnabled(moduleKey);
      return _QuickAction(
        icon: icon,
        label: label,
        subtitle: subtitle,
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
        const SizedBox(height: 2),
        Text(l10n.quickActionsSubtitle, style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 88,
          ),
          children: [
            // First action is Bills (view/manage existing bills) — this is
            // deliberately NOT "New Bill"; bill creation stays reachable via
            // the mic button and the Bills screen's own create action.
            gated(moduleKey: 'billing',    icon: Icons.receipt_long_rounded, label: l10n.bills,     subtitle: l10n.qaViewManage,    onTap: () => context.push('/bills')),
            gated(moduleKey: 'inventory',  icon: Icons.inventory_2_rounded,  label: l10n.items,     subtitle: l10n.qaManageStock,   onTap: () => context.push('/inventory')),
            gated(moduleKey: 'customers',  icon: Icons.people_rounded,       label: l10n.customers, subtitle: l10n.qaViewAndAdd,    onTap: () => context.push('/customers')),
            gated(moduleKey: 'inventory',  icon: Icons.add_box_rounded,      label: l10n.addItem,   subtitle: l10n.qaQuickAdd,      onTap: () => context.push('/inventory/add')),
            gated(moduleKey: 'reports',    icon: Icons.bar_chart_rounded,    label: l10n.reports,   subtitle: l10n.qaSalesInsights, onTap: () => context.push('/reports')),
            gated(moduleKey: 'ai_manager', icon: Icons.smart_toy_rounded,    label: l10n.aiManager, subtitle: l10n.qaVoiceSmart,    color: AppColors.primaryLight, onTap: () => context.push('/ai-manager')),
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

}

// ── Ledger Stat (Money at a Glance) ─────────────────────────────────────────

class _LedgerStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  // Small colored word under the value — only Net Balance uses this, to say
  // whether that balance is currently receivable ("Due Amount") or payable
  // ("In Advance") instead of one ambiguous "Outstanding" for either case.
  final String? tag;
  const _LedgerStat({required this.label, required this.value, required this.color, this.tag});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: c.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if (tag != null) ...[
          const SizedBox(height: 2),
          Text(tag!, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

// ── Recent Activity ──────────────────────────────────────────────────────────
//
// Merges two existing event sources — new bills, and standalone ledger
// movements (collections against a due, advance deposits, "You Gave"
// credit entries) — into one chronological feed, in place of the old
// bills-only "Recent Bills" list. See _HomeScreenState._loadData for how
// the list is built and which payment_transaction types are included.

enum _ActivityType { billCreated, paymentReceived, creditGiven, paymentMade }

class _ActivityEntry {
  final _ActivityType type;
  final String? customerName;
  final double amount;
  final DateTime createdAt;
  const _ActivityEntry({
    required this.type,
    required this.customerName,
    required this.amount,
    required this.createdAt,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;
  final bool showDivider;
  const _ActivityTile({required this.entry, required this.showDivider});

  String _formatTime(DateTime dt, String todayLabel) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    if (isToday) return '$todayLabel, $h:$m $ampm';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    final String label;
    final IconData icon;
    final Color color;
    final bool isPositive;
    switch (entry.type) {
      case _ActivityType.paymentReceived:
        label = l10n.activityPaymentReceived;
        icon = Icons.arrow_upward_rounded;
        color = c.success;
        isPositive = true;
      case _ActivityType.billCreated:
        label = l10n.activityBillCreated;
        icon = Icons.receipt_rounded;
        color = AppColors.primaryLight;
        isPositive = true;
      case _ActivityType.creditGiven:
        label = l10n.activityCreditGiven;
        icon = Icons.arrow_outward_rounded;
        color = c.warning;
        isPositive = false;
      case _ActivityType.paymentMade:
        label = l10n.activityPaymentMade;
        icon = Icons.keyboard_return_rounded;
        color = c.danger;
        isPositive = false;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showDivider
          ? BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: 1)))
          : null,
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              '${entry.customerName ?? l10n.walkInCustomer} · ${_formatTime(entry.createdAt, l10n.today)}',
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          '${isPositive ? '+' : '-'}${AppFormatters.formatCurrency(entry.amount)}',
          style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }
}

// ── Metric Tile ───────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: c.textHint),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 1),
          Text(title, style: TextStyle(fontSize: 11, color: c.textSecondary)),
        ]),
      ),
    );
  }
}

// ── Quick Action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.subtitle,
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
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: (color ?? AppColors.primaryLight).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 15, color: color ?? AppColors.primaryLight),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 15, color: c.textHint),
                    ],
                  ),
                  const Spacer(),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12, color: c.textPrimary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(fontSize: 9, color: c.textSecondary),
                      maxLines: 1,
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
