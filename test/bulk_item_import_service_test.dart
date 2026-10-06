import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaani/core/db/database_helper.dart';
import 'package:vaani/features/inventory/repositories/item_repository.dart';
import 'package:vaani/features/inventory/services/bulk_item_import_service.dart';
import 'package:vaani/shared/models/item.dart';

/// Builds a minimal .xlsx with the service's own column order, so these
/// tests exercise exactly what an uploaded sheet goes through — never a
/// hand-built BulkImportRow list that could drift from the real parser.
List<int> _sheetBytes(List<List<Object?>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel['Items'];
  excel.setDefaultSheet('Items');
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final value = rows[r][c];
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      if (value == null) {
        cell.value = null;
      } else if (value is num) {
        cell.value = DoubleCellValue(value.toDouble());
      } else {
        cell.value = TextCellValue(value.toString());
      }
    }
  }
  return excel.encode()!;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const shopId = 1;
  final service = BulkItemImportService();

  setUp(() async {
    await DatabaseHelper.openInMemoryForTesting();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('shops', {
      'id': shopId, 'name': 'Test Shop', 'owner_name': 'Owner', 'phone': '9999999999',
      'created_at': now, 'updated_at': now,
    });
    await GetIt.instance.reset();
    GetIt.instance.registerLazySingleton<ItemRepository>(() => ItemRepository());
  });

  test('generateTemplateBytes() produces a sheet whose header matches the documented columns', () {
    final bytes = service.generateTemplateBytes();
    final decoded = Excel.decodeBytes(bytes);
    final sheet = decoded.tables[decoded.tables.keys.first]!;
    final header = sheet.row(0).map((c) => c?.value?.toString()).toList();
    for (var i = 0; i < BulkItemImportService.columns.length; i++) {
      expect(header[i], contains(BulkItemImportService.columns[i]));
    }
  });

  group('parseWorkbook', () {
    final header = BulkItemImportService.columns;

    test('a well-formed new row parses cleanly and is marked as new (no match)', () async {
      final bytes = _sheetBytes([
        header,
        ['Dosa Batter', 'DB-1', '', 'Grocery', 30, 50, 60, 5, 20, 5],
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      expect(result.rowErrors, isEmpty);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.name, 'Dosa Batter');
      expect(row.sku, 'DB-1');
      expect(row.costPrice, 30);
      expect(row.sellingPrice, 50);
      expect(row.mrp, 60);
      expect(row.gstRate, 5);
      expect(row.stockQuantity, 20);
      expect(row.reorderLevel, 5);
      expect(row.isNew, isTrue);
    });

    test('a row whose name matches an existing item is flagged, not treated as new', () async {
      final now = DateTime.now();
      await GetIt.instance<ItemRepository>().insertItem(Item(
        shopId: shopId, name: 'Dosa Batter', sellingPrice: 45, createdAt: now, updatedAt: now,
      ));

      final bytes = _sheetBytes([
        header,
        ['dosa batter', '', '', '', 30, 50, null, 5, 20, 5], // case-insensitive match
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      expect(result.rows.single.isNew, isFalse);
      expect(result.rows.single.matchedExisting?.name, 'Dosa Batter');
    });

    test('a row missing Name is reported as an error and excluded, never silently dropped', () async {
      final bytes = _sheetBytes([
        header,
        [null, 'SKU-1', '', '', 10, 20, null, 5, 1, 1],
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      expect(result.rows, isEmpty);
      expect(result.rowErrors, hasLength(1));
      expect(result.rowErrors.single, contains('Row 2'));
      expect(result.rowErrors.single, contains('Name'));
    });

    test('a row with no selling price (or zero/negative) is reported as an error', () async {
      final bytes = _sheetBytes([
        header,
        ['Free Sample', '', '', '', 10, 0, null, 5, 1, 1],
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      expect(result.rows, isEmpty);
      expect(result.rowErrors.single, contains('Selling Price'));
    });

    test('a genuinely blank row is silently skipped — not an error, not a row', () async {
      final bytes = _sheetBytes([
        header,
        ['Dosa Batter', '', '', '', 30, 50, null, 5, 20, 5],
        [null, null, null, null, null, null, null, null, null, null],
        ['Idli Batter', '', '', '', 20, 35, null, 5, 15, 5],
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      expect(result.rows, hasLength(2));
      expect(result.rowErrors, isEmpty);
    });

    test('omitted cost price, MRP, GST rate, stock and reorder level fall back to sensible defaults', () async {
      final bytes = _sheetBytes([
        header,
        ['Loose Rice', null, null, null, null, 40, null, null, null, null],
      ]);

      final result = await service.parseWorkbook(bytes, shopId);

      final row = result.rows.single;
      expect(row.costPrice, 0);
      expect(row.mrp, isNull);
      expect(row.gstRate, 5.0);
      expect(row.stockQuantity, 0);
      expect(row.reorderLevel, 10);
    });
  });
}
