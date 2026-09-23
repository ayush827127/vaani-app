import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/utils/constants.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/cart_item.dart';

/// Thrown by [InvoiceRepository.createInvoice] when a cart item would drive
/// a item's stock below zero — the transaction is rolled back (sqflite
/// rolls back automatically on any thrown error inside `db.transaction`), so
/// nothing about the sale is partially committed. Every earlier stock check
/// (manual +/- buttons, voice quantity actions) is UI-level and can go stale
/// between being shown and checkout actually running; this is the last line
/// of defense that always sees the real row at the moment of the write.
class InsufficientStockException implements Exception {
  final String itemName;
  final int available;
  final int requested;
  const InsufficientStockException({
    required this.itemName,
    required this.available,
    required this.requested,
  });
  @override
  String toString() =>
      'Insufficient stock for $itemName: only $available available, $requested requested';
}

/// A payment ledger row to record alongside the invoice it belongs to — see
/// [InvoiceRepository.createInvoice]'s `paymentTransactions` parameter. Left
/// without an `invoiceId` because that id doesn't exist until the invoice
/// insert happens inside the same transaction.
class PendingPaymentTxn {
  final String type;
  final double amount;
  final String paymentMode;
  const PendingPaymentTxn({
    required this.type,
    required this.amount,
    required this.paymentMode,
  });
}

/// One invoice's share of a standalone payment collection (see
/// [InvoiceRepository.collectPayment]) — the new payment fields for that
/// invoice, plus how much of the collected amount was allocated to it.
class InvoicePaymentAllocation {
  final int invoiceId;
  final double allocated;
  final double newReceivedAmount;
  final double newPendingAmount;
  final String newStatus;
  const InvoicePaymentAllocation({
    required this.invoiceId,
    required this.allocated,
    required this.newReceivedAmount,
    required this.newPendingAmount,
    required this.newStatus,
  });
}

class InvoiceRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String> getNextInvoiceNumber(int shopId) async {
    final db = await _db.database;
    final now = DateTime.now();
    final ym = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery('''
      SELECT MAX(CAST(SUBSTR(invoice_number, 12) AS INTEGER)) as max_seq
      FROM invoices
      WHERE shop_id = ? AND SUBSTR(invoice_number, 5, 6) = ?
    ''', [shopId, ym]);
    final maxSeq = result.first['max_seq'] as int? ?? 0;
    final nextSeq = (maxSeq + 1).toString().padLeft(6, '0');
    return 'INV-$ym-$nextSeq';
  }

  /// Creates the invoice, its items, deducts stock, and — when [customerId]
  /// is set — updates that customer's outstanding/advance balance and
  /// inserts [paymentTransactions], all inside the same database
  /// transaction. Previously the balance update and ledger inserts happened
  /// as separate calls made by the caller *after* this returned; a crash or
  /// kill between this method committing and those calls running could
  /// leave stock deducted and the invoice recorded with no matching balance
  /// change or ledger entry (or, on a retry, double-apply them). Passing
  /// everything in up front makes the whole checkout one atomic unit.
  Future<Invoice> createInvoice({
    required Invoice invoice,
    required List<CartItem> cartItems,
    int? customerId,
    double? newOutstanding,
    double? newAdvanceBalance,
    List<PendingPaymentTxn> paymentTransactions = const [],
  }) async {
    final db = await _db.database;
    late Invoice savedInvoice;

    await db.transaction((txn) async {
      // Insert invoice
      final invoiceMap = invoice.toMap()..remove('id');
      final invoiceId = await txn.insert('invoices', invoiceMap);

      double totalCost = 0;
      int totalItems = 0;

      // Discount is applied at invoice level, not per line, but GST must be
      // charged on the post-discount taxable value (not the sticker price) —
      // so each line's own discount share is derived from its share of the
      // pre-discount subtotal and only then taxed at that line's GST rate.
      final discountRatio = invoice.subtotal > 0
          ? (invoice.discountAmount / invoice.subtotal).clamp(0.0, 1.0)
          : 0.0;

      // Insert items + deduct stock
      for (final item in cartItems) {
        final lineTotal = item.quantity * item.effectivePrice;
        final taxableValue = lineTotal * (1 - discountRatio);
        final gstAmt = taxableValue * item.item.gstRate / 100;

        await txn.insert('invoice_items', {
          'invoice_id': invoiceId,
          'item_id': item.item.id,
          'item_name': item.item.name,
          'quantity': item.quantity,
          'selling_price': item.effectivePrice,
          'gst_rate': item.item.gstRate,
          'gst_amount': gstAmt,
          'line_total': lineTotal,
          'returned_quantity': 0,
          'cost_price': item.item.costPrice,
        });

        // Get current stock
        final stockRows = await txn.query('items',
            columns: ['stock_quantity'], where: 'id = ?', whereArgs: [item.item.id]);
        if (stockRows.isEmpty) {
          throw InsufficientStockException(
            itemName: item.item.name,
            available: 0,
            requested: item.quantity,
          );
        }
        final stockBefore = stockRows.first['stock_quantity'] as int;
        final stockAfter = stockBefore - item.quantity;
        if (stockAfter < 0) {
          // Every earlier check (manual buttons, voice actions) is UI-level
          // and can be stale by the time checkout actually runs — this is
          // the one point that always sees the real row, so it's the one
          // that must actually refuse rather than just warn.
          throw InsufficientStockException(
            itemName: item.item.name,
            available: stockBefore,
            requested: item.quantity,
          );
        }

        // Deduct stock
        await txn.update(
          'items',
          {'stock_quantity': stockAfter, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [item.item.id],
        );

        // Inventory transaction
        await txn.insert('inventory_transactions', {
          'item_id': item.item.id,
          'invoice_id': invoiceId,
          'type': 'sale',
          'quantity_change': -item.quantity,
          'stock_before': stockBefore,
          'stock_after': stockAfter,
          'created_at': DateTime.now().toIso8601String(),
        });

        totalCost += item.quantity * item.item.costPrice;
        totalItems += item.quantity;
      }

      // Update customer stats
      if (customerId != null) {
        await txn.rawUpdate('''
          UPDATE customers SET
            total_purchases = total_purchases + ?,
            total_bills = total_bills + 1,
            last_visit = ?,
            updated_at = ?
          WHERE id = ?
        ''', [
          invoice.grandTotal,
          DateTime.now().toIso8601String(),
          DateTime.now().toIso8601String(),
          customerId,
        ]);
      }

      // Update sales_summary
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final existing = await txn.query('sales_summary', where: 'date = ?', whereArgs: [today]);
      if (existing.isEmpty) {
        await txn.insert('sales_summary', {
          'date': today,
          'total_sales': invoice.grandTotal,
          'total_cost': totalCost,
          'total_profit': invoice.grandTotal - totalCost,
          'total_bills': 1,
          'total_items_sold': totalItems,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        await txn.rawUpdate('''
          UPDATE sales_summary SET
            total_sales = total_sales + ?,
            total_cost = total_cost + ?,
            total_profit = total_profit + ?,
            total_bills = total_bills + 1,
            total_items_sold = total_items_sold + ?,
            updated_at = ?
          WHERE date = ?
        ''', [
          invoice.grandTotal,
          totalCost,
          invoice.grandTotal - totalCost,
          totalItems,
          DateTime.now().toIso8601String(),
          today,
        ]);
      }

      // Outstanding/advance balance + payment ledger — same transaction as
      // everything above (see the method doc comment for why).
      if (customerId != null && (newOutstanding != null || newAdvanceBalance != null)) {
        await txn.update(
          'customers',
          {
            if (newOutstanding != null)
              'total_outstanding': newOutstanding < 0 ? 0.0 : newOutstanding,
            if (newAdvanceBalance != null)
              'advance_balance': newAdvanceBalance < 0 ? 0.0 : newAdvanceBalance,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [customerId],
        );
      }

      for (final p in paymentTransactions) {
        if (p.type == 'outstanding_collection' && customerId != null) {
          // Excess cash on this bill that pays down OLD dues. The customer's
          // total was already reduced above, but until now none of the old
          // invoices were marked paid — they kept showing their full pending
          // amount, so they were offered again for collection (double-
          // counting the same money) and the invoice list disagreed with the
          // customer balance. Settle the oldest unpaid invoices first, one
          // ledger row per invoice; whatever is left over (a due that has
          // no invoice, e.g. a "Give Credit" entry) is recorded with no
          // invoice.
          var remaining = p.amount;
          final oldInvoices = await txn.query(
            'invoices',
            where: 'customer_id = ? AND pending_amount > 0.005 AND id != ? '
                "AND status != 'cancelled' AND deleted_at IS NULL",
            whereArgs: [customerId, invoiceId],
            orderBy: 'created_at ASC, id ASC',
          );
          final stamp = DateTime.now().toIso8601String();
          for (final row in oldInvoices) {
            if (remaining <= 0.005) break;
            final pending = (row['pending_amount'] as num).toDouble();
            final received = (row['received_amount'] as num).toDouble();
            final applied = remaining < pending ? remaining : pending;
            final newPending = pending - applied;
            await txn.update(
              'invoices',
              {
                'received_amount': received + applied,
                'pending_amount': newPending,
                'status': newPending <= 0.01
                    ? AppConstants.statusPaid
                    : AppConstants.statusPartialPaid,
                'updated_at': stamp,
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            await txn.insert('payment_transactions', {
              'shop_id': invoice.shopId,
              'customer_id': customerId,
              'invoice_id': row['id'],
              'type': 'outstanding_collection',
              'amount': applied,
              'payment_mode': p.paymentMode,
              'notes': null,
              'created_at': stamp,
              'updated_at': stamp,
            });
            remaining -= applied;
          }
          if (remaining > 0.005) {
            await txn.insert('payment_transactions', {
              'shop_id': invoice.shopId,
              'customer_id': customerId,
              'invoice_id': null,
              'type': 'outstanding_collection',
              'amount': remaining,
              'payment_mode': p.paymentMode,
              'notes': null,
              'created_at': stamp,
              'updated_at': stamp,
            });
          }
          continue;
        }
        await txn.insert('payment_transactions', {
          'shop_id': invoice.shopId,
          'customer_id': customerId,
          'invoice_id': invoiceId,
          'type': p.type,
          'amount': p.amount,
          'payment_mode': p.paymentMode,
          'notes': null,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // A ledger row for the pending (unpaid) portion of this bill, purely
      // additive to what already happens above — nothing here changes any
      // existing field or the cash-side payment rows just inserted. This is
      // what lets the customer ledger (customer_details_screen.dart) show a
      // complete, accurate running balance from payment_transactions alone,
      // rather than needing to separately reason about every invoice's
      // current pendingAmount. Reversed by _reverseInvoiceItems below via a
      // matching 'invoice_due_reversal' row if the bill is later voided/
      // returned before being fully paid.
      if (customerId != null && invoice.pendingAmount > 0) {
        await txn.insert('payment_transactions', {
          'shop_id': invoice.shopId,
          'customer_id': customerId,
          'invoice_id': invoiceId,
          'type': 'invoice_due',
          'amount': invoice.pendingAmount,
          'payment_mode': 'adjustment',
          'notes': null,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // toMap() always contains an 'id' key (null for a new invoice), so
      // the old containsKey('id') check was always true and this returned
      // the caller's id-less invoice — anything using the returned invoice
      // (PDF, void, share) had no id to work with.
      savedInvoice = invoice.id != null
          ? invoice
          : Invoice.fromMap({...invoice.toMap(), 'id': invoiceId});
    });

    return savedInvoice;
  }

  Future<Invoice?> getInvoiceById(int id) async {
    final db = await _db.database;
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final itemRows = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
    final items = itemRows.map(InvoiceItem.fromMap).toList();
    return Invoice.fromMap(rows.first, items: items);
  }

  Future<List<Invoice>> getInvoicesByShop(int shopId, {int limit = 20, int offset = 0}) async {
    final db = await _db.database;
    final rows = await db.query(
      'invoices',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shopId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  /// Same as [getInvoicesByShop], but each Invoice's [Invoice.itemCount] is
  /// populated via a COUNT subquery — for list screens (Home, Bills) that
  /// want to show "N items" per row without an N+1 query per invoice or
  /// loading every line item.
  Future<List<Invoice>> getInvoicesByShopWithItemCounts(int shopId,
      {int limit = 20, int offset = 0}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT invoices.*,
        (SELECT COUNT(*) FROM invoice_items WHERE invoice_items.invoice_id = invoices.id) AS item_count
      FROM invoices
      WHERE shop_id = ? AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    ''', [shopId, limit, offset]);
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  Future<List<Invoice>> getInvoicesByCustomer(int customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'invoices',
      where: 'customer_id = ? AND deleted_at IS NULL',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  /// How many voice-created invoices this shop has, for the Basic plan's
  /// 50-invoice cap — see the isVoiceCreated field doc comment on Invoice.
  /// This is the *local* count (instant, works offline); the backend
  /// independently re-derives the same number from synced data as the
  /// authoritative backstop — see shop-voice.service.js.
  Future<int> countVoiceInvoices(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM invoices WHERE shop_id = ? AND is_voice_created = 1 AND deleted_at IS NULL',
      [shopId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> updateInvoicePayment(
    int invoiceId, {
    required double receivedAmount,
    required double pendingAmount,
    required String status,
  }) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {
        'received_amount': receivedAmount,
        'pending_amount': pendingAmount,
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  /// Records a standalone payment collection (collect_payment_sheet.dart) —
  /// an advance deposit, or an outstanding-balance collection allocated
  /// across one or more invoices — atomically: every invoice's payment
  /// fields, every matching ledger row, and the customer's resulting
  /// outstanding/advance balance are all written in one transaction. This
  /// used to be a loop of separate repository calls (updateInvoicePayment,
  /// then a ledger insert, per invoice, then a final balance update); a
  /// crash partway through could leave an invoice marked paid with no
  /// ledger row for it, or a ledger row recorded against a balance that
  /// was never actually updated.
  Future<void> collectPayment({
    required int shopId,
    required int customerId,
    required double newOutstanding,
    required double newAdvanceBalance,
    required String paymentMode,
    double? advanceDepositAmount,
    List<InvoicePaymentAllocation> invoiceAllocations = const [],
    double? generalCollectionAmount,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();

      if (advanceDepositAmount != null && advanceDepositAmount > 0) {
        await txn.insert('payment_transactions', {
          'shop_id': shopId,
          'customer_id': customerId,
          'invoice_id': null,
          'type': 'advance_deposit',
          'amount': advanceDepositAmount,
          'payment_mode': paymentMode,
          'notes': null,
          'created_at': now,
          'updated_at': now,
        });
      }

      // Collecting against the customer's aggregate outstanding with no
      // specific invoice behind it — e.g. paying down a "Give Credit" ledger
      // entry, which has no invoice to allocate against at all (see
      // CollectPaymentSheet's _generalCollectionCtrl).
      if (generalCollectionAmount != null && generalCollectionAmount > 0) {
        await txn.insert('payment_transactions', {
          'shop_id': shopId,
          'customer_id': customerId,
          'invoice_id': null,
          'type': 'outstanding_collection',
          'amount': generalCollectionAmount,
          'payment_mode': paymentMode,
          'notes': null,
          'created_at': now,
          'updated_at': now,
        });
      }

      for (final alloc in invoiceAllocations) {
        await txn.update(
          'invoices',
          {
            'received_amount': alloc.newReceivedAmount,
            'pending_amount': alloc.newPendingAmount,
            'status': alloc.newStatus,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [alloc.invoiceId],
        );
        await txn.insert('payment_transactions', {
          'shop_id': shopId,
          'customer_id': customerId,
          'invoice_id': alloc.invoiceId,
          'type': 'outstanding_collection',
          'amount': alloc.allocated,
          'payment_mode': paymentMode,
          'notes': null,
          'created_at': now,
          'updated_at': now,
        });
      }

      await txn.update(
        'customers',
        {
          'total_outstanding': newOutstanding < 0 ? 0.0 : newOutstanding,
          'advance_balance': newAdvanceBalance < 0 ? 0.0 : newAdvanceBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  /// The other half of the customer ledger, mirroring [collectPayment]'s
  /// atomicity: records a khata-style "You Gave" entry — goods or cash
  /// given to a customer on credit with no formal invoice (give_credit_
  /// sheet.dart) — as a 'manual_credit' ledger row and increases the
  /// customer's outstanding balance, in one transaction.
  Future<void> giveCredit({
    required int shopId,
    required int customerId,
    required double amount,
    required double newOutstanding,
    String? notes,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert('payment_transactions', {
        'shop_id': shopId,
        'customer_id': customerId,
        'invoice_id': null,
        'type': 'manual_credit',
        'amount': amount,
        'payment_mode': 'adjustment',
        'notes': notes,
        'created_at': now,
        'updated_at': now,
      });
      await txn.update(
        'customers',
        {
          'total_outstanding': newOutstanding < 0 ? 0.0 : newOutstanding,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  Future<List<Invoice>> getOutstandingInvoicesByCustomer(int customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'invoices',
      where: "customer_id = ? AND deleted_at IS NULL AND status IN ('partial_paid', 'pending')",
      whereArgs: [customerId],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  Future<int> getTodayBillCount(int shopId) async {
    final db = await _db.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM invoices
      WHERE shop_id = ? AND DATE(created_at) = ?
    ''', [shopId, today]);
    return result.first['cnt'] as int? ?? 0;
  }

  /// All invoices for [shopId] updated since [since] (or all, if null), each
  /// with its items batch-loaded — used for cloud sync.
  Future<List<Invoice>> getInvoicesUpdatedSince(int shopId, DateTime? since) async {
    final db = await _db.database;
    final invoiceRows = since == null
        ? await db.query('invoices', where: 'shop_id = ?', whereArgs: [shopId])
        : await db.query(
            'invoices',
            where: 'shop_id = ? AND updated_at > ?',
            whereArgs: [shopId, since.toIso8601String()],
          );
    if (invoiceRows.isEmpty) return [];

    final ids = invoiceRows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final itemRows = await db.rawQuery(
      'SELECT * FROM invoice_items WHERE invoice_id IN ($placeholders)',
      ids,
    );
    final itemsByInvoiceId = <int, List<InvoiceItem>>{};
    for (final row in itemRows) {
      final invoiceId = row['invoice_id'] as int;
      itemsByInvoiceId.putIfAbsent(invoiceId, () => []).add(InvoiceItem.fromMap(row));
    }

    return invoiceRows
        .map((r) => Invoice.fromMap(r, items: itemsByInvoiceId[r['id'] as int] ?? []))
        .toList();
  }

  /// Writes a cloud-pulled invoice straight into the row matching its exact
  /// [invoice.id] — see the matching note on
  /// ItemRepository.upsertFromCloud(). Items are wholesale-replaced
  /// (delete-then-plain-insert): nothing else references invoice_items.id,
  /// so there's no need to preserve or match the cloud's own item ids —
  /// letting SQLite assign fresh ones locally is simpler and just as correct.
  Future<void> upsertFromCloud(Invoice invoice) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final map = invoice.toMap();
      map['deleted_at'] = invoice.deletedAt?.toIso8601String();
      await txn.insert('invoices', map, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoice.id]);
      for (final item in invoice.items) {
        await txn.insert('invoice_items', {
          'invoice_id': invoice.id,
          'item_id': item.itemId,
          'item_name': item.itemName,
          'quantity': item.quantity,
          'selling_price': item.sellingPrice,
          'gst_rate': item.gstRate,
          'gst_amount': item.gstAmount,
          'line_total': item.lineTotal,
          'returned_quantity': item.returnedQuantity,
          'cost_price': item.costPrice,
        });
      }
    });
  }

  /// Cancels an invoice entirely: reverses whatever stock hasn't already
  /// been returned, refunds any money already collected for it back onto
  /// the customer's advance balance (the shop still needs to hand back cash
  /// if it was physically taken — this just keeps the ledger correct),
  /// reverses the customer's purchase/outstanding stats, and backs the
  /// day's sales_summary totals out. No-ops if already cancelled.
  Future<void> voidInvoice(int invoiceId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final invRows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invRows.isEmpty) return;
      final invoice = Invoice.fromMap(invRows.first);
      if (invoice.status == AppConstants.statusCancelled) return;

      final itemRows = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final reversals = <int, int>{}; // invoice_item id -> qty to reverse
      for (final row in itemRows) {
        final id = row['id'] as int;
        final qty = row['quantity'] as int;
        final returned = row['returned_quantity'] as int? ?? 0;
        final remaining = qty - returned;
        if (remaining > 0) reversals[id] = remaining;
      }

      await _reverseInvoiceItems(
        txn: txn,
        invoice: invoice,
        itemRows: itemRows,
        reversals: reversals,
        reason: AppConstants.txnVoid,
        note: 'Invoice ${invoice.invoiceNumber} voided',
      );

      await txn.update(
        'invoices',
        {
          'status': AppConstants.statusCancelled,
          'pending_amount': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      if (invoice.customerId != null) {
        await txn.rawUpdate(
          'UPDATE customers SET total_bills = MAX(0, total_bills - 1) WHERE id = ?',
          [invoice.customerId],
        );
      }
    });
  }

  /// Returns specific quantities of specific invoice lines (a partial or, if
  /// every remaining unit is included, effectively full return). [returns]
  /// maps invoice_item id -> quantity to return. Reverses stock for the
  /// returned units, shrinks the invoice's subtotal/GST/grand total by their
  /// (discount-adjusted) value, recomputes received/pending/status against
  /// what's already been collected, and adjusts the customer's ledger.
  /// If every line ends up fully returned the invoice is marked cancelled,
  /// same as [voidInvoice].
  Future<void> returnItems(int invoiceId, Map<int, int> returns) async {
    if (returns.isEmpty || returns.values.every((q) => q <= 0)) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      final invRows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invRows.isEmpty) return;
      final invoice = Invoice.fromMap(invRows.first);
      if (invoice.status == AppConstants.statusCancelled) return;

      final itemRows = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);

      // Clamp each requested return to what's actually still returnable.
      final reversals = <int, int>{};
      for (final row in itemRows) {
        final id = row['id'] as int;
        final requested = returns[id];
        if (requested == null || requested <= 0) continue;
        final qty = row['quantity'] as int;
        final returned = row['returned_quantity'] as int? ?? 0;
        final remaining = qty - returned;
        final toReturn = requested > remaining ? remaining : requested;
        if (toReturn > 0) reversals[id] = toReturn;
      }
      if (reversals.isEmpty) return;

      await _reverseInvoiceItems(
        txn: txn,
        invoice: invoice,
        itemRows: itemRows,
        reversals: reversals,
        reason: AppConstants.txnReturn,
        note: 'Items returned against ${invoice.invoiceNumber}',
      );

      // If every line is now fully returned, treat the bill as cancelled.
      final refreshedItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final fullyReturned = refreshedItems.every(
          (r) => (r['returned_quantity'] as int? ?? 0) >= (r['quantity'] as int));
      if (fullyReturned) {
        await txn.update(
          'invoices',
          {
            'status': AppConstants.statusCancelled,
            'pending_amount': 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
        if (invoice.customerId != null) {
          await txn.rawUpdate(
            'UPDATE customers SET total_bills = MAX(0, total_bills - 1) WHERE id = ?',
            [invoice.customerId],
          );
        }
      }
    });
  }

  /// Shared reversal engine for [voidInvoice] and [returnItems]: puts stock
  /// back, shrinks the invoice's own totals, reconciles received/pending
  /// against money already collected (refunding any now-excess amount to
  /// the customer's advance balance), reverses the customer's purchase
  /// total and outstanding by the same amount, and backs the reversed
  /// portion out of that day's sales_summary row.
  Future<void> _reverseInvoiceItems({
    required Transaction txn,
    required Invoice invoice,
    required List<Map<String, Object?>> itemRows,
    required Map<int, int> reversals,
    required String reason,
    required String note,
  }) async {
    final now = DateTime.now().toIso8601String();
    final discountRatio = invoice.subtotal > 0
        ? (invoice.discountAmount / invoice.subtotal).clamp(0.0, 1.0)
        : 0.0;

    double reversedSubtotal = 0;
    double reversedGst = 0;
    double reversedCost = 0;
    int reversedQtyTotal = 0;

    for (final row in itemRows) {
      final invoiceItemId = row['id'] as int;
      final qtyToReverse = reversals[invoiceItemId];
      if (qtyToReverse == null || qtyToReverse <= 0) continue;

      final itemId = row['item_id'] as int;
      final unitPrice = (row['selling_price'] as num).toDouble();
      final gstRate = (row['gst_rate'] as num?)?.toDouble() ?? 0;
      final costPrice = (row['cost_price'] as num?)?.toDouble() ?? 0;
      final returnedSoFar = row['returned_quantity'] as int? ?? 0;

      final lineReversed = unitPrice * qtyToReverse;
      final taxableReversed = lineReversed * (1 - discountRatio);
      final gstReversed = taxableReversed * gstRate / 100;

      reversedSubtotal += lineReversed;
      reversedGst += gstReversed;
      reversedCost += costPrice * qtyToReverse;
      reversedQtyTotal += qtyToReverse;

      // Put stock back.
      final stockRows = await txn.query('items', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [itemId]);
      if (stockRows.isNotEmpty) {
        final stockBefore = stockRows.first['stock_quantity'] as int;
        final stockAfter = stockBefore + qtyToReverse;
        await txn.update(
          'items',
          {'stock_quantity': stockAfter, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [itemId],
        );
        await txn.insert('inventory_transactions', {
          'item_id': itemId,
          'invoice_id': invoice.id,
          'type': reason,
          'quantity_change': qtyToReverse,
          'stock_before': stockBefore,
          'stock_after': stockAfter,
          'notes': note,
          'created_at': now,
        });
      }

      await txn.update(
        'invoice_items',
        {'returned_quantity': returnedSoFar + qtyToReverse},
        where: 'id = ?',
        whereArgs: [itemId],
      );
    }

    if (reversedQtyTotal == 0) return;

    final reversedDiscount = reversedSubtotal * discountRatio;
    final reversedTotal = (reversedSubtotal - reversedDiscount) + reversedGst;

    final newSubtotal = invoice.subtotal - reversedSubtotal;
    final newDiscountAmount = invoice.discountAmount - reversedDiscount;
    final newGstAmount = invoice.gstAmount - reversedGst;
    final newGrandTotal = invoice.grandTotal - reversedTotal;

    // invoice.receivedAmount is the running total already credited to this
    // invoice (set at creation, and kept current by both
    // InvoiceRepository.updateInvoicePayment and this same method) — using
    // it directly, rather than re-summing the payment ledger, is what keeps
    // a second reversal on the same invoice from re-refunding money a prior
    // reversal already refunded.
    final alreadyReceived = invoice.receivedAmount;

    double newReceived;
    double newPending;
    double refundToAdvance = 0;
    if (alreadyReceived >= newGrandTotal) {
      newReceived = newGrandTotal;
      newPending = 0;
      refundToAdvance = alreadyReceived - newGrandTotal;
    } else {
      newReceived = alreadyReceived;
      newPending = newGrandTotal - alreadyReceived;
    }
    final newStatus = newPending <= 0.01
        ? AppConstants.statusPaid
        : (newReceived > 0 ? AppConstants.statusPartialPaid : AppConstants.statusPending);

    await txn.update(
      'invoices',
      {
        'subtotal': newSubtotal,
        'discount_amount': newDiscountAmount,
        'gst_amount': newGstAmount,
        'grand_total': newGrandTotal,
        'received_amount': newReceived,
        'pending_amount': newPending,
        'status': newStatus,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [invoice.id],
    );

    if (invoice.customerId != null) {
      final custRows = await txn.query('customers', where: 'id = ?', whereArgs: [invoice.customerId]);
      if (custRows.isNotEmpty) {
        final customer = Customer.fromMap(custRows.first);
        final outstandingDrop = invoice.pendingAmount - newPending;
        final newOutstanding =
            (customer.totalOutstanding - outstandingDrop).clamp(0.0, double.infinity);
        final newAdvance = customer.advanceBalance + refundToAdvance;
        final newTotalPurchases =
            (customer.totalPurchases - reversedTotal).clamp(0.0, double.infinity);

        await txn.update(
          'customers',
          {
            'total_outstanding': newOutstanding,
            'advance_balance': newAdvance,
            'total_purchases': newTotalPurchases,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [invoice.customerId],
        );

        if (refundToAdvance > 0) {
          await txn.insert('payment_transactions', {
            'shop_id': invoice.shopId,
            'customer_id': invoice.customerId,
            'invoice_id': invoice.id,
            'type': 'refund',
            'amount': refundToAdvance,
            'payment_mode': 'adjustment',
            'notes': note,
            'created_at': now,
          });
        }

        // Matching write-off for the 'invoice_due' row createInvoice() may
        // have recorded for this bill — keeps the ledger's running balance
        // correct when a void/return shrinks or clears an unpaid due,
        // rather than leaving that due looking permanently outstanding.
        if (outstandingDrop > 0) {
          await txn.insert('payment_transactions', {
            'shop_id': invoice.shopId,
            'customer_id': invoice.customerId,
            'invoice_id': invoice.id,
            'type': 'invoice_due_reversal',
            'amount': outstandingDrop,
            'payment_mode': 'adjustment',
            'notes': note,
            'created_at': now,
          });
        }
      }
    }

    // Back the reversed portion out of that day's sales_summary row.
    final dateStr = invoice.createdAt.toIso8601String().substring(0, 10);
    final reversedProfit = reversedTotal - reversedCost;
    await txn.rawUpdate('''
      UPDATE sales_summary SET
        total_sales = MAX(0, total_sales - ?),
        total_cost = MAX(0, total_cost - ?),
        total_profit = total_profit - ?,
        total_items_sold = MAX(0, total_items_sold - ?),
        updated_at = ?
      WHERE date = ?
    ''', [reversedTotal, reversedCost, reversedProfit, reversedQtyTotal, now, dateStr]);
  }
}
