import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/utils/constants.dart';
import '../../../shared/models/item.dart';

class ItemRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Item>> getAllItems(int shopId) async {
    final db = await _db.database;
    final rows = await db.query(
      'items',
      where: 'shop_id = ? AND is_active = 1',
      whereArgs: [shopId],
      orderBy: 'name ASC',
    );
    final items = <Item>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      items.add(Item.fromMap(row, aliases: aliases));
    }
    return items;
  }

  Future<List<Item>> getLowStockItems(int shopId) async {
    final db = await _db.database;
    // stock_quantity > 0 matches Item.isLowStock and the Inventory
    // screen's own "low stock" filter — without it, out-of-stock items were
    // double-counted here (once as "low stock" on the dashboard, again as
    // "out of stock" on the Inventory screen), inflating the dashboard's count.
    final rows = await db.rawQuery(
      'SELECT * FROM items WHERE shop_id = ? AND is_active = 1 AND stock_quantity > 0 AND stock_quantity <= reorder_level ORDER BY stock_quantity ASC',
      [shopId],
    );
    final items = <Item>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      items.add(Item.fromMap(row, aliases: aliases));
    }
    return items;
  }

  Future<Item?> getItemBySku(int shopId, String sku) async {
    final db = await _db.database;
    final rows = await db.query(
      'items',
      where: 'shop_id = ? AND is_active = 1 AND LOWER(sku) = ?',
      whereArgs: [shopId, sku.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'] as int;
    final aliases = await _getAliases(id);
    return Item.fromMap(rows.first, aliases: aliases);
  }

  Future<Item?> getItemByBarcode(int shopId, String barcode) async {
    final db = await _db.database;
    // Normalize: trim whitespace and line endings so scanner output matches stored value.
    final normalized = barcode.trim().replaceAll(RegExp(r'[\r\n\t]'), '').toLowerCase();
    final rows = await db.query(
      'items',
      where: 'shop_id = ? AND is_active = 1 AND LOWER(barcode) = ?',
      whereArgs: [shopId, normalized],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      final aliases = await _getAliases(id);
      return Item.fromMap(rows.first, aliases: aliases);
    }
    // Fall back to SKU for backward compatibility.
    return getItemBySku(shopId, normalized);
  }

  /// Returns true if the barcode is not already used by any active item.
  Future<bool> isBarcodeUnique(String barcode, {int? excludeItemId}) async {
    final db = await _db.database;
    final where = excludeItemId != null
        ? 'is_active = 1 AND LOWER(barcode) = ? AND id != ?'
        : 'is_active = 1 AND LOWER(barcode) = ?';
    final args = excludeItemId != null
        ? [barcode.toLowerCase(), excludeItemId]
        : [barcode.toLowerCase()];
    final rows = await db.query('items', where: where, whereArgs: args, limit: 1);
    return rows.isEmpty;
  }

  /// Generates a globally unique VAI-prefixed barcode (e.g. VAI000001).
  Future<String> generateUniqueBarcode() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT barcode FROM items WHERE barcode LIKE 'VAI%' ORDER BY barcode DESC LIMIT 1",
    );
    int next = 1;
    if (rows.isNotEmpty) {
      final existing = rows.first['barcode'] as String?;
      if (existing != null && existing.length > 3) {
        next = (int.tryParse(existing.substring(3)) ?? 0) + 1;
      }
    }
    String candidate;
    do {
      candidate = 'VAI${next.toString().padLeft(6, '0')}';
      if (await isBarcodeUnique(candidate)) break;
      next++;
    } while (true);
    return candidate;
  }

  Future<Item?> getItemById(int id) async {
    final db = await _db.database;
    final rows = await db.query('items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final aliases = await _getAliases(id);
    return Item.fromMap(rows.first, aliases: aliases);
  }

  Future<List<Item>> searchItems(int shopId, String query) async {
    final db = await _db.database;
    final pattern = '%${query.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT p.* FROM items p
      LEFT JOIN item_aliases a ON p.id = a.item_id
      WHERE p.shop_id = ? AND p.is_active = 1
        AND (LOWER(p.name) LIKE ?
          OR LOWER(a.alias) LIKE ?
          OR LOWER(p.sku) LIKE ?
          OR LOWER(p.barcode) LIKE ?)
      ORDER BY p.name ASC
      LIMIT 20
    ''', [shopId, pattern, pattern, pattern, pattern]);
    final items = <Item>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      items.add(Item.fromMap(row, aliases: aliases));
    }
    return items;
  }

  Future<List<Item>> searchByAlias(int shopId, String alias) async {
    final db = await _db.database;
    final pattern = '%${alias.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT p.* FROM items p
      JOIN item_aliases a ON p.id = a.item_id
      WHERE p.shop_id = ? AND p.is_active = 1
        AND LOWER(a.alias) LIKE ?
      LIMIT 5
    ''', [shopId, pattern]);
    final items = <Item>[];
    for (final row in rows) {
      final al = await _getAliases(row['id'] as int);
      items.add(Item.fromMap(row, aliases: al));
    }
    return items;
  }

  Future<int> insertItem(Item item) async {
    final db = await _db.database;
    final map = item.toMap()..remove('id');
    final id = await db.insert('items', map);
    // Insert aliases
    for (final alias in item.aliases) {
      if (alias.trim().isNotEmpty) {
        await db.insert('item_aliases', {
          'item_id': id,
          'alias': alias.trim().toLowerCase(),
        });
      }
    }
    return id;
  }

  Future<void> updateItem(Item item) async {
    final db = await _db.database;
    final existing = await db.query('items',
        columns: ['image_path', 'stock_quantity'], where: 'id = ?', whereArgs: [item.id]);
    final oldImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;
    final oldStock = existing.isNotEmpty ? existing.first['stock_quantity'] as int : item.stockQuantity;

    final map = item.toMap();
    if (oldImagePath != item.imagePath) {
      // The picked image changed (or was removed) — the previously uploaded
      // Cloudinary URL, if any, no longer matches. Clear it so the next
      // cloud sync re-uploads the new image instead of keeping a stale one.
      map['image_url'] = null;
    }

    await db.transaction((txn) async {
      await txn.update('items', map, where: 'id = ?', whereArgs: [item.id]);
      // The dedicated stock-adjust flow (adjustStock()) always logs an
      // inventory_transactions row; editing the quantity field directly on
      // this form silently didn't, leaving a gap in the audit trail that
      // reports rely on for anything edited this way instead of via +/-.
      final delta = item.stockQuantity - oldStock;
      if (delta != 0) {
        await txn.insert('inventory_transactions', {
          'item_id': item.id,
          'invoice_id': null,
          'type': AppConstants.txnAdjustment,
          'quantity_change': delta,
          'stock_before': oldStock,
          'stock_after': item.stockQuantity,
          'notes': 'Edited via item form',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      // Update aliases
      await txn.delete('item_aliases', where: 'item_id = ?', whereArgs: [item.id]);
      for (final alias in item.aliases) {
        if (alias.trim().isNotEmpty) {
          await txn.insert('item_aliases', {
            'item_id': item.id,
            'alias': alias.trim().toLowerCase(),
          });
        }
      }
    });
  }

  /// Called after a successful Cloudinary upload during cloud sync — the
  /// only writer of this column besides the change-detection in
  /// [updateItem].
  Future<void> setImageUrl(int itemId, String url) async {
    final db = await _db.database;
    await db.update('items', {'image_url': url}, where: 'id = ?', whereArgs: [itemId]);
  }

  /// Writes a cloud-pulled item straight into the row matching its exact
  /// [item.id] (which may be negative for an admin-created record —
  /// SQLite's INTEGER PRIMARY KEY accepts that fine, and AUTOINCREMENT never
  /// assigns a value that low itself). Inserts if the id doesn't exist
  /// locally yet, replaces the whole row otherwise.
  ///
  /// Two fields are handled specially rather than taken from [item]:
  /// - image_url is written directly (not diffed against image_path like
  ///   [updateItem] does — that diff detects a *local* picked-image
  ///   change, which is meaningless here).
  /// - image_path is always kept as whatever this device already has for
  ///   this id (null for a brand-new record) — the cloud's copy of this
  ///   column is just whichever device last pushed it, a file path
  ///   meaningless on any other device, so it must never overwrite this
  ///   device's own reference to its own locally cached file.
  Future<void> upsertFromCloud(Item item) async {
    final db = await _db.database;
    final existing = await db.query('items',
        columns: ['image_path'], where: 'id = ?', whereArgs: [item.id]);
    final localImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;

    final map = item.toMap();
    map['image_path'] = localImagePath;
    map['image_url'] = item.imageUrl;
    // Same reasoning as deleteItem() — a cloud-side tombstone still
    // carries its original barcode in the pull payload, and writing that
    // through as-is would keep blocking the barcode's reuse via the
    // all-rows unique index even though the item is inactive.
    if (!item.isActive) map['barcode'] = null;
    await db.insert('items', map, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.delete('item_aliases', where: 'item_id = ?', whereArgs: [item.id]);
    for (final alias in item.aliases) {
      if (alias.trim().isNotEmpty) {
        await db.insert('item_aliases', {
          'item_id': item.id,
          'alias': alias.trim().toLowerCase(),
        });
      }
    }
  }

  Future<void> deleteItem(int id) async {
    final db = await _db.database;
    // Clearing the barcode here (not just is_active) matters because
    // idx_items_barcode is a UNIQUE index over *all* rows with a non-null
    // barcode, regardless of is_active — isBarcodeUnique() above only checks
    // active items, so without this a soft-deleted item would keep
    // silently blocking its old barcode from ever being reused: the app-level
    // check says "unique", the INSERT then throws an uncaught
    // DatabaseException.
    await db.update(
      'items',
      {'is_active': 0, 'barcode': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> adjustStock(int itemId, int quantityChange, String type,
      {int? invoiceId, String? notes}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('items', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [itemId]);
      final stockBefore = rows.first['stock_quantity'] as int;
      final stockAfter = stockBefore + quantityChange;
      await txn.update(
        'items',
        {'stock_quantity': stockAfter, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await txn.insert('inventory_transactions', {
        'item_id': itemId,
        'invoice_id': invoiceId,
        'type': type,
        'quantity_change': quantityChange,
        'stock_before': stockBefore,
        'stock_after': stockAfter,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<String>> _getAliases(int itemId) async {
    final db = await _db.database;
    final rows = await db.query('item_aliases', where: 'item_id = ?', whereArgs: [itemId]);
    return rows.map((r) => r['alias'] as String).toList();
  }

  Future<int> getItemCount(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM items WHERE shop_id = ? AND is_active = 1', [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  Future<int> getInStockCount(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM items WHERE shop_id = ? AND is_active = 1 AND stock_quantity > 0',
        [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  /// All items for [shopId] updated since [since] (or all, if null),
  /// including inactive/deactivated ones — used for cloud sync, which must
  /// mirror deactivation too. Unlike [getAllItems], not filtered by
  /// `is_active`.
  Future<List<Item>> getItemsUpdatedSince(int shopId, DateTime? since) async {
    final db = await _db.database;
    final rows = since == null
        ? await db.query('items', where: 'shop_id = ?', whereArgs: [shopId])
        : await db.query(
            'items',
            where: 'shop_id = ? AND updated_at > ?',
            whereArgs: [shopId, since.toIso8601String()],
          );
    final items = <Item>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      items.add(Item.fromMap(row, aliases: aliases));
    }
    return items;
  }

  /// Raw inventory-ledger rows for [shopId] created since [since] (or all, if
  /// null) — used for cloud sync. There's no dedicated model/repository for
  /// this append-only table, so rows are returned as plain maps.
  Future<List<Map<String, Object?>>> getInventoryTransactionsSince(
      int shopId, DateTime? since) async {
    final db = await _db.database;
    if (since == null) {
      return db.rawQuery('''
        SELECT it.* FROM inventory_transactions it
        JOIN items p ON p.id = it.item_id
        WHERE p.shop_id = ?
      ''', [shopId]);
    }
    return db.rawQuery('''
      SELECT it.* FROM inventory_transactions it
      JOIN items p ON p.id = it.item_id
      WHERE p.shop_id = ? AND it.created_at > ?
    ''', [shopId, since.toIso8601String()]);
  }
}
