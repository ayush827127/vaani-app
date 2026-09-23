import '../../../core/db/database_helper.dart';

class SalesSummary {
  final double totalSales;
  final double totalCost;
  final double totalProfit;
  final int totalBills;
  final int totalItemsSold;

  const SalesSummary({
    this.totalSales = 0,
    this.totalCost = 0,
    this.totalProfit = 0,
    this.totalBills = 0,
    this.totalItemsSold = 0,
  });
}

class TopItem {
  final int itemId;
  final String name;
  final String? imagePath;
  final int totalQty;
  final double totalRevenue;

  const TopItem({
    required this.itemId,
    required this.name,
    this.imagePath,
    required this.totalQty,
    required this.totalRevenue,
  });
}

class DailyData {
  final String date;
  final double sales;
  final double profit;

  const DailyData({required this.date, required this.sales, required this.profit});
}

class ReportRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Revenue is recognised at the point of sale, matching sales_summary's own
  // accrual-basis bookkeeping (populated at invoice creation regardless of
  // payment status) — so a credit/partial-paid sale still counts here.
  // Only cancelled (voided/fully-returned) and soft-deleted invoices are
  // excluded, since those never happened from a stock/revenue standpoint.
  static const _liveInvoiceFilter =
      "deleted_at IS NULL AND status != 'cancelled'";

  Future<SalesSummary> getPeriodSales(int shopId, String startDate, String endDate) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(grand_total), 0) as total_sales,
        COUNT(*) as total_bills
      FROM invoices
      WHERE shop_id = ? AND $_liveInvoiceFilter
        AND DATE(created_at) BETWEEN ? AND ?
    ''', [shopId, startDate, endDate]);

    final profitResult = await db.rawQuery('''
      SELECT
        COALESCE(SUM(ii.line_total - ii.quantity * ii.cost_price), 0) as profit,
        COALESCE(SUM(ii.quantity), 0) as items_sold
      FROM invoice_items ii
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.shop_id = ? AND $_liveInvoiceFilter
        AND DATE(i.created_at) BETWEEN ? AND ?
    ''', [shopId, startDate, endDate]);

    final sales = (result.first['total_sales'] as num?)?.toDouble() ?? 0;
    final bills = result.first['total_bills'] as int? ?? 0;
    final profit = (profitResult.first['profit'] as num?)?.toDouble() ?? 0;
    final items = profitResult.first['items_sold'] as int? ?? 0;

    return SalesSummary(
      totalSales: sales,
      totalCost: sales - profit,
      totalProfit: profit,
      totalBills: bills,
      totalItemsSold: items,
    );
  }

  Future<SalesSummary> getTodaySummary(int shopId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return getPeriodSales(shopId, today, today);
  }

  Future<SalesSummary> getYesterdaySummary(int shopId) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    return getPeriodSales(shopId, yesterday, yesterday);
  }

  Future<List<TopItem>> getTopItems(int shopId, String startDate, String endDate, {int limit = 10}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.id as item_id, p.name, p.image_path,
             SUM(ii.quantity) as total_qty,
             SUM(ii.line_total) as total_revenue
      FROM invoice_items ii
      JOIN items p ON p.id = ii.item_id
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.shop_id = ? AND $_liveInvoiceFilter
        AND DATE(i.created_at) BETWEEN ? AND ?
      GROUP BY p.id
      ORDER BY total_qty DESC
      LIMIT ?
    ''', [shopId, startDate, endDate, limit]);

    return rows
        .map((r) => TopItem(
              itemId: r['item_id'] as int,
              name: r['name'] as String,
              imagePath: r['image_path'] as String?,
              totalQty: r['total_qty'] as int? ?? 0,
              totalRevenue: (r['total_revenue'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  Future<List<DailyData>> getLast7DaysSales(int shopId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT date, total_sales as sales, total_profit as profit
      FROM sales_summary
      WHERE date >= DATE('now', '-7 days')
      ORDER BY date ASC
    ''');
    return rows
        .map((r) => DailyData(
              date: r['date'] as String,
              sales: (r['sales'] as num?)?.toDouble() ?? 0,
              profit: (r['profit'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  Future<List<DailyData>> getMonthSales(int shopId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT date, total_sales as sales, total_profit as profit
      FROM sales_summary
      WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now')
      ORDER BY date ASC
    ''');
    return rows
        .map((r) => DailyData(
              date: r['date'] as String,
              sales: (r['sales'] as num?)?.toDouble() ?? 0,
              profit: (r['profit'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  Future<double> getSalesHealthPercent(int shopId) async {
    final today = await getTodaySummary(shopId);
    if (today.totalSales == 0) return 50;
    // Compare to 30-day average
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final past = await getPeriodSales(shopId, thirtyDaysAgo, yesterday);
    if (past.totalBills == 0) return 75;
    final avgDaily = past.totalSales / 30;
    final health = (today.totalSales / avgDaily * 100).clamp(0.0, 100.0);
    return health;
  }
}
