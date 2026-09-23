import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/billing/repositories/invoice_repository.dart';
import 'package:vaani/features/billing/repositories/payment_transaction_repository.dart';
import 'package:vaani/features/customers/repositories/customer_repository.dart';
import 'package:vaani/features/inventory/repositories/item_repository.dart';
import 'package:vaani/shared/models/cart_item.dart';
import 'package:vaani/shared/models/customer.dart';
import 'package:vaani/shared/models/invoice.dart';
import 'package:vaani/shared/models/item.dart';
import 'package:vaani/shared/models/payment_transaction.dart';

/// Real repository code against a real (in-memory) SQLite database with the
/// production schema. The checkout arithmetic below mirrors
/// payment_bottom_sheet.dart's getters line for line (they live inside a
/// widget State and can't be called directly) — if that math changes, change
/// this helper with it.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late InvoiceRepository invoices;
  late CustomerRepository customers;
  late ItemRepository items;
  late PaymentTransactionRepository txns;
  const shopId = 1;
  late Item water; // ₹100, GST 0 to keep the arithmetic exact
  late int customerId;

  Future<Customer> cust() async => (await customers.getCustomerById(customerId))!;

  Future<void> outstandingEquals(double v, String why) async =>
      expect((await cust()).totalOutstanding, closeTo(v, 0.001), reason: why);
  Future<void> advanceEquals(double v, String why) async =>
      expect((await cust()).advanceBalance, closeTo(v, 0.001), reason: why);

  /// Mirrors PaymentBottomSheet for a registered customer.
  Future<Invoice> checkout({
    required double total,
    required double received, // physical money handed over now
    bool applyAdvance = true,
    int qty = 1,
  }) async {
    final c = await cust();
    final advanceApplied =
        (applyAdvance && c.advanceBalance > 0) ? min(c.advanceBalance, total) : 0.0;
    final netBillDue = max(0.0, total - advanceApplied);
    final pending = max(0.0, total - advanceApplied - received);
    final excess = max(0.0, received - netBillDue);
    final outstandingReduced = min(excess, c.totalOutstanding);
    final newAdvanceFromOverpay = excess - outstandingReduced;
    final newOutstanding = max(0.0, (c.totalOutstanding - outstandingReduced) + pending);
    final newAdvance = max(0.0, c.advanceBalance - advanceApplied + newAdvanceFromOverpay);
    final covered = min(received, netBillDue);
    final invoiceReceived = advanceApplied + covered;
    final status = pending == 0
        ? 'paid'
        : (advanceApplied + received > 0 ? 'partial_paid' : 'pending');

    final inv = Invoice(
      invoiceNumber: await invoices.getNextInvoiceNumber(shopId),
      shopId: shopId,
      customerId: customerId,
      customerName: c.name,
      subtotal: total,
      grandTotal: total,
      receivedAmount: invoiceReceived,
      pendingAmount: pending,
      paymentMode: 'cash',
      status: status,
      createdAt: DateTime.now(),
    );
    return invoices.createInvoice(
      invoice: inv,
      cartItems: [CartItem(item: water, quantity: qty)],
      customerId: customerId,
      newOutstanding: newOutstanding,
      newAdvanceBalance: newAdvance,
      paymentTransactions: [
        if (advanceApplied > 0)
          PendingPaymentTxn(type: 'advance_used', amount: advanceApplied, paymentMode: 'advance'),
        if (covered > 0)
          PendingPaymentTxn(type: 'bill_payment', amount: covered, paymentMode: 'cash'),
        if (outstandingReduced > 0)
          PendingPaymentTxn(
              type: 'outstanding_collection', amount: outstandingReduced, paymentMode: 'cash'),
        if (newAdvanceFromOverpay > 0)
          PendingPaymentTxn(
              type: 'advance_deposit', amount: newAdvanceFromOverpay, paymentMode: 'cash'),
      ],
    );
  }

  Future<double> sumInvoicePending() async {
    final list = await invoices.getInvoicesByCustomer(customerId);
    return list
        .where((i) => i.status != 'cancelled')
        .fold<double>(0, (s, i) => s + i.pendingAmount);
  }

  /// The ledger screen reconstructs history by walking backwards from
  /// totalOutstanding using each row's outstanding effect — for that to be
  /// honest, the effects of ALL rows must add up to exactly the current
  /// balance (i.e. the walk must land on 0 at the beginning of time).
  Future<void> ledgerReconciles() async {
    final rows = await txns.getByCustomer(customerId, limit: 1000);
    double delta(PaymentTransaction t) {
      switch (t.type) {
        case 'invoice_due':
        case 'manual_credit':
          return t.amount;
        case 'outstanding_collection':
        case 'invoice_due_reversal':
          return -t.amount;
        default:
          return 0;
      }
    }

    final sum = rows.fold<double>(0, (s, t) => s + delta(t));
    expect(sum, closeTo((await cust()).totalOutstanding, 0.001),
        reason: 'ledger rows must sum to the customer outstanding');
  }

  setUp(() async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('shops', {
      'id': shopId,
      'name': 'Test Shop',
      'owner_name': 'Owner',
      'phone': '9999999999',
      'created_at': now,
      'updated_at': now,
    });
    invoices = InvoiceRepository();
    customers = CustomerRepository();
    items = ItemRepository();
    txns = PaymentTransactionRepository();
    final pid = await items.insertItem(Item(
      shopId: shopId,
      name: 'Water',
      sellingPrice: 100,
      gstRate: 0,
      costPrice: 60,
      stockQuantity: 1000,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    water = (await items.getItemById(pid))!;
    customerId = await customers.insertCustomer(Customer(
      shopId: shopId,
      name: 'Ramesh',
      phone: '9111111111',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  group('udhar (credit sales)', () {
    test('partial payment leaves the remainder as outstanding', () async {
      final inv = await checkout(total: 1000, received: 400, qty: 10);
      expect(inv.pendingAmount, 600);
      expect(inv.status, 'partial_paid');
      await outstandingEquals(600, 'customer owes the unpaid part');
      expect(await sumInvoicePending(), 600);
      await ledgerReconciles();
    });

    test('nothing paid = fully udhar, status pending', () async {
      final inv = await checkout(total: 500, received: 0, qty: 5);
      expect(inv.status, 'pending');
      await outstandingEquals(500, 'whole bill is due');
      await ledgerReconciles();
    });

    test('a second udhar bill adds to the previous due', () async {
      await checkout(total: 500, received: 0, qty: 5);
      await checkout(total: 300, received: 100, qty: 3);
      await outstandingEquals(700, '500 old + 200 new');
      expect(await sumInvoicePending(), 700);
      await ledgerReconciles();
    });

    test('stock is deducted for credit sales too', () async {
      await checkout(total: 500, received: 0, qty: 5);
      expect((await items.getItemById(water.id!))!.stockQuantity, 995);
    });
  });

  group('paying old dues while billing (excess payment)', () {
    test('excess on a new bill reduces the customer outstanding', () async {
      await checkout(total: 600, received: 0, qty: 6); // owes 600
      await checkout(total: 200, received: 500, qty: 2); // 200 bill + 300 toward old due
      await outstandingEquals(300, '600 - 300 collected');
      await advanceEquals(0, 'nothing left over');
      await ledgerReconciles();
    });

    test('excess beyond all dues becomes advance', () async {
      await checkout(total: 200, received: 0, qty: 2); // owes 200
      await checkout(total: 100, received: 600, qty: 1); // 100 bill, 200 dues, 300 advance
      await outstandingEquals(0, 'dues cleared');
      await advanceEquals(300, 'leftover kept as advance');
      await ledgerReconciles();
    });

    // The customer-level balance drops, but which BILL got paid? If old
    // invoices keep showing their full pending amount, the invoice list and
    // "collect against dues" would still offer them — and collecting again
    // would double-count the same money.
    test('old invoices are settled too — invoice pending stays in step with outstanding',
        () async {
      await checkout(total: 600, received: 0, qty: 6);
      await checkout(total: 200, received: 500, qty: 2);
      await outstandingEquals(300, 'customer level');
      expect(await sumInvoicePending(), closeTo(300, 0.001),
          reason: 'sum of invoice pendings must match the customer balance');
    });
  });

  group('Previous Outstanding + Current Bill − Received = New Outstanding', () {
    // (previous outstanding, current bill, received now, expected new
    // outstanding, expected new advance) — floored at 0, any surplus
    // received beyond that becomes advance.
    final cases = <(double, double, double, double, double)>[
      (0, 500, 500, 0, 0),
      (0, 500, 200, 300, 0),
      (600, 500, 200, 900, 0),
      (600, 500, 0, 1100, 0),
      (600, 200, 200, 600, 0),
      (600, 200, 500, 300, 0),
      (600, 200, 800, 0, 0),
      (200, 100, 600, 0, 300),
      (600, 500, 900, 200, 0),
      (600, 500, 1100, 0, 0),
      (600, 500, 1300, 0, 200),
    ];
    for (final (prev, bill, received, wantOut, wantAdv) in cases) {
      test('prev $prev + bill $bill − received $received = $wantOut', () async {
        if (prev > 0) {
          await invoices.giveCredit(
              shopId: shopId, customerId: customerId, amount: prev, newOutstanding: prev);
        }
        await checkout(total: bill, received: received, qty: (bill / 100).round());
        await outstandingEquals(wantOut, 'new outstanding');
        await advanceEquals(wantAdv, 'new advance');
        await ledgerReconciles();
      });
    }
  });

  group('advance', () {
    test('advance deposit then a bill fully covered by advance', () async {
      await invoices.collectPayment(
        shopId: shopId,
        customerId: customerId,
        newOutstanding: 0,
        newAdvanceBalance: 500,
        paymentMode: 'cash',
        advanceDepositAmount: 500,
      );
      await advanceEquals(500, 'deposit recorded');
      final inv = await checkout(total: 300, received: 0, qty: 3);
      expect(inv.status, 'paid');
      expect(inv.receivedAmount, 300);
      await advanceEquals(200, 'advance consumed');
      await outstandingEquals(0, 'no due');
    });

    test('advance covers part, cash covers part, rest is due', () async {
      await invoices.collectPayment(
        shopId: shopId,
        customerId: customerId,
        newOutstanding: 0,
        newAdvanceBalance: 200,
        paymentMode: 'cash',
        advanceDepositAmount: 200,
      );
      final inv = await checkout(total: 800, received: 300, qty: 8);
      expect(inv.receivedAmount, 500);
      expect(inv.pendingAmount, 300);
      await advanceEquals(0, 'advance used up');
      await outstandingEquals(300, 'remainder is udhar');
      await ledgerReconciles();
    });
  });

  group('collecting dues later', () {
    test('collect against a specific invoice in two instalments', () async {
      final inv = await checkout(total: 600, received: 0, qty: 6);
      Future<void> collect(double amt) async {
        final list = await invoices.getOutstandingInvoicesByCustomer(customerId);
        final i = list.firstWhere((x) => x.id == inv.id);
        final newPending = max(0.0, i.pendingAmount - amt);
        await invoices.collectPayment(
          shopId: shopId,
          customerId: customerId,
          newOutstanding: max(0.0, (await cust()).totalOutstanding - amt),
          newAdvanceBalance: (await cust()).advanceBalance,
          paymentMode: 'upi',
          invoiceAllocations: [
            InvoicePaymentAllocation(
              invoiceId: i.id!,
              allocated: amt,
              newReceivedAmount: i.receivedAmount + amt,
              newPendingAmount: newPending,
              newStatus: newPending <= 0.01 ? 'paid' : 'partial_paid',
            ),
          ],
        );
      }

      await collect(250);
      await outstandingEquals(350, 'after first instalment');
      expect((await invoices.getInvoiceById(inv.id!))!.status, 'partial_paid');
      await collect(350);
      await outstandingEquals(0, 'cleared');
      expect((await invoices.getInvoiceById(inv.id!))!.status, 'paid');
      await ledgerReconciles();
    });
  });

  group('ledger entries (Give Credit)', () {
    test('give credit raises outstanding; general collection lowers it', () async {
      await invoices.giveCredit(
          shopId: shopId,
          customerId: customerId,
          amount: 200,
          newOutstanding: 200,
          notes: 'cash loan');
      await outstandingEquals(200, 'credit given');
      await invoices.collectPayment(
        shopId: shopId,
        customerId: customerId,
        newOutstanding: 50,
        newAdvanceBalance: 0,
        paymentMode: 'cash',
        generalCollectionAmount: 150,
      );
      await outstandingEquals(50, 'after partial repayment');
      await ledgerReconciles();
    });

    test('credit + bills + collections all reconcile', () async {
      await checkout(total: 600, received: 100, qty: 6); // 500 due
      await invoices.giveCredit(
          shopId: shopId, customerId: customerId, amount: 200, newOutstanding: 700);
      await checkout(total: 100, received: 0, qty: 1); // 800
      await outstandingEquals(800, 'sum of everything');
      await ledgerReconciles();
    });
  });

  group('void / return', () {
    test('voiding an unpaid bill removes its due from the customer', () async {
      final inv = await checkout(total: 600, received: 0, qty: 6);
      await invoices.voidInvoice(inv.id!);
      await outstandingEquals(0, 'due written off');
      expect((await items.getItemById(water.id!))!.stockQuantity, 1000,
          reason: 'stock restored');
      await ledgerReconciles();
    });

    test('voiding a partly paid bill refunds the paid part to advance', () async {
      final inv = await checkout(total: 600, received: 400, qty: 6);
      await invoices.voidInvoice(inv.id!);
      await outstandingEquals(0, 'due gone');
      await advanceEquals(400, 'money already paid is kept as credit');
      await ledgerReconciles();
    });

    test('returning part of an unpaid bill shrinks the due', () async {
      final inv = await checkout(total: 600, received: 0, qty: 6);
      final full = (await invoices.getInvoiceById(inv.id!))!;
      await invoices.returnItems(inv.id!, {full.items.first.id!: 2}); // 2 x 100
      await outstandingEquals(400, '600 - 200 returned');
      expect(await sumInvoicePending(), 400);
      await ledgerReconciles();
    });
  });

  group('services (inventory_enabled = false)', () {
    late Item service;

    setUp(() async {
      final sid = await items.insertItem(Item(
        shopId: shopId,
        name: 'Home Delivery',
        sellingPrice: 50,
        gstRate: 0,
        costPrice: 0,
        stockQuantity: 0,
        reorderLevel: 0,
        itemType: ItemType.service,
        inventoryEnabled: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      service = (await items.getItemById(sid))!;
    });

    Future<Invoice> checkoutService({required int qty}) async {
      final inv = Invoice(
        invoiceNumber: await invoices.getNextInvoiceNumber(shopId),
        shopId: shopId,
        customerId: customerId,
        customerName: (await cust()).name,
        subtotal: service.sellingPrice * qty,
        grandTotal: service.sellingPrice * qty,
        receivedAmount: service.sellingPrice * qty,
        pendingAmount: 0,
        paymentMode: 'cash',
        status: 'paid',
        createdAt: DateTime.now(),
      );
      return invoices.createInvoice(
        invoice: inv,
        cartItems: [CartItem(item: service, quantity: qty)],
        customerId: customerId,
      );
    }

    Future<int> movementCount(int itemId) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('inventory_transactions', where: 'item_id = ?', whereArgs: [itemId]);
      return rows.length;
    }

    test('billing a service never touches stock, however large the quantity', () async {
      // 9999 units of a service that has 0 "stock" would throw
      // InsufficientStockException for a product — it must not for a
      // service, since inventory_enabled gates the check entirely.
      final inv = await checkoutService(qty: 9999);
      expect(inv.id, isNotNull);
      expect((await items.getItemById(service.id!))!.stockQuantity, 0,
          reason: 'a service never accrues a stock count');
      expect(await movementCount(service.id!), 0,
          reason: 'no inventory_transactions row for a non-inventory item');
    });

    test('a bill mixing a product and a service only deducts the product\'s stock', () async {
      final inv = Invoice(
        invoiceNumber: await invoices.getNextInvoiceNumber(shopId),
        shopId: shopId,
        customerId: customerId,
        customerName: (await cust()).name,
        subtotal: 250,
        grandTotal: 250,
        receivedAmount: 250,
        pendingAmount: 0,
        paymentMode: 'cash',
        status: 'paid',
        createdAt: DateTime.now(),
      );
      final saved = await invoices.createInvoice(
        invoice: inv,
        cartItems: [
          CartItem(item: water, quantity: 2), // product: 2 x 100
          CartItem(item: service, quantity: 1), // service: 1 x 50
        ],
        customerId: customerId,
      );
      expect((await items.getItemById(water.id!))!.stockQuantity, 998, reason: 'product deducted');
      expect((await items.getItemById(service.id!))!.stockQuantity, 0, reason: 'service untouched');
      expect(await movementCount(water.id!), 1);
      expect(await movementCount(service.id!), 0);

      // Void the same mixed bill: product stock restores, service still
      // never gets a movement row.
      await invoices.voidInvoice(saved.id!);
      expect((await items.getItemById(water.id!))!.stockQuantity, 1000, reason: 'product restored');
      expect(await movementCount(water.id!), 2, reason: 'sale + restore');
      expect(await movementCount(service.id!), 0);
    });

    test(
        'voiding a bill follows the inventory_tracked SNAPSHOT taken at sale time, '
        'not the item\'s current inventory_enabled', () async {
      // Sell the service while it's genuinely a service (no stock touched).
      final inv = await checkoutService(qty: 1);

      // Later, the shop owner reclassifies it as inventory-tracked (e.g.
      // realized it should have been a stocked product all along). This
      // itself is a legitimate, separately-audited stock change (0 -> 5
      // via the edit form), so it's expected to add its own movement row —
      // that's not what this test is checking.
      final reclassified = service.copyWith(inventoryEnabled: true, stockQuantity: 5);
      await items.updateItem(reclassified);
      final movementsBeforeVoid = await movementCount(service.id!);

      // Voiding the OLD bill must not "restore" stock for units that were
      // never deducted in the first place — the live flag is now true, but
      // the sale itself never touched inventory.
      await invoices.voidInvoice(inv.id!);
      expect((await items.getItemById(service.id!))!.stockQuantity, 5,
          reason: 'nothing to restore — this sale never deducted stock');
      expect(await movementCount(service.id!), movementsBeforeVoid,
          reason: 'void adds no movement for a line that was never inventory-tracked');
    });
  });

  group('stock movements (Add/Remove Stock)', () {
    test('Add Stock records a dated, reasoned movement and raises the stock count', () async {
      final date = DateTime(2026, 9, 20);
      await items.adjustStock(water.id!, 20, 'restock',
          reason: 'Purchase', notes: 'Received from supplier', date: date);
      expect((await items.getItemById(water.id!))!.stockQuantity, 1020);

      final history = await items.getStockHistory(water.id!);
      expect(history, hasLength(1));
      expect(history.first['type'], 'restock');
      expect(history.first['reason'], 'Purchase');
      expect(history.first['notes'], 'Received from supplier');
      expect(history.first['quantity_change'], 20);
      expect(DateTime.parse(history.first['created_at'] as String), date);
    });

    test('Remove Stock lowers the count and is newest-first alongside a sale', () async {
      await checkout(total: 100, received: 100, qty: 1); // stock 1000 -> 999, 1 sale movement
      await items.adjustStock(water.id!, -3, 'damage', reason: 'Damaged', notes: 'Dropped in transit');
      expect((await items.getItemById(water.id!))!.stockQuantity, 996);

      final history = await items.getStockHistory(water.id!);
      expect(history, hasLength(2));
      expect(history.first['type'], 'damage', reason: 'newest movement first');
      expect(history.last['type'], 'sale');
    });
  });

  group('item images (multiple images per item)', () {
    test('no image is valid — nothing to fall back to but the letter avatar', () async {
      final gallery = await items.getImages(water.id!);
      expect(gallery, isEmpty);
      expect((await items.getItemById(water.id!))!.imagePath, isNull);
    });

    test('the first image added becomes primary automatically', () async {
      final id1 = await items.addImage(water.id!, imagePath: '/tmp/a.jpg');
      final gallery = await items.getImages(water.id!);
      expect(gallery, hasLength(1));
      expect(gallery.single.id, id1);
      expect(gallery.single.isPrimary, isTrue);
      expect((await items.getItemById(water.id!))!.imagePath, '/tmp/a.jpg',
          reason: 'items.image_path caches the primary image');
    });

    test('later images default to non-primary; setPrimaryImage switches the cache', () async {
      final id1 = await items.addImage(water.id!, imagePath: '/tmp/a.jpg');
      final id2 = await items.addImage(water.id!, imagePath: '/tmp/b.jpg');
      var gallery = await items.getImages(water.id!);
      expect(gallery.firstWhere((g) => g.id == id1).isPrimary, isTrue);
      expect(gallery.firstWhere((g) => g.id == id2).isPrimary, isFalse);
      expect((await items.getItemById(water.id!))!.imagePath, '/tmp/a.jpg');

      await items.setPrimaryImage(water.id!, id2);
      gallery = await items.getImages(water.id!);
      expect(gallery.firstWhere((g) => g.id == id1).isPrimary, isFalse);
      expect(gallery.firstWhere((g) => g.id == id2).isPrimary, isTrue);
      expect((await items.getItemById(water.id!))!.imagePath, '/tmp/b.jpg',
          reason: 'cache follows the new primary');
    });

    test('removing the primary promotes the next image by sort order', () async {
      final id1 = await items.addImage(water.id!, imagePath: '/tmp/a.jpg');
      final id2 = await items.addImage(water.id!, imagePath: '/tmp/b.jpg');

      await items.removeImage(water.id!, id1);
      final gallery = await items.getImages(water.id!);
      expect(gallery, hasLength(1));
      expect(gallery.single.id, id2);
      expect(gallery.single.isPrimary, isTrue);
      expect((await items.getItemById(water.id!))!.imagePath, '/tmp/b.jpg');
    });

    test('removing the last image clears the primary-image cache', () async {
      final id1 = await items.addImage(water.id!, imagePath: '/tmp/a.jpg');
      await items.removeImage(water.id!, id1);
      expect(await items.getImages(water.id!), isEmpty);
      expect((await items.getItemById(water.id!))!.imagePath, isNull);
    });

    test('reorderImages persists the new display order', () async {
      final id1 = await items.addImage(water.id!, imagePath: '/tmp/a.jpg');
      final id2 = await items.addImage(water.id!, imagePath: '/tmp/b.jpg');
      final id3 = await items.addImage(water.id!, imagePath: '/tmp/c.jpg');

      await items.reorderImages(water.id!, [id3, id1, id2]);
      final gallery = await items.getImages(water.id!);
      expect(gallery.map((g) => g.id).toList(), [id3, id1, id2]);
    });
  });
}
