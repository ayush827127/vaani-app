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
      // Migrate categories already stored on products
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
      // e.g. a payment pointing at a deleted invoice). Products don't get
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
      // twice. cost_price snapshots the product's cost at sale time so
      // profit reports and later void/return reversals stay accurate even if
      // the product's cost is edited afterwards.
      await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN returned_quantity INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoice_items ADD COLUMN cost_price REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 11) {
      // Customer profile photo — local file path only (no image_url/cloud
      // sync counterpart, unlike products' image_path/image_url pair; this
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
      // Customer photo now has a cloud counterpart, same pair as products'
      // image_path/image_url — this is the fix for a customer's photo
      // vanishing after a reinstall (v11's image_path alone is a local file
      // path, wiped along with the app's storage; nothing backed it up).
      await db.execute('ALTER TABLE customers ADD COLUMN image_url TEXT');
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
      CREATE TABLE IF NOT EXISTS products (
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
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (shop_id) REFERENCES shops(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        alias TEXT NOT NULL,
        language TEXT NOT NULL DEFAULT 'en',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
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
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        selling_price REAL NOT NULL,
        gst_rate REAL NOT NULL DEFAULT 0,
        gst_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        returned_quantity INTEGER NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        invoice_id INTEGER,
        type TEXT NOT NULL,
        quantity_change INTEGER NOT NULL,
        stock_before INTEGER NOT NULL,
        stock_after INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id),
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_aliases_product ON product_aliases(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_aliases_alias ON product_aliases(alias)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_shop_date ON invoices(shop_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoice_items_product ON invoice_items(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inv_trans_product ON inventory_transactions(product_id)');
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
    await db.delete('product_aliases');
    await db.delete('categories');
    await db.delete('customers');
    await db.delete('products');
    await db.delete('shops');
  }
}
