import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/item.dart';
import '../repositories/item_repository.dart';
import '../services/bulk_item_import_service.dart';

/// Shown after a sheet (or, later, an OCR-scanned purchase bill) has been
/// parsed, before anything is actually written to the catalog. A row
/// matching an existing item by name is shown but not actionable — bulk
/// import only ever *creates* new items, it never silently overwrites real
/// inventory data a spreadsheet mistake could otherwise clobber.
class BulkImportReviewScreen extends StatefulWidget {
  final List<BulkImportRow> rows;
  final List<String> rowErrors;
  const BulkImportReviewScreen({super.key, required this.rows, required this.rowErrors});

  @override
  State<BulkImportReviewScreen> createState() => _BulkImportReviewScreenState();
}

class _BulkImportReviewScreenState extends State<BulkImportReviewScreen> {
  bool _importing = false;

  int get _selectedNewCount => widget.rows.where((r) => r.isNew && r.selected).length;
  int get _existingCount => widget.rows.where((r) => !r.isNew).length;

  Future<void> _import() async {
    setState(() => _importing = true);
    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final itemRepo = getIt<ItemRepository>();

    var created = 0;
    for (final row in widget.rows) {
      if (!row.isNew || !row.selected) continue;
      final now = DateTime.now();
      await itemRepo.insertItem(Item(
        shopId: shopId,
        name: row.name,
        sku: row.sku,
        barcode: row.barcode,
        category: row.category,
        costPrice: row.costPrice,
        sellingPrice: row.sellingPrice,
        mrp: row.mrp,
        gstRate: row.gstRate,
        stockQuantity: row.stockQuantity,
        reorderLevel: row.reorderLevel,
        createdAt: now,
        updatedAt: now,
      ));
      created++;
    }

    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Import')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_selectedNewCount new item${_selectedNewCount == 1 ? '' : 's'} will be created'
                  '${_existingCount > 0 ? ', $_existingCount already exist and will be skipped' : ''}.',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w500),
                ),
                if (widget.rowErrors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...widget.rowErrors.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(e, style: TextStyle(color: c.danger, fontSize: 12)),
                      )),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.rows.length,
              itemBuilder: (_, i) {
                final row = widget.rows[i];
                return Card(
                  color: c.surface,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    enabled: row.isNew,
                    leading: row.isNew
                        ? Checkbox(
                            value: row.selected,
                            onChanged: (v) => setState(() => row.selected = v ?? true),
                          )
                        : Icon(Icons.info_outline_rounded, color: c.textHint),
                    title: Text(row.name, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      row.isNew
                          ? 'New · ${AppFormatters.formatCurrency(row.sellingPrice)} · Stock ${row.stockQuantity}'
                          : 'Already exists — skipped',
                      style: TextStyle(color: row.isNew ? c.textSecondary : c.textHint, fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_importing || _selectedNewCount == 0) ? null : _import,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight),
                child: _importing
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text('Import $_selectedNewCount Item${_selectedNewCount == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
