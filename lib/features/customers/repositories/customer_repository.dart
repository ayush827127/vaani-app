import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../shared/models/customer.dart';

class CustomerRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Customer>> getAllCustomers(int shopId) async {
    final db = await _db.database;
    final rows = await db.query('customers',
        where: 'shop_id = ? AND deleted_at IS NULL', whereArgs: [shopId], orderBy: 'name ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<Customer>> searchCustomers(int shopId, String query) async {
    final db = await _db.database;
    final pattern = '%$query%';
    final rows = await db.query(
      'customers',
      where: 'shop_id = ? AND deleted_at IS NULL AND (name LIKE ? OR phone LIKE ?)',
      whereArgs: [shopId, pattern, pattern],
      orderBy: 'name ASC',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await _db.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  /// Returns the active customer already using [phone] in [shopId], if any
  /// — there's no DB-level uniqueness constraint on phone (unlike items'
  /// barcode), so this is the only thing that can catch a duplicate before
  /// it's saved. `null`/empty phones are never checked — many customers
  /// legitimately have no phone on file.
  Future<Customer?> getCustomerByPhone(int shopId, String phone) async {
    if (phone.trim().isEmpty) return null;
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'shop_id = ? AND deleted_at IS NULL AND phone = ?',
      whereArgs: [shopId, phone.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<int> insertCustomer(Customer customer) async {
    final db = await _db.database;
    final map = customer.toMap()..remove('id');
    return db.insert('customers', map);
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await _db.database;
    final existing = await db.query('customers',
        columns: ['image_path'], where: 'id = ?', whereArgs: [customer.id]);
    final oldImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;

    final map = customer.toMap();
    if (oldImagePath != customer.imagePath) {
      // Photo changed (or was removed) — the previously uploaded Cloudinary
      // URL, if any, no longer matches. Clear it so the next cloud sync
      // re-uploads the new photo instead of a stale one still resolving to
      // the old (or now-deleted) picture — same reasoning as
      // ShopRepository.updateShop()'s logo_url handling.
      map['image_url'] = null;
    }
    await db.update('customers', map, where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<void> updateCustomerStats(int customerId, double purchaseAmount) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE customers SET
        total_purchases = total_purchases + ?,
        total_bills = total_bills + 1,
        last_visit = ?,
        updated_at = ?
      WHERE id = ?
    ''', [purchaseAmount, DateTime.now().toIso8601String(), DateTime.now().toIso8601String(), customerId]);
  }

  Future<int> getCustomerCount(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM customers WHERE shop_id = ?', [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  Future<int> getNewCustomersThisMonth(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM customers
      WHERE shop_id = ? AND strftime('%Y-%m', created_at) = strftime('%Y-%m', 'now')
    ''', [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  Future<void> updateCustomerOutstanding(int customerId, double outstanding) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {
        'total_outstanding': outstanding,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  // Atomically sets both balance fields in a single UPDATE — avoids two round-trips.
  Future<void> updateCustomerBalances(
      int customerId, double outstanding, double advance) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {
        'total_outstanding': outstanding < 0 ? 0.0 : outstanding,
        'advance_balance': advance < 0 ? 0.0 : advance,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  Future<List<Customer>> getTopCustomers(int shopId, {int limit = 5}) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shopId],
      orderBy: 'total_purchases DESC',
      limit: limit,
    );
    return rows.map(Customer.fromMap).toList();
  }

  /// Called after a successful Cloudinary upload during cloud sync — the
  /// only writer of this column besides the change-detection in
  /// [upsertFromCloud] (mirrors ItemRepository.setImageUrl()).
  Future<void> setImageUrl(int customerId, String url) async {
    final db = await _db.database;
    await db.update('customers', {'image_url': url}, where: 'id = ?', whereArgs: [customerId]);
  }

  /// Writes a cloud-pulled customer straight into the row matching its
  /// exact [customer.id] — see the matching note on
  /// ItemRepository.upsertFromCloud().
  ///
  /// image_path is always kept as whatever this device already has for
  /// this id (a local file path meaningless on any other device); image_url
  /// is written straight from [customer] since it's the Cloudinary URL that
  /// is meaningful across devices.
  Future<void> upsertFromCloud(Customer customer) async {
    final db = await _db.database;
    final existing = await db.query('customers',
        columns: ['image_path'], where: 'id = ?', whereArgs: [customer.id]);
    final localImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;

    final map = customer.toMap();
    map['image_path'] = localImagePath;
    map['image_url'] = customer.imageUrl;
    map['deleted_at'] = customer.deletedAt?.toIso8601String();
    await db.insert('customers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// All customers for [shopId] updated since [since] (or all, if null) —
  /// used for cloud sync.
  Future<List<Customer>> getCustomersUpdatedSince(int shopId, DateTime? since) async {
    final db = await _db.database;
    final rows = since == null
        ? await db.query('customers', where: 'shop_id = ?', whereArgs: [shopId])
        : await db.query(
            'customers',
            where: 'shop_id = ? AND updated_at > ?',
            whereArgs: [shopId, since.toIso8601String()],
          );
    return rows.map(Customer.fromMap).toList();
  }
}
