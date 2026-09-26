import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../shared/models/payment_transaction.dart';

class PaymentTransactionRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> insert(PaymentTransaction txn) async {
    final db = await _db.database;
    final map = txn.toMap()..remove('id');
    return db.insert('payment_transactions', map);
  }

  Future<PaymentTransaction?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('payment_transactions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return PaymentTransaction.fromMap(rows.first);
  }

  Future<List<PaymentTransaction>> getByCustomer(int customerId,
      {int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'payment_transactions',
      where: 'customer_id = ? AND deleted_at IS NULL',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  Future<List<PaymentTransaction>> getByInvoice(int invoiceId) async {
    final db = await _db.database;
    final rows = await db.query(
      'payment_transactions',
      where: 'invoice_id = ? AND deleted_at IS NULL',
      whereArgs: [invoiceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  /// All payment transactions for [shopId] created since [since] (or all, if
  /// null) — used for cloud sync. Insert-only ledger, so `created_at` alone
  /// is sufficient (same as `inventory_transactions`).
  Future<List<PaymentTransaction>> getPaymentTransactionsUpdatedSince(
      int shopId, DateTime? since) async {
    final db = await _db.database;
    final rows = since == null
        ? await db.query('payment_transactions', where: 'shop_id = ?', whereArgs: [shopId])
        : await db.query(
            'payment_transactions',
            where: 'shop_id = ? AND created_at > ?',
            whereArgs: [shopId, since.toIso8601String()],
          );
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  /// Actual cash/UPI/card collected within [startDate]..[endDate] —
  /// 'bill_payment' (paid at checkout), 'outstanding_collection' (collected
  /// later against a due) and 'advance_deposit' (paid in before any bill).
  /// Deliberately excludes 'advance_used' (existing balance moved, not new
  /// money in) and 'refund'/'invoice_due'/'invoice_due_reversal' (ledger
  /// bookkeeping, not a cash movement) — see the type field's doc comment
  /// on PaymentTransaction for what each one means.
  Future<double> getPeriodCollections(int shopId, String startDate, String endDate) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM payment_transactions
      WHERE shop_id = ? AND deleted_at IS NULL AND DATE(created_at) BETWEEN ? AND ?
        AND type IN ('bill_payment', 'outstanding_collection', 'advance_deposit')
    ''', [shopId, startDate, endDate]);
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> getTodayCollections(int shopId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return getPeriodCollections(shopId, today, today);
  }

  /// Collected amount within the period, broken down by [PaymentTransaction.
  /// paymentMode] ('cash', 'upi', 'card', ...) — for the Payments tab's
  /// Cash/UPI/Credit/Other breakdown. Same money-in type set as
  /// [getPeriodCollections].
  Future<Map<String, double>> getPaymentModeBreakdown(int shopId, String startDate, String endDate) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT payment_mode, COALESCE(SUM(amount), 0) as total FROM payment_transactions
      WHERE shop_id = ? AND deleted_at IS NULL AND DATE(created_at) BETWEEN ? AND ?
        AND type IN ('bill_payment', 'outstanding_collection', 'advance_deposit')
      GROUP BY payment_mode
    ''', [shopId, startDate, endDate]);
    return {
      for (final r in rows) (r['payment_mode'] as String? ?? 'cash'): (r['total'] as num?)?.toDouble() ?? 0,
    };
  }

  /// Most recent standalone ledger events for a shop's activity feed —
  /// scoped to [types] so callers can pick which kinds of movement count as
  /// a distinct "activity" (e.g. a Home dashboard excluding 'bill_payment'
  /// since that's already represented by the bill itself).
  Future<List<PaymentTransaction>> getRecentByShop(
    int shopId, {
    required List<String> types,
    int limit = 10,
  }) async {
    final db = await _db.database;
    final placeholders = List.filled(types.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT * FROM payment_transactions
      WHERE shop_id = ? AND deleted_at IS NULL AND type IN ($placeholders)
      ORDER BY created_at DESC
      LIMIT ?
    ''', [shopId, ...types, limit]);
    return rows.map(PaymentTransaction.fromMap).toList();
  }

  /// Writes a cloud-pulled payment straight into the row matching its exact
  /// [payment.id] — see the matching note on
  /// ItemRepository.upsertFromCloud().
  ///
  /// Note (pre-existing, now newly visible under two-way sync): an admin
  /// edit/delete to a payment does not recompute the linked invoice's
  /// receivedAmount/pendingAmount or the customer's totalOutstanding on the
  /// backend — those stay whatever they were, independent of this payment
  /// row. That mismatch already existed one-way (silently, since it never
  /// reached the phone); it's a known follow-up, not something this sync
  /// layer attempts to reconcile.
  Future<void> upsertFromCloud(PaymentTransaction payment) async {
    final db = await _db.database;
    final map = payment.toMap();
    map['deleted_at'] = payment.deletedAt?.toIso8601String();
    await db.insert('payment_transactions', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
