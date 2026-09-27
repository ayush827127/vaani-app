import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/inventory/repositories/item_repository.dart';
import 'package:vaani/shared/models/item.dart';

/// Reproduces, and verifies the fix for, a real reported bug: an item
/// ("dosa", a service) with two locally-added images showed only one image
/// after Cloud Sync, and that one rendered as the small header icon instead
/// of the full gallery banner every other item gets.
///
/// Root cause — the item_images gallery table (the full multi-image
/// gallery) had no cloud representation at all: push
/// (DataSyncRepository._itemJson) only ever sent the single denormalized
/// items.image_path/image_url cache, and pull only ever wrote that same
/// single field back via ItemRepository.upsertFromCloud. A second/third
/// image never reached the cloud, so any pull that rewrote this item locally
/// (e.g. on another device, or after this item's cache field was refreshed)
/// left item_images empty or single-row, and the Item Details page's gallery
/// (which reads item_images via getImages, not the single cache field) fell
/// back to the old single-icon ItemAvatar treatment.
///
/// The fix threads the item's full gallery through both directions of sync:
/// push includes every uploaded image (not just the primary) as an inline
/// 'images' list on the item payload; pull rebuilds item_images from that
/// list via upsertFromCloud's images parameter, matching incoming URLs
/// against this device's own rows so a locally cached file path is never
/// discarded just because the cloud only knows the URL.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late ItemRepository items;
  const shopId = 1;
  late int itemId;

  setUp(() async {
    final db = await DatabaseHelper.openInMemoryForTesting();
    items = ItemRepository();
    await db.insert('shops', {
      'id': shopId,
      'name': 'Test Shop',
      'owner_name': 'Test Owner',
      'phone': '9999999999',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    itemId = await items.insertItem(Item(
      shopId: shopId,
      name: 'Dosa',
      itemType: ItemType.service,
      sellingPrice: 60,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  Item cloudItemFor(int id) {
    final existingUpdatedAt = DateTime.now().add(const Duration(minutes: 1));
    return Item(
      id: id,
      shopId: shopId,
      name: 'Dosa',
      itemType: ItemType.service,
      sellingPrice: 60,
      imageUrl: 'https://cloud/1.jpg',
      createdAt: existingUpdatedAt,
      updatedAt: existingUpdatedAt,
    );
  }

  test('a 2-image gallery pulled from the cloud survives in full, not just the primary', () async {
    await items.upsertFromCloud(cloudItemFor(itemId), images: [
      {'imageUrl': 'https://cloud/1.jpg', 'sortOrder': 0, 'isPrimary': true},
      {'imageUrl': 'https://cloud/2.jpg', 'sortOrder': 1, 'isPrimary': false},
    ]);

    final gallery = await items.getImages(itemId);
    expect(gallery, hasLength(2), reason: 'both images must survive the pull, not just the primary');
    expect(gallery[0].imageUrl, 'https://cloud/1.jpg');
    expect(gallery[0].isPrimary, isTrue);
    expect(gallery[1].imageUrl, 'https://cloud/2.jpg');
    expect(gallery[1].isPrimary, isFalse);

    final item = await items.getItemById(itemId);
    expect(item!.imageUrl, 'https://cloud/1.jpg',
        reason: 'the single-image cache still mirrors the primary, for old read paths');
  });

  test('this device\'s own local file path is kept when the cloud echoes back the same URL', () async {
    final imageId = await items.addImage(itemId, imagePath: '/local/dosa.jpg');
    await items.setImageImageUrl(imageId, 'https://cloud/1.jpg');

    // Simulates the pull step of the very next sync, which returns this
    // same item (now with the just-uploaded URL) from the cloud.
    await items.upsertFromCloud(cloudItemFor(itemId), images: [
      {'imageUrl': 'https://cloud/1.jpg', 'sortOrder': 0, 'isPrimary': true},
    ]);

    final gallery = await items.getImages(itemId);
    expect(gallery, hasLength(1));
    expect(gallery.single.imagePath, '/local/dosa.jpg',
        reason: 'the device that uploaded this file must keep its own local reference to it');
  });

  test('a brand-new image the cloud has but this device never uploaded has no local path yet', () async {
    await items.upsertFromCloud(cloudItemFor(itemId), images: [
      {'imageUrl': 'https://cloud/1.jpg', 'sortOrder': 0, 'isPrimary': true},
      {'imageUrl': 'https://cloud/only-on-other-device.jpg', 'sortOrder': 1, 'isPrimary': false},
    ]);

    final gallery = await items.getImages(itemId);
    final fromOtherDevice = gallery.firstWhere((img) => img.imageUrl == 'https://cloud/only-on-other-device.jpg');
    expect(fromOtherDevice.imagePath, isNull,
        reason: 'falls back to loading it over the network — see _resolveItemImage');
  });

  test('re-pulling the same cloud gallery repeatedly never duplicates images (idempotent)', () async {
    final payload = cloudItemFor(itemId);
    final images = [
      {'imageUrl': 'https://cloud/1.jpg', 'sortOrder': 0, 'isPrimary': true},
      {'imageUrl': 'https://cloud/2.jpg', 'sortOrder': 1, 'isPrimary': false},
    ];
    await items.upsertFromCloud(payload, images: images);
    await items.upsertFromCloud(payload, images: images);
    await items.upsertFromCloud(payload, images: images);

    expect(await items.getImages(itemId), hasLength(2));
  });

  test('adding a second (non-primary) image bumps the item so push actually picks it up', () async {
    final db = await DatabaseHelper.instance.database;
    await db.update('items', {'updated_at': '2020-01-01T00:00:00.000'}, where: 'id = ?', whereArgs: [itemId]);

    await items.addImage(itemId, imagePath: '/local/a.jpg');
    final afterFirst = (await items.getItemById(itemId))!.updatedAt;
    expect(afterFirst.isAfter(DateTime(2021)), isTrue,
        reason: 'without this, an item change consisting only of an added image is invisible to getItemsUpdatedSince');

    await db.update('items', {'updated_at': '2020-01-01T00:00:00.000'}, where: 'id = ?', whereArgs: [itemId]);
    await items.addImage(itemId, imagePath: '/local/b.jpg');
    final afterSecond = (await items.getItemById(itemId))!.updatedAt;
    expect(afterSecond.isAfter(DateTime(2021)), isTrue,
        reason: 'the second image (non-primary) must bump it too, not just the first/primary one');
  });

  test('removing, setting primary, and reordering images all bump the item too', () async {
    final db = await DatabaseHelper.instance.database;
    final id1 = await items.addImage(itemId, imagePath: '/local/a.jpg');
    final id2 = await items.addImage(itemId, imagePath: '/local/b.jpg');

    Future<void> reset() async =>
        db.update('items', {'updated_at': '2020-01-01T00:00:00.000'}, where: 'id = ?', whereArgs: [itemId]);

    await reset();
    await items.setPrimaryImage(itemId, id2);
    expect((await items.getItemById(itemId))!.updatedAt.isAfter(DateTime(2021)), isTrue);

    await reset();
    await items.reorderImages(itemId, [id2, id1]);
    expect((await items.getItemById(itemId))!.updatedAt.isAfter(DateTime(2021)), isTrue);

    await reset();
    await items.removeImage(itemId, id1);
    expect((await items.getItemById(itemId))!.updatedAt.isAfter(DateTime(2021)), isTrue);
  });
}
