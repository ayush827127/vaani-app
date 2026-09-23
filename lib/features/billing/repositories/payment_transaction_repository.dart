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
