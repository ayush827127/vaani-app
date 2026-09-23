import '../../../core/db/database_helper.dart';

class CategoryRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<String>> getCategories(int shopId) async {
    final db = await _db.database;

    // The billing screen builds its category chips from items' own
    // `category` values, while this table is what the Items screen and
    // the category picker read — nothing kept the two in step, so a shop
    // could have items tagged "Drinks"/"Soft Drinks" (visible in
    // billing) and an empty categories table ("Category not found" in
    // Items). Any category an active item already uses is by
    // definition a real category, so fold those in (idempotent, and it
    // also means the list pushed to the cloud is complete).
    final used = await db.rawQuery(
      "SELECT DISTINCT TRIM(category) AS name FROM items "
      "WHERE shop_id = ? AND is_active = 1 AND category IS NOT NULL AND TRIM(category) != ''",
      [shopId],
    );
    final now = DateTime.now().toIso8601String();
    for (final r in used) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
        [shopId, r['name'], now],
      );
    }

    final rows = await db.query(
      'categories',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> addCategory(int shopId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await _db.database;
    await db.rawInsert(
      'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
      [shopId, trimmed, DateTime.now().toIso8601String()],
    );
  }

  Future<void> deleteCategory(int shopId, String name) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'categories',
        where: 'shop_id = ? AND name = ?',
        whereArgs: [shopId, name],
      );
      // Without this, a item still holding this category name is
      // orphaned — permanently invisible in every category filter chip
      // (which only lists categories that still exist) while still counted
      // under "All", since nothing else ever clears item.category.
      await txn.update(
        'items',
        {'category': null, 'updated_at': DateTime.now().toIso8601String()},
        where: 'shop_id = ? AND category = ?',
        whereArgs: [shopId, name],
      );
    });
  }

  /// Replaces the whole category list for [shopId] with [names] — used when
  /// merging a cloud-pulled shopProfile.categories snapshot. Categories
  /// aren't independently timestamped, so there's no incremental diff to
  /// apply; the cloud's list is always treated as the full authoritative set
  /// whenever a shop-profile change is pulled at all.
  Future<void> replaceCategories(int shopId, List<String> names) async {
    final db = await _db.database;
    final incoming = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet();
    // An empty snapshot means the cloud simply has no category list yet (a
    // shop that never pushed one), not that an admin deleted every
    // category — treating it as authoritative would wipe the local list
    // and null every item's category.
    if (incoming.isEmpty) return;
    await db.transaction((txn) async {
      final existingRows =
          await txn.query('categories', columns: ['name'], where: 'shop_id = ?', whereArgs: [shopId]);
      final existingNames = existingRows.map((r) => r['name'] as String).toSet();
      final removed = existingNames.difference(incoming);

      await txn.delete('categories', where: 'shop_id = ?', whereArgs: [shopId]);
      final now = DateTime.now().toIso8601String();
      for (final name in incoming) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
          [shopId, name, now],
        );
      }

      // Same reasoning as deleteCategory() — an admin removing a category
      // via the web panel drove this same code path (cloud pull → replace)
      // with no item-side cleanup, orphaning any item still holding
      // that category name.
      for (final removedName in removed) {
        await txn.update(
          'items',
          {'category': null, 'updated_at': now},
          where: 'shop_id = ? AND category = ?',
          whereArgs: [shopId, removedName],
        );
      }
    });
  }
}
