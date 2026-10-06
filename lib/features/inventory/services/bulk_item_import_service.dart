import 'package:excel/excel.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/item.dart';
import '../repositories/item_repository.dart';

/// One parsed, not-yet-applied row from an uploaded bulk-import sheet.
/// [matchedExisting] is resolved by name against the current catalog so the
/// review screen can show "already exists — will be skipped" instead of
/// silently creating a duplicate or silently overwriting real data.
class BulkImportRow {
  final int rowNumber; // 1-indexed as a spreadsheet row, for error messages
  final String name;
  final String? sku;
  final String? barcode;
  final String? category;
  final double costPrice;
  final double sellingPrice;
  final double? mrp;
  final double gstRate;
  final int stockQuantity;
  final int reorderLevel;
  Item? matchedExisting;
  bool selected;

  BulkImportRow({
    required this.rowNumber,
    required this.name,
    this.sku,
    this.barcode,
    this.category,
    required this.costPrice,
    required this.sellingPrice,
    this.mrp,
    required this.gstRate,
    required this.stockQuantity,
    required this.reorderLevel,
    this.matchedExisting,
    this.selected = true,
  });

  bool get isNew => matchedExisting == null;
}

class BulkImportParseResult {
  final List<BulkImportRow> rows;
  // Row-level problems that kept a row from being parsed at all (e.g. a
  // missing name) — shown to the user, never silently dropped.
  final List<String> rowErrors;

  const BulkImportParseResult({required this.rows, required this.rowErrors});
}

class BulkItemImportService {
  static const List<String> columns = [
    'Name',
    'SKU',
    'Barcode',
    'Category',
    'Cost Price',
    'Selling Price',
    'MRP',
    'GST Rate',
    'Stock Quantity',
    'Reorder Level',
  ];

  /// A ready-to-fill .xlsx with the header row and one example row, so a
  /// shopkeeper opening it in Excel/Sheets/WPS sees exactly what each column
  /// means without guessing.
  List<int> generateTemplateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['Items'];
    excel.setDefaultSheet('Items');
    // The auto-created default sheet (named after Excel's own convention,
    // not 'Items') would otherwise ship alongside it as a confusing second,
    // empty tab.
    for (final name in List<String>.from(excel.sheets.keys)) {
      if (name != 'Items') excel.delete(name);
    }

    for (var i = 0; i < columns.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
          TextCellValue(columns[i]);
    }
    final example = [
      'Dosa Batter 1kg',
      'DB-1KG',
      '',
      'Grocery',
      30,
      50,
      60,
      5,
      20,
      5,
    ];
    for (var i = 0; i < example.length; i++) {
      final value = example[i];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value =
          value is num ? DoubleCellValue(value.toDouble()) : TextCellValue(value as String);
    }

    return excel.encode()!;
  }

  String? _cellText(CellValue? v) {
    if (v == null) return null;
    final s = switch (v) {
      TextCellValue() => v.value.toString(),
      IntCellValue() => v.value.toString(),
      DoubleCellValue() => v.value.toString(),
      _ => v.toString(),
    };
    final trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _cellNum(CellValue? v) {
    if (v == null) return null;
    return switch (v) {
      IntCellValue() => v.value.toDouble(),
      DoubleCellValue() => v.value,
      TextCellValue() => double.tryParse(v.value.toString().trim()),
      _ => null,
    };
  }

  /// Parses an uploaded .xlsx, matches each row against the current catalog
  /// by name, and returns both the usable rows and any row-level errors —
  /// a bad row never silently disappears, it shows up as a reported error
  /// instead so the user knows to fix and re-upload.
  Future<BulkImportParseResult> parseWorkbook(List<int> bytes, int shopId) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return const BulkImportParseResult(rows: [], rowErrors: ['The file has no sheets.']);
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    final itemRepo = getIt<ItemRepository>();

    final rows = <BulkImportRow>[];
    final errors = <String>[];

    // Row 0 is the header; data starts at row 1 (spreadsheet row 2).
    for (var r = 1; r < sheet.maxRows; r++) {
      final cells = sheet.row(r);
      if (cells.every((c) => c?.value == null)) continue; // a genuinely blank row
      final rowNumber = r + 1;

      final name = _cellText(cells.elementAtOrNull(0)?.value);
      if (name == null) {
        errors.add('Row $rowNumber: Name is required — skipped.');
        continue;
      }
      final sellingPrice = _cellNum(cells.elementAtOrNull(5)?.value);
      if (sellingPrice == null || sellingPrice <= 0) {
        errors.add('Row $rowNumber ($name): Selling Price must be a positive number — skipped.');
        continue;
      }

      final existing = await itemRepo.getItemByName(shopId, name);
      rows.add(BulkImportRow(
        rowNumber: rowNumber,
        name: name,
        sku: _cellText(cells.elementAtOrNull(1)?.value),
        barcode: _cellText(cells.elementAtOrNull(2)?.value),
        category: _cellText(cells.elementAtOrNull(3)?.value),
        costPrice: _cellNum(cells.elementAtOrNull(4)?.value) ?? 0,
        sellingPrice: sellingPrice,
        mrp: _cellNum(cells.elementAtOrNull(6)?.value),
        gstRate: _cellNum(cells.elementAtOrNull(7)?.value) ?? 5.0,
        stockQuantity: (_cellNum(cells.elementAtOrNull(8)?.value) ?? 0).round(),
        reorderLevel: (_cellNum(cells.elementAtOrNull(9)?.value) ?? 10).round(),
        matchedExisting: existing,
      ));
    }

    return BulkImportParseResult(rows: rows, rowErrors: errors);
  }
}
