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

  /// Merges a cloud-pulled shopProfile.categories snapshot into the local
  /// category list for [shopId] — adds any category the cloud has that
  /// isn't already stored locally. Deliberately never deletes a local
  /// category just because it's absent from the cloud list.
  ///
  /// Categories have no id/UUID, created_at-only (no updated_at) and no
  /// deleted_at/tombstone of their own — see the table's schema in
  /// database_helper.dart — so there is no reliable way to tell "an admin
  /// removed this on the web" apart from "this was created locally a
  /// moment ago and hasn't reached the cloud yet". `syncNow()` always pulls
  /// before it pushes (see DataSyncRepository), so a category created
  /// right before tapping Cloud Sync is, at pull time, *by definition* not
  /// in the cloud's list yet — a destructive replace-with-cloud here
  /// deleted it before the push a few lines later ever got a chance to
  /// upload it, which was the actual bug: a newly created category
  /// vanishing the moment Cloud Sync ran. Treating the cloud list as
  /// additive-only, the same "never treat a partial/empty snapshot as
  /// authoritative" reasoning this method already used for the
  /// empty-list case, fixes that for the non-empty case too.
  ///
  /// `INSERT OR IGNORE` plus the table's `UNIQUE(shop_id, name)` constraint
  /// make this naturally idempotent and duplicate-proof no matter how many
  /// times sync runs against the same or overlapping snapshots.
  Future<void> mergeCategories(int shopId, List<String> names) async {
    final db = await _db.database;
    final incoming = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet();
    if (incoming.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    for (final name in incoming) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
        [shopId, name, now],
      );
    }
  }
}
