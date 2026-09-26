import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';

/// Reproduces, and verifies the fix for, a real reported bug: a device that
/// had already reached dbVersion 14 on an earlier build — back when
/// `item_images` was folded into the v14 upgrade block instead of its own
/// version — would never see that block run again (sqflite only calls
/// onUpgrade when the stored version is *strictly less than* the target),
/// so it stayed permanently missing item_images: "DatabaseException(no such
/// table: item_images)". Splitting the table into its own v15 block, gated
/// on `oldVersion < 15`, is what actually fixes that for a device already
/// sitting at 14.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vaani_migration_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// The exact `items`/`invoice_items`/`inventory_transactions` shape a
  /// real device already at v14 has — i.e. post-Product→Item-rename, but
  /// from before item_images existed at all. Deliberately hand-written
  /// (not calling the app's own _createTables, which always builds the
  /// *current* schema) so this test can't accidentally pass just because
  /// both sides of the bug moved together.
  Future<void> createLegacyV14Database(String path) async {
    final db = await openDatabase(
      path,
      version: 14,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            image_path TEXT,
            image_url TEXT,
            item_type TEXT NOT NULL DEFAULT 'PRODUCT',
            inventory_enabled INTEGER NOT NULL DEFAULT 1,
            stock_quantity INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        // A genuine v14 device has these two tables already — just without
        // inventory_tracked/reason, which is exactly the state the v16
        // migration (tested further below) needs to find and fix.
        await db.execute('''
          CREATE TABLE invoice_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            item_name TEXT NOT NULL,
            item_type TEXT NOT NULL DEFAULT 'PRODUCT',
            quantity INTEGER NOT NULL,
            selling_price REAL NOT NULL,
            gst_rate REAL NOT NULL DEFAULT 0,
            gst_amount REAL NOT NULL DEFAULT 0,
            line_total REAL NOT NULL,
            returned_quantity INTEGER NOT NULL DEFAULT 0,
            cost_price REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE inventory_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            quantity_change INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        // Also genuinely present at v14, without previous_due — needed for
        // the v17 migration (tested further below) to have something to
        // find and fix.
        await db.execute('''
          CREATE TABLE invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_id INTEGER NOT NULL,
            customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
            grand_total REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'unpaid',
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    // A real shopkeeper's item that already had a single (pre-gallery)
    // photo — the migration's job is to carry this into item_images as
    // that item's first, primary image without losing it.
    await db.insert('items', {
      'shop_id': 1,
      'name': 'Teddy Bear',
      'image_path': '/data/user/0/app/files/item_images/teddy.jpg',
      'image_url': null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert('items', {
      'shop_id': 1,
      'name': 'Service Only',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.close();
  }

  test('a device stuck at v14 without item_images gets it on the next open, '
      'with its existing photo carried over as the primary image', () async {
    final path = p.join(tempDir.path, 'legacy.db');
    await createLegacyV14Database(path);

    // Re-open at the *current* target version — exactly what happens the
    // next time the shopkeeper opens the app after updating.
    final db = await openDatabase(
      path,
      version: 15,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );

    // The actual failing query from the bug report.
    final teddyRow = await db.query('items', where: 'name = ?', whereArgs: ['Teddy Bear']);
    final teddyId = teddyRow.single['id'] as int;
    final images = await db.query('item_images', where: 'item_id = ?', whereArgs: [teddyId]);

    expect(images, hasLength(1), reason: 'the existing single image was carried over');
    expect(images.single['image_path'], '/data/user/0/app/files/item_images/teddy.jpg');
    expect(images.single['is_primary'], 1);

    // The service-only item never had a photo — it should end up with an
    // empty gallery, not a spurious row.
    final serviceRow = await db.query('items', where: 'name = ?', whereArgs: ['Service Only']);
    final serviceId = serviceRow.single['id'] as int;
    final serviceImages = await db.query('item_images', where: 'item_id = ?', whereArgs: [serviceId]);
    expect(serviceImages, isEmpty);

    await db.close();
  });

  test('running the v15 upgrade twice (idempotent) never duplicates the '
      'carried-over image', () async {
    final path = p.join(tempDir.path, 'legacy2.db');
    await createLegacyV14Database(path);

    var db = await openDatabase(
      path,
      version: 15,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );
    await db.close();

    // Simulate the migration block somehow running again against the same
    // already-migrated database (e.g. a future version bump that re-checks
    // this range, or a manual re-run) — CREATE TABLE IF NOT EXISTS and the
    // "already has a row" guard on the backfill INSERT must make this a
    // true no-op.
    db = await openDatabase(path, version: 15);
    await DatabaseHelper.upgradeForTesting(db, 14, 15);

    final teddyRow = await db.query('items', where: 'name = ?', whereArgs: ['Teddy Bear']);
    final teddyId = teddyRow.single['id'] as int;
    final images = await db.query('item_images', where: 'item_id = ?', whereArgs: [teddyId]);
    expect(images, hasLength(1), reason: 're-running the migration must not duplicate the image');

    await db.close();
  });

  test('a fresh install (onCreate) gets item_images natively, no upgrade needed', () async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    // Table exists and the exact query from the bug report succeeds.
    final rows = await db.query('item_images', where: 'item_id = ?', whereArgs: [999]);
    expect(rows, isEmpty);
  });

  test('a fresh install also has invoice_items.inventory_tracked and '
      'inventory_transactions.reason natively, no upgrade needed', () async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    final itemCols = await db.rawQuery("PRAGMA table_info(invoice_items)");
    expect(itemCols.any((c) => c['name'] == 'inventory_tracked'), isTrue);
    final txnCols = await db.rawQuery("PRAGMA table_info(inventory_transactions)");
    expect(txnCols.any((c) => c['name'] == 'reason'), isTrue);
  });

  /// The exact shape a real device stuck in the *second* instance of the
  /// same class of bug has: `invoice_items.inventory_tracked` and
  /// `inventory_transactions.reason` were added into the v14 upgrade block
  /// in a change that never bumped dbVersion (see the v14→v15 item_images
  /// split above, which is the first time this exact mistake happened).
  /// Any device already at v14 before that change — including, after the
  /// v15 split shipped, every device auto-upgraded straight to v15 for
  /// item_images — has v15's schema for everything else, but never got
  /// either column. Hand-written for the same reason as
  /// createLegacyV14Database above.
  Future<void> createLegacyV15DatabaseMissingV16Columns(String path) async {
    final db = await openDatabase(
      path,
      version: 15,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_id INTEGER NOT NULL,
            customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
            grand_total REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'unpaid',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE invoice_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            item_name TEXT NOT NULL,
            item_type TEXT NOT NULL DEFAULT 'PRODUCT',
            quantity INTEGER NOT NULL,
            selling_price REAL NOT NULL,
            gst_rate REAL NOT NULL DEFAULT 0,
            gst_amount REAL NOT NULL DEFAULT 0,
            line_total REAL NOT NULL,
            returned_quantity INTEGER NOT NULL DEFAULT 0,
            cost_price REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE inventory_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            quantity_change INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE item_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            image_path TEXT,
            image_url TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_primary INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    await db.close();
  }

  test(
      'a device stuck at v15 without invoice_items.inventory_tracked gets it on the '
      'next open, and the exact bill-creation INSERT from the bug report now succeeds',
      () async {
    final path = p.join(tempDir.path, 'legacy_v15.db');
    await createLegacyV15DatabaseMissingV16Columns(path);

    final db = await openDatabase(
      path,
      version: 16,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );

    final itemCols = await db.rawQuery("PRAGMA table_info(invoice_items)");
    expect(itemCols.any((c) => c['name'] == 'inventory_tracked'), isTrue);
    final txnCols = await db.rawQuery("PRAGMA table_info(inventory_transactions)");
    expect(txnCols.any((c) => c['name'] == 'reason'), isTrue);

    // The exact failing INSERT from the bug report.
    final invoiceId = await db.insert('invoices', {
      'shop_id': 1,
      'customer_name': 'Walk-in Customer',
      'grand_total': 100,
      'status': 'paid',
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('invoice_items', {
      'invoice_id': invoiceId,
      'item_id': 1,
      'item_name': 'Sprite',
      'item_type': 'PRODUCT',
      'inventory_tracked': 1,
      'quantity': 2,
      'selling_price': 50,
      'gst_rate': 5,
      'gst_amount': 5,
      'line_total': 100,
      'returned_quantity': 0,
      'cost_price': 35,
    });

    final row = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    expect(row.single['inventory_tracked'], 1);

    await db.close();
  });

  test('running the v16 upgrade twice (idempotent) does not throw "duplicate column"', () async {
    final path = p.join(tempDir.path, 'legacy_v15_twice.db');
    await createLegacyV15DatabaseMissingV16Columns(path);

    var db = await openDatabase(
      path,
      version: 16,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );
    await db.close();

    // Re-running the same upgrade range against an already-migrated
    // database must not throw "duplicate column name" — the PRAGMA guard
    // is what makes this safe.
    db = await openDatabase(path, version: 16);
    await DatabaseHelper.upgradeForTesting(db, 15, 16);

    final itemCols = await db.rawQuery("PRAGMA table_info(invoice_items)");
    expect(itemCols.where((c) => c['name'] == 'inventory_tracked'), hasLength(1));

    await db.close();
  });

  test('a device without invoices.previous_due gets it on upgrade to v17, '
      'and inserting a bill with it now succeeds', () async {
    final path = p.join(tempDir.path, 'legacy_v16.db');
    await createLegacyV15DatabaseMissingV16Columns(path);

    final db = await openDatabase(
      path,
      version: 17,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );

    final invoiceCols = await db.rawQuery("PRAGMA table_info(invoices)");
    expect(invoiceCols.any((c) => c['name'] == 'previous_due'), isTrue);

    final invoiceId = await db.insert('invoices', {
      'shop_id': 1,
      'customer_name': 'Aditya Singh',
      'grand_total': 100,
      'status': 'paid',
      'created_at': DateTime.now().toIso8601String(),
      'previous_due': 75,
    });
    final row = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    expect(row.single['previous_due'], 75);

    await db.close();
  });

  test('running the v17 upgrade twice (idempotent) does not throw "duplicate column"', () async {
    final path = p.join(tempDir.path, 'legacy_v16_twice.db');
    await createLegacyV15DatabaseMissingV16Columns(path);

    var db = await openDatabase(
      path,
      version: 17,
      onUpgrade: (db, oldV, newV) => DatabaseHelper.upgradeForTesting(db, oldV, newV),
    );
    await db.close();

    db = await openDatabase(path, version: 17);
    await DatabaseHelper.upgradeForTesting(db, 16, 17);

    final invoiceCols = await db.rawQuery("PRAGMA table_info(invoices)");
    expect(invoiceCols.where((c) => c['name'] == 'previous_due'), hasLength(1));

    await db.close();
  });

  test('a fresh install also has invoices.previous_due natively, no upgrade needed', () async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    final invoiceCols = await db.rawQuery("PRAGMA table_info(invoices)");
    expect(invoiceCols.any((c) => c['name'] == 'previous_due'), isTrue);
  });
}
