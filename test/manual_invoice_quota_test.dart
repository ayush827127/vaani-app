import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/billing/repositories/invoice_repository.dart';

/// Exercises InvoiceRepository.countManualInvoicesThisMonth — the local,
/// offline-first gate behind the Basic plan's separate monthly cap on
/// manually-created invoices (see AppConstants.basicPlanManualInvoiceLimit
/// and payment_bottom_sheet.dart's call site). Invoices are inserted
/// directly rather than through the full checkout flow — this is a unit
/// test of the count query itself, not of invoice creation.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const shopId = 1;
  final repo = InvoiceRepository();

  Future<void> seedInvoice({
    required String number,
    required bool isVoiceCreated,
    required DateTime createdAt,
    bool deleted = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('invoices', {
      'invoice_number': number,
      'shop_id': shopId,
      'customer_name': 'Walk-in Customer',
      'subtotal': 100,
      'grand_total': 100,
      'is_voice_created': isVoiceCreated ? 1 : 0,
      'deleted_at': deleted ? DateTime.now().toIso8601String() : null,
      'created_at': createdAt.toIso8601String(),
    });
  }

  setUp(() async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('shops', {
      'id': shopId, 'name': 'Test Shop', 'owner_name': 'Owner', 'phone': '9999999999',
      'created_at': now, 'updated_at': now,
    });
  });

  test('counts only manually-created invoices from this calendar month', () async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 15);
    final lastMonth = DateTime(now.year, now.month - 1, 15);

    await seedInvoice(number: 'INV-1', isVoiceCreated: false, createdAt: thisMonth);
    await seedInvoice(number: 'INV-2', isVoiceCreated: false, createdAt: thisMonth);
    // Voice-created — belongs to the separate lifetime voice cap, not this one.
    await seedInvoice(number: 'INV-3', isVoiceCreated: true, createdAt: thisMonth);
    // Manual, but from last month — shouldn't count toward this month's cap.
    await seedInvoice(number: 'INV-4', isVoiceCreated: false, createdAt: lastMonth);
    // Manual, this month, but soft-deleted — a voided/deleted bill shouldn't
    // still count against the cap.
    await seedInvoice(number: 'INV-5', isVoiceCreated: false, createdAt: thisMonth, deleted: true);

    final count = await repo.countManualInvoicesThisMonth(shopId);
    expect(count, 2);
  });

  test('a shop with no invoices at all counts as zero, not an error', () async {
    final count = await repo.countManualInvoicesThisMonth(shopId);
    expect(count, 0);
  });

  test('does not count another shop\'s invoices', () async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('shops', {
      'id': 2, 'name': 'Other Shop', 'owner_name': 'Owner 2', 'phone': '8888888888',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('invoices', {
      'invoice_number': 'OTHER-1',
      'shop_id': 2,
      'customer_name': 'Walk-in Customer',
      'subtotal': 100,
      'grand_total': 100,
      'is_voice_created': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    final count = await repo.countManualInvoicesThisMonth(shopId);
    expect(count, 0);
  });
}
