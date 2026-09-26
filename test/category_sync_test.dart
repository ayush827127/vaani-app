import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/inventory/repositories/category_repository.dart';

/// Reproduces, and verifies the fix for, a real reported bug: creating a
/// category locally and then tapping Cloud Sync made it disappear.
///
/// Root cause — DataSyncRepository.syncNow() always pulls from the cloud
/// before it pushes local changes up (see its own comment: "pull always
/// runs before push in the same cycle"). The pull handler called what was
/// then CategoryRepository.replaceCategories(shopId, cloudCategories),
/// which deleted every local category not in that cloud list and reinserted
/// only the cloud's set — so a category created moments before Cloud Sync
/// was tapped, and therefore not yet in the cloud's list, was deleted
/// before the push a few lines later ever got a chance to upload it.
///
/// The fix (mergeCategories) makes the cloud list purely additive: it adds
/// any category the cloud has that isn't already stored locally, and never
/// deletes a local category just because a cloud snapshot didn't mention it.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CategoryRepository categories;
  const shopId = 1;

  setUp(() async {
    final db = await DatabaseHelper.openInMemoryForTesting();
    categories = CategoryRepository();
    await db.insert('shops', {
      'id': shopId,
      'name': 'Test Shop',
      'owner_name': 'Test Owner',
      'phone': '9999999999',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  });

  test('a category created locally survives a cloud sync that does not yet know about it', () async {
    await categories.addCategory(shopId, 'Party Supplies');
    expect(await categories.getCategories(shopId), contains('Party Supplies'));

    // Simulates the pull step of a Cloud Sync tapped moments later — the
    // cloud snapshot reflects the state from *before* this category was
    // created, since it hasn't been pushed up yet.
    await categories.mergeCategories(shopId, ['Soft Drinks', 'Snacks']);

    final result = await categories.getCategories(shopId);
    expect(result, contains('Party Supplies'), reason: 'the locally created category must not be deleted');
    expect(result, containsAll(['Soft Drinks', 'Snacks']), reason: 'cloud categories are still merged in');
  });

  test('cloud categories not present locally are added', () async {
    await categories.addCategory(shopId, 'Local Only');
    await categories.mergeCategories(shopId, ['Cloud Only']);

    final result = await categories.getCategories(shopId);
    expect(result, containsAll(['Local Only', 'Cloud Only']));
  });

  test('overlapping local and cloud categories both remain, with no duplicates', () async {
    await categories.addCategory(shopId, 'Soft Drinks');
    await categories.mergeCategories(shopId, ['Soft Drinks', 'Snacks']);

    final result = await categories.getCategories(shopId);
    expect(result.where((c) => c == 'Soft Drinks'), hasLength(1));
    expect(result, containsAll(['Soft Drinks', 'Snacks']));
  });

  test('syncing the same cloud snapshot multiple times never creates duplicates (idempotent)', () async {
    await categories.mergeCategories(shopId, ['Soft Drinks', 'Snacks']);
    await categories.mergeCategories(shopId, ['Soft Drinks', 'Snacks']);
    await categories.mergeCategories(shopId, ['Soft Drinks', 'Snacks']);

    final result = await categories.getCategories(shopId);
    expect(result.where((c) => c == 'Soft Drinks'), hasLength(1));
    expect(result.where((c) => c == 'Snacks'), hasLength(1));
  });

  test('an empty cloud snapshot is a no-op, not "the cloud has no categories, delete everything"', () async {
    await categories.addCategory(shopId, 'Keep Me');
    await categories.mergeCategories(shopId, []);

    expect(await categories.getCategories(shopId), contains('Keep Me'));
  });

  test('a category created entirely offline (never synced) keeps existing after several merges', () async {
    await categories.addCategory(shopId, 'Offline Category');

    // Several sync rounds pass with the cloud still unaware of it (device
    // was offline when it was created and reconnects later).
    await categories.mergeCategories(shopId, ['Existing Cloud Category']);
    await categories.mergeCategories(shopId, ['Existing Cloud Category']);

    expect(await categories.getCategories(shopId), contains('Offline Category'));
  });
}
