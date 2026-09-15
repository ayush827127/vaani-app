import '../../../core/db/database_helper.dart';

class CategoryRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<String>> getCategories(int shopId) async {
    final db = await _db.database;
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
    await db.delete(
      'categories',
      where: 'shop_id = ? AND name = ?',
      whereArgs: [shopId, name],
    );
  }

  /// Replaces the whole category list for [shopId] with [names] — used when
  /// merging a cloud-pulled shopProfile.categories snapshot. Categories
  /// aren't independently timestamped, so there's no incremental diff to
  /// apply; the cloud's list is always treated as the full authoritative set
  /// whenever a shop-profile change is pulled at all.
  Future<void> replaceCategories(int shopId, List<String> names) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('categories', where: 'shop_id = ?', whereArgs: [shopId]);
      final now = DateTime.now().toIso8601String();
      for (final name in names) {
        final trimmed = name.trim();
        if (trimmed.isEmpty) continue;
        await txn.rawInsert(
          'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
          [shopId, trimmed, now],
        );
      }
    });
  }
}
