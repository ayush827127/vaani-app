import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/billing/repositories/payment_transaction_repository.dart';
import 'package:vaani/features/customers/repositories/customer_repository.dart';
import 'package:vaani/shared/models/customer.dart';
import 'package:vaani/shared/models/payment_transaction.dart';

/// PaymentTransactionRepository.insert() is the single choke point every
/// payment/ledger mutation goes through, so it auto-captures the customer's
/// balance immediately before the row is written — these snapshot fields
/// are what the backend uses to detect a real concurrent-write conflict on
/// a customer's balance (mirroring how inventory transactions already let
/// it detect one on stock).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CustomerRepository customers;
  late PaymentTransactionRepository txns;
  const shopId = 1;
  late int customerId;

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
    customers = CustomerRepository();
    txns = PaymentTransactionRepository();
    customerId = await customers.insertCustomer(Customer(
      shopId: shopId,
      name: 'Ramesh',
      phone: '9111111111',
      totalOutstanding: 500,
      advanceBalance: 50,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  test('insert() auto-captures the customer\'s current balance when the caller supplies none', () async {
    final id = await txns.insert(PaymentTransaction(
      shopId: shopId,
      customerId: customerId,
      type: 'outstanding_collection',
      amount: 200,
      paymentMode: 'cash',
      createdAt: DateTime.now(),
    ));
    final saved = await txns.getById(id);
    expect(saved!.customerOutstandingBefore, 500);
    expect(saved.customerAdvanceBefore, 50);
  });

  test('insert() respects a caller-supplied snapshot instead of overwriting it', () async {
    final id = await txns.insert(PaymentTransaction(
      shopId: shopId,
      customerId: customerId,
      type: 'outstanding_collection',
      amount: 200,
      paymentMode: 'cash',
      createdAt: DateTime.now(),
      customerOutstandingBefore: 123,
      customerAdvanceBefore: 45,
    ));
    final saved = await txns.getById(id);
    expect(saved!.customerOutstandingBefore, 123);
    expect(saved.customerAdvanceBefore, 45);
  });

  test('each insert snapshots the balance as it stood at that moment, not a stale earlier value', () async {
    final firstId = await txns.insert(PaymentTransaction(
      shopId: shopId,
      customerId: customerId,
      type: 'outstanding_collection',
      amount: 200,
      paymentMode: 'cash',
      createdAt: DateTime.now(),
    ));
    expect((await txns.getById(firstId))!.customerOutstandingBefore, 500);

    // Simulate what actually applying that collection does to the customer's
    // running balance before the next transaction is recorded.
    final c = await customers.getCustomerById(customerId);
    await customers.updateCustomer(c!.copyWith(totalOutstanding: 300));

    final secondId = await txns.insert(PaymentTransaction(
      shopId: shopId,
      customerId: customerId,
      type: 'outstanding_collection',
      amount: 100,
      paymentMode: 'cash',
      createdAt: DateTime.now(),
    ));
    final second = await txns.getById(secondId);
    expect(second!.customerOutstandingBefore, 300,
        reason: 'must reflect the balance right before THIS transaction, not the first one\'s');
    expect(second.customerAdvanceBefore, 50);
  });

  test('a row created before this field existed (nulls from cloud/legacy data) stays null, never invented', () async {
    await txns.upsertFromCloud(PaymentTransaction(
      shopId: shopId,
      customerId: customerId,
      type: 'outstanding_collection',
      amount: 200,
      paymentMode: 'cash',
      createdAt: DateTime.now(),
    ));
    final rows = await txns.getByCustomer(customerId);
    expect(rows.single.customerOutstandingBefore, isNull);
    expect(rows.single.customerAdvanceBefore, isNull);
  });
}
