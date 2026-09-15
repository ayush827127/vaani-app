import 'package:sqflite/sqflite.dart';
import '../../../core/db/database_helper.dart';
import '../../../shared/models/product.dart';

class ProductRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Product>> getAllProducts(int shopId) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      where: 'shop_id = ? AND is_active = 1',
      whereArgs: [shopId],
      orderBy: 'name ASC',
    );
    final products = <Product>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      products.add(Product.fromMap(row, aliases: aliases));
    }
    return products;
  }

  Future<List<Product>> getLowStockProducts(int shopId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM products WHERE shop_id = ? AND is_active = 1 AND stock_quantity <= reorder_level ORDER BY stock_quantity ASC',
      [shopId],
    );
    final products = <Product>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      products.add(Product.fromMap(row, aliases: aliases));
    }
    return products;
  }

  Future<Product?> getProductBySku(int shopId, String sku) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      where: 'shop_id = ? AND is_active = 1 AND LOWER(sku) = ?',
      whereArgs: [shopId, sku.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'] as int;
    final aliases = await _getAliases(id);
    return Product.fromMap(rows.first, aliases: aliases);
  }

  Future<Product?> getProductByBarcode(int shopId, String barcode) async {
    final db = await _db.database;
    // Normalize: trim whitespace and line endings so scanner output matches stored value.
    final normalized = barcode.trim().replaceAll(RegExp(r'[\r\n\t]'), '').toLowerCase();
    print('[Barcode] Scanned raw: "${barcode.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}" (len:${barcode.length}) | Normalized: "$normalized" | shopId: $shopId');
    final rows = await db.query(
      'products',
      where: 'shop_id = ? AND is_active = 1 AND LOWER(barcode) = ?',
      whereArgs: [shopId, normalized],
      limit: 1,
    );
    print('[Barcode] DB matched: ${rows.length} row(s)');
    if (rows.isNotEmpty) {
      print('[Barcode] Product: "${rows.first['name']}", stored barcode: "${rows.first['barcode']}"');
      final id = rows.first['id'] as int;
      final aliases = await _getAliases(id);
      return Product.fromMap(rows.first, aliases: aliases);
    }
    // Fall back to SKU for backward compatibility.
    return getProductBySku(shopId, normalized);
  }

  /// Returns true if the barcode is not already used by any active product.
  Future<bool> isBarcodeUnique(String barcode, {int? excludeProductId}) async {
    final db = await _db.database;
    final where = excludeProductId != null
        ? 'is_active = 1 AND LOWER(barcode) = ? AND id != ?'
        : 'is_active = 1 AND LOWER(barcode) = ?';
    final args = excludeProductId != null
        ? [barcode.toLowerCase(), excludeProductId]
        : [barcode.toLowerCase()];
    final rows = await db.query('products', where: where, whereArgs: args, limit: 1);
    return rows.isEmpty;
  }

  /// Generates a globally unique VAI-prefixed barcode (e.g. VAI000001).
  Future<String> generateUniqueBarcode() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT barcode FROM products WHERE barcode LIKE 'VAI%' ORDER BY barcode DESC LIMIT 1",
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

  Future<Product?> getProductById(int id) async {
    final db = await _db.database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final aliases = await _getAliases(id);
    return Product.fromMap(rows.first, aliases: aliases);
  }

  Future<List<Product>> searchProducts(int shopId, String query) async {
    final db = await _db.database;
    final pattern = '%${query.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT p.* FROM products p
      LEFT JOIN product_aliases a ON p.id = a.product_id
      WHERE p.shop_id = ? AND p.is_active = 1
        AND (LOWER(p.name) LIKE ?
          OR LOWER(a.alias) LIKE ?
          OR LOWER(p.sku) LIKE ?
          OR LOWER(p.barcode) LIKE ?)
      ORDER BY p.name ASC
      LIMIT 20
    ''', [shopId, pattern, pattern, pattern, pattern]);
    final products = <Product>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      products.add(Product.fromMap(row, aliases: aliases));
    }
    return products;
  }

  Future<List<Product>> searchByAlias(int shopId, String alias) async {
    final db = await _db.database;
    final pattern = '%${alias.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT p.* FROM products p
      JOIN product_aliases a ON p.id = a.product_id
      WHERE p.shop_id = ? AND p.is_active = 1
        AND LOWER(a.alias) LIKE ?
      LIMIT 5
    ''', [shopId, pattern]);
    final products = <Product>[];
    for (final row in rows) {
      final al = await _getAliases(row['id'] as int);
      products.add(Product.fromMap(row, aliases: al));
    }
    return products;
  }

  Future<int> insertProduct(Product product) async {
    final db = await _db.database;
    final map = product.toMap()..remove('id');
    final id = await db.insert('products', map);
    // Insert aliases
    for (final alias in product.aliases) {
      if (alias.trim().isNotEmpty) {
        await db.insert('product_aliases', {
          'product_id': id,
          'alias': alias.trim().toLowerCase(),
        });
      }
    }
    return id;
  }

  Future<void> updateProduct(Product product) async {
    final db = await _db.database;
    final existing = await db.query('products',
        columns: ['image_path'], where: 'id = ?', whereArgs: [product.id]);
    final oldImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;

    final map = product.toMap();
    if (oldImagePath != product.imagePath) {
      // The picked image changed (or was removed) — the previously uploaded
      // Cloudinary URL, if any, no longer matches. Clear it so the next
      // cloud sync re-uploads the new image instead of keeping a stale one.
      map['image_url'] = null;
    }
    await db.update('products', map, where: 'id = ?', whereArgs: [product.id]);
    // Update aliases
    await db.delete('product_aliases', where: 'product_id = ?', whereArgs: [product.id]);
    for (final alias in product.aliases) {
      if (alias.trim().isNotEmpty) {
        await db.insert('product_aliases', {
          'product_id': product.id,
          'alias': alias.trim().toLowerCase(),
        });
      }
    }
  }

  /// Called after a successful Cloudinary upload during cloud sync — the
  /// only writer of this column besides the change-detection in
  /// [updateProduct].
  Future<void> setImageUrl(int productId, String url) async {
    final db = await _db.database;
    await db.update('products', {'image_url': url}, where: 'id = ?', whereArgs: [productId]);
  }

  /// Writes a cloud-pulled product straight into the row matching its exact
  /// [product.id] (which may be negative for an admin-created record —
  /// SQLite's INTEGER PRIMARY KEY accepts that fine, and AUTOINCREMENT never
  /// assigns a value that low itself). Inserts if the id doesn't exist
  /// locally yet, replaces the whole row otherwise.
  ///
  /// Two fields are handled specially rather than taken from [product]:
  /// - image_url is written directly (not diffed against image_path like
  ///   [updateProduct] does — that diff detects a *local* picked-image
  ///   change, which is meaningless here).
  /// - image_path is always kept as whatever this device already has for
  ///   this id (null for a brand-new record) — the cloud's copy of this
  ///   column is just whichever device last pushed it, a file path
  ///   meaningless on any other device, so it must never overwrite this
  ///   device's own reference to its own locally cached file.
  Future<void> upsertFromCloud(Product product) async {
    final db = await _db.database;
    final existing = await db.query('products',
        columns: ['image_path'], where: 'id = ?', whereArgs: [product.id]);
    final localImagePath = existing.isNotEmpty ? existing.first['image_path'] as String? : null;

    final map = product.toMap();
    map['image_path'] = localImagePath;
    map['image_url'] = product.imageUrl;
    await db.insert('products', map, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.delete('product_aliases', where: 'product_id = ?', whereArgs: [product.id]);
    for (final alias in product.aliases) {
      if (alias.trim().isNotEmpty) {
        await db.insert('product_aliases', {
          'product_id': product.id,
          'alias': alias.trim().toLowerCase(),
        });
      }
    }
  }

  Future<void> deleteProduct(int id) async {
    final db = await _db.database;
    await db.update('products', {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(int productId, int quantityChange, String type,
      {int? invoiceId, String? notes}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [productId]);
      final stockBefore = rows.first['stock_quantity'] as int;
      final stockAfter = stockBefore + quantityChange;
      await txn.update(
        'products',
        {'stock_quantity': stockAfter, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.insert('inventory_transactions', {
        'product_id': productId,
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

  Future<List<String>> _getAliases(int productId) async {
    final db = await _db.database;
    final rows = await db.query('product_aliases', where: 'product_id = ?', whereArgs: [productId]);
    return rows.map((r) => r['alias'] as String).toList();
  }

  Future<int> getProductCount(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM products WHERE shop_id = ? AND is_active = 1', [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  Future<int> getInStockCount(int shopId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM products WHERE shop_id = ? AND is_active = 1 AND stock_quantity > 0',
        [shopId]);
    return result.first['cnt'] as int? ?? 0;
  }

  /// All products for [shopId] updated since [since] (or all, if null),
  /// including inactive/deactivated ones — used for cloud sync, which must
  /// mirror deactivation too. Unlike [getAllProducts], not filtered by
  /// `is_active`.
  Future<List<Product>> getProductsUpdatedSince(int shopId, DateTime? since) async {
    final db = await _db.database;
    final rows = since == null
        ? await db.query('products', where: 'shop_id = ?', whereArgs: [shopId])
        : await db.query(
            'products',
            where: 'shop_id = ? AND updated_at > ?',
            whereArgs: [shopId, since.toIso8601String()],
          );
    final products = <Product>[];
    for (final row in rows) {
      final aliases = await _getAliases(row['id'] as int);
      products.add(Product.fromMap(row, aliases: aliases));
    }
    return products;
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
        JOIN products p ON p.id = it.product_id
        WHERE p.shop_id = ?
      ''', [shopId]);
    }
    return db.rawQuery('''
      SELECT it.* FROM inventory_transactions it
      JOIN products p ON p.id = it.product_id
      WHERE p.shop_id = ? AND it.created_at > ?
    ''', [shopId, since.toIso8601String()]);
  }
}
