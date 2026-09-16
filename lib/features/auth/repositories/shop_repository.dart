import '../../../core/db/database_helper.dart';
import '../../../shared/models/shop.dart';

class ShopRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<Shop?> getShop() async {
    final db = await _db.database;
    // A device is only ever supposed to hold one shop row — createShop()
    // enforces that going forward by wiping any existing shop before
    // inserting a new one — but this orders by id DESC as a safety net for
    // any row left over from before that fix existed, so it deterministically
    // picks the most recently created shop rather than "whatever SQLite
    // happens to return first".
    final rows = await db.query('shops', orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    return Shop.fromMap(rows.first);
  }

  Future<Shop?> getShopByPhone(String phone) async {
    final db = await _db.database;
    final rows = await db.query('shops', where: 'phone = ?', whereArgs: [phone]);
    if (rows.isEmpty) return null;
    return Shop.fromMap(rows.first);
  }

  /// Creates the device's shop. A device only ever holds one shop's data at
  /// a time, but nothing previously enforced that — logging out and setting
  /// up (or cloud-restoring) a *different* shop on the same device could
  /// leave a second `shops` row behind with the old shop's products,
  /// customers, and invoices still in their tables underneath it. Wiping
  /// first guarantees a clean slate for the new shop; it's a no-op on a
  /// genuinely fresh install since there's nothing to wipe.
  Future<int> createShop(Shop shop) async {
    await _db.resetDatabase();
    final db = await _db.database;
    final map = shop.toMap()..remove('id');
    return db.insert('shops', map);
  }

  Future<void> updateShop(Shop shop) async {
    final db = await _db.database;
    final existing = await db.query('shops',
        columns: ['logo_path'], where: 'id = ?', whereArgs: [shop.id]);
    final oldLogoPath = existing.isNotEmpty ? existing.first['logo_path'] as String? : null;

    final map = shop.toMap();
    if (oldLogoPath != shop.logoPath) {
      // Logo changed (or was removed) — the previously uploaded Cloudinary
      // URL, if any, no longer matches. Clear it so the next cloud sync
      // re-uploads the new logo instead of keeping a stale one.
      map['logo_url'] = null;
    }
    await db.update('shops', map, where: 'id = ?', whereArgs: [shop.id]);
  }

  /// Called after a successful Cloudinary upload during cloud sync — the
  /// only writer of this column besides the change-detection in
  /// [updateShop].
  Future<void> setLogoUrl(int shopId, String url) async {
    final db = await _db.database;
    await db.update('shops', {'logo_url': url}, where: 'id = ?', whereArgs: [shopId]);
  }

  /// Direct field writer for a cloud-pulled shop profile — bypasses
  /// [updateShop]'s logo-path-diff side effect (same reasoning as
  /// ProductRepository.upsertFromCloud() and image_url). Always an UPDATE of
  /// the single existing local shop row, never an insert (a device only
  /// ever has one shop). Categories live in a separate table — see
  /// CategoryRepository.replaceCategories().
  Future<void> mergeFromCloud({
    required int shopId,
    required String name,
    required String ownerName,
    String? address,
    String? gstNumber,
    required String currency,
    required bool gstEnabled,
    required double defaultGstRate,
    String? upiId,
    String? logoUrl,
    required DateTime updatedAt,
  }) async {
    final db = await _db.database;
    await db.update(
      'shops',
      {
        'name': name,
        'owner_name': ownerName,
        'address': address,
        'gst_number': gstNumber,
        'currency': currency,
        'gst_enabled': gstEnabled ? 1 : 0,
        'default_gst_rate': defaultGstRate,
        'upi_id': upiId,
        'logo_url': logoUrl,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [shopId],
    );
  }

  Future<void> updatePhone(int shopId, String newPhone) async {
    final db = await _db.database;
    await db.update(
      'shops',
      {'phone': newPhone, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [shopId],
    );
  }

  /// Wipes all data — used for account deletion.
  Future<void> deleteShopData() => _db.resetDatabase();
}
