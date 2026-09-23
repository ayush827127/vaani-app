import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/constants.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Test-only: opens an in-memory database with the real schema through
  /// the same onCreate/onConfigure path as production, and makes it the
  /// shared instance so repositories can be exercised against genuine
  /// SQLite. The caller must have set `databaseFactory` (e.g. to
  /// sqflite_common_ffi's) first.
  @visibleForTesting
  static Future<Database> openInMemoryForTesting() async {
    await _database?.close();
    _database = await openDatabase(
      inMemoryDatabasePath,
      version: AppConstants.dbVersion,
      onCreate: instance._onCreate,
      onConfigure: instance._onConfigure,
    );
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    // journal_mode returns a result row, so rawQuery() is required — execute() maps to
    // Android's execSQL() which rejects statements that return rows.
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE shops ADD COLUMN upi_id TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE invoices ADD COLUMN received_amount REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN pending_amount REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE customers ADD COLUMN total_outstanding REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      // Historical DDL — the table was still named "products" at this point
      // in a device's upgrade history (the products→items rename happens in
      // the v14 block below, which always runs after this one). Do not
      // "fix" these table names to match the current schema.
      await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL',
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shop_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          UNIQUE(shop_id, name),
          FOREIGN KEY (shop_id) REFERENCES shops(id)
        )
      ''');
      // Migrate categories already stored on products (historical table name
      // — see the note in the v4 block above).
      await db.rawInsert('''
        INSERT OR IGNORE INTO categories (shop_id, name, created_at)
        SELECT DISTINCT shop_id, category, datetime('now')
        FROM products WHERE category IS NOT NULL AND is_active = 1
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE customers ADD COLUMN advance_balance REAL NOT NULL DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shop_id INTEGER NOT NULL,
          customer_id INTEGER NOT NULL,
          invoice_id INTEGER,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          payment_mode TEXT NOT NULL DEFAULT 'cash',
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers(id),
          FOREIGN KEY (invoice_id) REFERENCES invoices(id)
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pay_txn_customer ON payment_transactions(customer_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pay_txn_invoice ON payment_transactions(invoice_id)');
    }
    if (oldVersion < 7) {
      // Invoices had no updated_at — needed to detect post-creation payment
      // updates for incremental cloud sync. Backfill existing rows to their
      // created_at value; new rows always populate it going forward.
      await db.execute('ALTER TABLE invoices ADD COLUMN updated_at TEXT');
      await db.execute('UPDATE invoices SET updated_at = created_at WHERE updated_at IS NULL');
    }
    if (oldVersion < 8) {
      // image_path/logo_path are local file paths, meaningless off-device.
      // These hold the Cloudinary URL uploaded during cloud sync, which is
      // what actually gets sent to the backend/admin panel.
      await db.execute('ALTER TABLE products ADD COLUMN image_url TEXT');
      await db.execute('ALTER TABLE shops ADD COLUMN logo_url TEXT');
    }
    if (oldVersion < 9) {
      // Two-way sync: an admin-panel delete is a tombstone the phone needs
      // to see and hide locally, not a hard local delete (which would risk
      // breaking other local records that still reference the deleted row,
      // e.g. a payment pointing at a deleted invoice). Items don't get
      // their own column — they already have is_active for exactly this.
      await db.execute('ALTER TABLE customers ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE payment_transactions ADD COLUMN deleted_at TEXT');
      // payment_transactions had no updated_at at all — needed so admin
      // edits/deletes to a payment are visible to "changed since" pull sync,
      // same reasoning as invoices' updated_at added in v7.
      await db.execute('ALTER TABLE payment_transactions ADD COLUMN updated_at TEXT');
      await db.execute(
          'UPDATE payment_transactions SET updated_at = created_at WHERE updated_at IS NULL');
    }
    if (oldVersion < 10) {
      // returned_quantity backs partial-return/void support — tracks how much
      // of each line has already been reversed so a line can't be returned
      // twice. cost_price snapshots the item's cost at sale time so
      // profit reports and later void/return reversals stay accurate even if
      // the item's cost is edited afterwards.
      await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN returned_quantity INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoice_items ADD COLUMN cost_price REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 11) {
      // Customer profile photo — local file path only (no image_url/cloud
      // sync counterpart, unlike items' image_path/image_url pair; this
      // is a device-local convenience, not synced to the backend).
      await db.execute('ALTER TABLE customers ADD COLUMN image_path TEXT');
    }
    if (oldVersion < 12) {
      // Marks an invoice as created via voice billing — the Basic plan's
      // 50-voice-invoice cap counts these specifically, so a manually
      // created invoice never counts against it (and vice versa).
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN is_voice_created INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 13) {
      // Customer photo now has a cloud counterpart, same pair as items'
      // image_path/image_url — this is the fix for a customer's photo
      // vanishing after a reinstall (v11's image_path alone is a local file
      // path, wiped along with the app's storage; nothing backed it up).
      await db.execute('ALTER TABLE customers ADD COLUMN image_url TEXT');
    }
    if (oldVersion < 14) {
      // "Product" → "Item": the app now bills both physical products and
      // non-inventory services through the same catalog. Renaming preserves
      // every existing row/id/relationship — RENAME TABLE/COLUMN in SQLite
      // (3.25+, well within what sqflite ships on both platforms) is a
      // metadata-only operation, not a copy, so nothing here can lose data
      // or leave a partially-migrated table if it fails.
      await db.execute('ALTER TABLE products RENAME TO items');
      await db.execute('ALTER TABLE product_aliases RENAME TO item_aliases');
      await db.execute('ALTER TABLE item_aliases RENAME COLUMN product_id TO item_id');
      await db.execute('ALTER TABLE invoice_items RENAME COLUMN product_id TO item_id');
      await db.execute('ALTER TABLE invoice_items RENAME COLUMN product_name TO item_name');
      // Every existing invoice line was necessarily a physical product (the
      // service concept didn't exist before this version) — same default
      // reasoning as items.item_type above.
      await db.execute(
          "ALTER TABLE invoice_items ADD COLUMN item_type TEXT NOT NULL DEFAULT 'PRODUCT'");
      // Whether THIS line actually deducted stock at sale time — the
      // authority void/return use to decide whether to restore stock,
      // independent of the item's CURRENT inventory_enabled (which may have
      // since changed). Without its own snapshot, voiding an old bill after
      // its item was later switched product↔service would either restore
      // stock that was never deducted, or fail to restore stock that was.
      // Every existing line predates the service concept, so it did deduct.
      await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN inventory_tracked INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE inventory_transactions RENAME COLUMN product_id TO item_id');
      // Add/Remove Stock now capture a short structured reason (Purchase,
      // Damaged, ...) separate from the free-text notes field.
      await db.execute('ALTER TABLE inventory_transactions ADD COLUMN reason TEXT');
      // New: every existing row is an inventory-tracked physical product —
      // exactly its current (unchanged) behavior. inventory_enabled, not
      // item_type, is what billing actually gates on; item_type mainly
      // drives what the UI shows/hides.
      await db.execute(
          "ALTER TABLE items ADD COLUMN item_type TEXT NOT NULL DEFAULT 'PRODUCT'");
      await db.execute(
          'ALTER TABLE items ADD COLUMN inventory_enabled INTEGER NOT NULL DEFAULT 1');

      // One item, many images — items.image_path/image_url stay as a
      // denormalized cache of the primary image (see the table's own doc
      // comment in _createTables). Every item that already had a single
      // image gets it carried over as that first, primary image — nothing
      // existing is lost.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_images (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          image_path TEXT,
          image_url TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          is_primary INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
        )
      ''');
      await db.rawInsert('''
        INSERT INTO item_images (item_id, image_path, image_url, sort_order, is_primary, created_at)
        SELECT id, image_path, image_url, 0, 1, datetime('now')
        FROM items WHERE image_path IS NOT NULL OR image_url IS NOT NULL
      ''');
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE,
        gst_number TEXT,
        address TEXT,
        logo_path TEXT,
        logo_url TEXT,
        currency TEXT NOT NULL DEFAULT 'INR',
        gst_enabled INTEGER NOT NULL DEFAULT 1,
        default_gst_rate REAL NOT NULL DEFAULT 5.0,
        upi_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        category TEXT,
        cost_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL,
        gst_rate REAL NOT NULL DEFAULT 5.0,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 10,
        image_path TEXT,
        image_url TEXT,
        item_type TEXT NOT NULL DEFAULT 'PRODUCT',
        inventory_enabled INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        alias TEXT NOT NULL,
        language TEXT NOT NULL DEFAULT 'en',
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
      )
    ''');

    // One-to-many, mirroring the local-file/Cloudinary-URL pattern
    // items.image_path/image_url already uses for its single legacy image —
    // this is that same pattern made one-to-many. is_primary decides which
    // image is used anywhere the rest of the app needs just one (ItemAvatar,
    // invoice PDFs, ...); items.image_path/image_url are kept as a
    // denormalized cache of that primary image, updated whenever it changes,
    // so every existing single-image read path keeps working unmodified.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        image_path TEXT,
        image_url TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        total_purchases REAL NOT NULL DEFAULT 0,
        total_bills INTEGER NOT NULL DEFAULT 0,
        total_outstanding REAL NOT NULL DEFAULT 0,
        advance_balance REAL NOT NULL DEFAULT 0,
        last_visit TEXT,
        image_path TEXT,
        image_url TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        shop_id INTEGER NOT NULL,
        customer_id INTEGER,
        customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        subtotal REAL NOT NULL,
        discount_type TEXT NOT NULL DEFAULT 'none',
        discount_value REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        gst_amount REAL NOT NULL DEFAULT 0,
        grand_total REAL NOT NULL,
        received_amount REAL NOT NULL DEFAULT 0,
        pending_amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        status TEXT NOT NULL DEFAULT 'paid',
        notes TEXT,
        is_voice_created INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (shop_id) REFERENCES shops(id),
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'PRODUCT',
        inventory_tracked INTEGER NOT NULL DEFAULT 1,
        quantity INTEGER NOT NULL,
        selling_price REAL NOT NULL,
        gst_rate REAL NOT NULL DEFAULT 0,
        gst_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        returned_quantity INTEGER NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        invoice_id INTEGER,
        type TEXT NOT NULL,
        reason TEXT,
        quantity_change INTEGER NOT NULL,
        stock_before INTEGER NOT NULL,
        stock_after INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (item_id) REFERENCES items(id),
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_summary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        total_sales REAL NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        total_profit REAL NOT NULL DEFAULT 0,
        total_bills INTEGER NOT NULL DEFAULT 0,
        total_items_sold INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        reference_id INTEGER,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        notes TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(shop_id, name),
        FOREIGN KEY (shop_id) REFERENCES shops(id)
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_shop ON items(shop_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_name ON items(name)');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_items_barcode ON items(barcode) WHERE barcode IS NOT NULL',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_aliases_item ON item_aliases(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_aliases_alias ON item_aliases(alias)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_shop_date ON invoices(shop_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_item ON invoice_items(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_trans_item ON inventory_transactions(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_summary_date ON sales_summary(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pay_txn_customer ON payment_transactions(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pay_txn_invoice ON payment_transactions(invoice_id)');
  }

  /// Forces every committed write sitting in the WAL file back into the
  /// main .db file. Must be called before copying the raw db file (backup
  /// export) — otherwise recent transactions that are still only in
  /// vaani.db-wal would be silently missing from the copy.
  Future<void> checkpoint() async {
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<void> resetDatabase() async {
    // Use the initialized database so all tables are guaranteed to exist.
    final db = await database;
    // Delete in FK-safe order (children before parents). payment_transactions
    // and categories were missing here — both reference shops/customers, so
    // skipping them left orphaned rows behind after every reset (account
    // deletion, and now also createShop()'s wipe-before-create).
    await db.delete('payment_transactions');
    await db.delete('inventory_transactions');
    await db.delete('invoice_items');
    await db.delete('invoices');
    await db.delete('sales_summary');
    await db.delete('notifications');
    await db.delete('item_aliases');
    await db.delete('categories');
    await db.delete('customers');
    await db.delete('items');
    await db.delete('shops');
  }
}
