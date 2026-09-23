import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/item.dart';
import '../repositories/item_repository.dart';
import '../../../shared/widgets/item_avatar.dart';
import '../../../l10n/l10n_extensions.dart';

class ItemDetailsScreen extends StatefulWidget {
  final int itemId;
  const ItemDetailsScreen({super.key, required this.itemId});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  Item? _item;
  List<Map<String, Object?>> _stockHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = getIt<ItemRepository>();
    final item = await repo.getItemById(widget.itemId);
    // Stock History is meaningless for a service, so it's not even fetched
    // for one — nothing to show, no point querying.
    final history = item != null && item.inventoryEnabled
        ? await repo.getStockHistory(widget.itemId)
        : <Map<String, Object?>>[];
    if (!mounted) return;
    setState(() {
      _item = item;
      _stockHistory = history;
      _isLoading = false;
    });
  }

  Color _categoryColor(String? cat) {
    const palette = [
      Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF16A34A),
      Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF0891B2),
      Color(0xFF65A30D), Color(0xFF9333EA), Color(0xFFD97706),
    ];
    if (cat == null) return const Color(0xFF7C3AED);
    return palette[cat.hashCode.abs() % palette.length];
  }

  Future<void> _addStock() => _showStockSheet(isAdd: true);
  Future<void> _removeStock() => _showStockSheet(isAdd: false);

  /// Add Stock and Remove Stock share the same shape (Quantity, Date,
  /// Reason, optional Note) — just the sign, color, reason list and title
  /// differ. Building both from one sheet keeps them from drifting apart.
  Future<void> _showStockSheet({required bool isAdd}) async {
    final c = context.colors;
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final color = isAdd ? c.success : c.warning;
    final reasons = isAdd ? AppConstants.stockInReasons : AppConstants.stockOutReasons;
    DateTime date = DateTime.now();
    String reason = reasons.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => StatefulBuilder(
        builder: (bsCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(bsCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(isAdd ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                        color: color),
                    const SizedBox(width: 10),
                    Text(isAdd ? l10n.addStock : l10n.removeStockLabel,
                        style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.currentStock('${_item?.stockQuantity ?? 0}'),
                  style: TextStyle(color: c.textHint, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: TextStyle(color: c.textPrimary, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: isAdd ? l10n.unitsToAdd : l10n.unitsToRemoveAdjust,
                    hintText: '0',
                    suffixText: l10n.unitsLabel,
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.inputBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.primaryLight),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: bsCtx,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setSheetState(() => date = picked);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: l10n.date,
                            filled: true,
                            fillColor: c.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.inputBorder)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 15, color: c.textHint),
                              const SizedBox(width: 8),
                              Text(AppFormatters.formatDate(date),
                                  style: TextStyle(color: c.textPrimary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: reason,
                        isExpanded: true,
                        dropdownColor: c.surface,
                        style: TextStyle(color: c.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: l10n.reasonLabel,
                          filled: true,
                          fillColor: c.surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.inputBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        ),
                        items: reasons
                            .map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setSheetState(() => reason = v ?? reasons.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteCtrl,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(color: c.textPrimary),
                  decoration: InputDecoration(
                    labelText: l10n.noteOptionalLabel,
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.inputBorder)),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final qty = int.tryParse(ctrl.text) ?? 0;
                      if (qty > 0) {
                        final type = isAdd
                            ? AppConstants.txnRestock
                            : (reason == 'Damaged' ? AppConstants.txnDamage : AppConstants.txnAdjustment);
                        await getIt<ItemRepository>().adjustStock(
                          widget.itemId,
                          isAdd ? qty : -qty,
                          type,
                          reason: reason,
                          notes: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                          date: date,
                        );
                        if (bsCtx.mounted) Navigator.pop(bsCtx);
                        _load();
                      }
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(isAdd ? l10n.addStock : l10n.confirmAdjustment,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteItem() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deleteItem, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          l10n.removeItemConfirm(_item?.name ?? ''),
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await getIt<ItemRepository>().deleteItem(widget.itemId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.itemDeleted), backgroundColor: c.success),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    if (_item == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: Text(l10n.item, style: TextStyle(color: c.textPrimary)),
        ),
        body: Center(child: Text(l10n.itemNotFound, style: TextStyle(color: c.textHint))),
      );
    }

    final p = _item!;
    final catColor = _categoryColor(p.category);
    final margin = p.sellingPrice > 0
        ? ((p.sellingPrice - p.costPrice) / p.sellingPrice) * 100
        : 0.0;
    final stockMax = p.reorderLevel * 3;
    final stockRatio = stockMax > 0 ? (p.stockQuantity / stockMax).clamp(0.0, 1.0) : 0.0;
    final stockColor = p.stockQuantity == 0
        ? c.danger
        : p.stockQuantity <= p.reorderLevel
            ? c.warning
            : c.success;
    final stockLabel = p.stockQuantity == 0
        ? l10n.outOfStock
        : p.stockQuantity <= p.reorderLevel
            ? l10n.lowStock
            : l10n.inStock;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: catColor.withValues(alpha: 0.9),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                tooltip: l10n.edit,
                onPressed: () => context.push('/inventory/add', extra: p.id).then((_) => _load()),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                tooltip: l10n.delete,
                onPressed: _deleteItem,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [catColor.withValues(alpha: 0.9), Theme.of(context).scaffoldBackgroundColor],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      ItemAvatar(
                        item: p,
                        size: 72,
                        catColor: Colors.white,
                        borderRadiusValue: 20,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Poppins',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (p.category != null || p.itemType == ItemType.service) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Only shown for a service — a product's type is
                            // already implied everywhere else on this page,
                            // so this badge would just be clutter for the
                            // common case.
                            if (p.itemType == ItemType.service) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  l10n.itemTypeService,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (p.category != null) const SizedBox(width: 6),
                            ],
                            if (p.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  localizedCategory(l10n, p.category!),
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Pricing row
                Row(
                  children: [
                    Expanded(child: _InfoCard(
                      icon: Icons.sell_rounded,
                      label: l10n.sellingPrice,
                      value: '₹${p.sellingPrice.toStringAsFixed(2)}',
                      color: AppColors.primaryLight,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _InfoCard(
                      icon: Icons.price_change_rounded,
                      label: l10n.costPrice,
                      value: '₹${p.costPrice.toStringAsFixed(2)}',
                      color: c.info,
                    )),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _InfoCard(
                      icon: Icons.percent_rounded,
                      label: l10n.profitMargin,
                      value: '${margin.toStringAsFixed(1)}%',
                      color: margin >= 20 ? c.success : c.warning,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _InfoCard(
                      icon: Icons.receipt_long_rounded,
                      label: l10n.gstRate,
                      value: '${p.gstRate.toInt()}%',
                      color: c.info,
                    )),
                  ],
                ),

                const SizedBox(height: 16),

                // Stock section — inventory summary only exists for
                // inventory-tracked items; a service shows nothing here
                // rather than a meaningless "0 units".
                if (p.inventoryEnabled) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.stockLevel,
                                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: stockColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: stockColor.withValues(alpha: 0.4)),
                              ),
                              child: Text(stockLabel,
                                  style: TextStyle(fontSize: 12, color: stockColor, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              '${p.stockQuantity}',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: stockColor,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(l10n.unitsLabel, style: TextStyle(color: c.textHint, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: stockRatio,
                            minHeight: 8,
                            backgroundColor: c.surfaceBorder,
                            valueColor: AlwaysStoppedAnimation<Color>(stockColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.reorderAt('${p.reorderLevel}'),
                                style: TextStyle(color: c.textHint, fontSize: 12)),
                            Text(l10n.stockValue(AppFormatters.formatCurrency(p.sellingPrice * p.stockQuantity)),
                                style: TextStyle(color: c.textHint, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Item details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.itemDetails,
                          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (p.sku != null) _DetailRow(l10n.skuCode, p.sku!),
                      _DetailRow(
                        l10n.barcode,
                        p.barcode ?? l10n.noBarcodeAssigned,
                      ),
                      _DetailRow(l10n.category, p.category != null ? localizedCategory(l10n, p.category!) : l10n.uncategorized),
                      _DetailRow(l10n.itemTypeLabel, p.itemType == ItemType.service ? l10n.itemTypeService : l10n.itemTypeProduct),
                      if (p.inventoryEnabled)
                        _DetailRow(l10n.reorderLevel, '${p.reorderLevel} ${l10n.unitsLabel}'),
                      _DetailRow(l10n.addedOn, AppFormatters.formatDate(p.createdAt)),
                      _DetailRow(l10n.lastUpdated, AppFormatters.formatDate(p.updatedAt)),
                      if (p.aliases.isNotEmpty)
                        _DetailRow(l10n.voiceAliases, p.aliases.join(', ')),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action buttons — Add/Remove Stock only make sense for an
                // inventory-tracked item; a service just gets Edit.
                Row(
                  children: [
                    if (p.inventoryEnabled) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.add_circle_rounded,
                          label: l10n.addStock,
                          color: c.success,
                          onTap: _addStock,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.remove_circle_rounded,
                          label: l10n.adjust,
                          color: c.warning,
                          onTap: _removeStock,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.edit_rounded,
                        label: l10n.edit,
                        color: AppColors.primaryLight,
                        onTap: () => context.push('/inventory/add', extra: p.id).then((_) => _load()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // History — Stock History for an inventory-tracked item;
                // services have no stock movements, so nothing is shown
                // here for them at all (rather than an empty stock-history
                // card with nothing meaningful to say).
                if (p.inventoryEnabled) ...[
                  _StockHistorySection(history: _stockHistory),
                  const SizedBox(height: 16),
                ],

                OutlinedButton.icon(
                  onPressed: _deleteItem,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(l10n.deleteItem),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger.withValues(alpha: 0.5)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock History ─────────────────────────────────────────────────────────
//
// Every stock change — Add/Remove Stock entries, sales, and void/return
// reversals alike — already lands in inventory_transactions (see
// ItemRepository.adjustStock and InvoiceRepository's create/void/return);
// this just displays that one existing audit trail, newest first.

class _StockHistorySection extends StatelessWidget {
  final List<Map<String, Object?>> history;
  const _StockHistorySection({required this.history});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.stockHistory,
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.noStockHistoryYet, style: TextStyle(color: c.textHint, fontSize: 13)),
            )
          else
            for (var i = 0; i < history.length; i++)
              _StockHistoryRow(row: history[i], showDivider: i > 0),
        ],
      ),
    );
  }
}

class _StockHistoryRow extends StatelessWidget {
  final Map<String, Object?> row;
  final bool showDivider;
  const _StockHistoryRow({required this.row, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final type = row['type'] as String? ?? '';
    final reason = row['reason'] as String?;
    final notes = row['notes'] as String?;
    final invoiceId = row['invoice_id'];
    final qtyChange = row['quantity_change'] as int? ?? 0;
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final isIncrease = qtyChange > 0;
    final color = isIncrease ? c.success : c.danger;

    String typeLabel;
    IconData icon;
    switch (type) {
      case AppConstants.txnSale:
        typeLabel = l10n.stockMovementSale;
        icon = Icons.point_of_sale_rounded;
        break;
      case AppConstants.txnRestock:
        typeLabel = l10n.stockMovementStockIn;
        icon = Icons.add_box_rounded;
        break;
      case AppConstants.txnDamage:
        typeLabel = l10n.stockMovementDamaged;
        icon = Icons.report_problem_rounded;
        break;
      case AppConstants.txnReturn:
        typeLabel = isIncrease ? l10n.stockMovementReturnIn : l10n.stockMovementReturnOut;
        icon = Icons.assignment_return_rounded;
        break;
      case AppConstants.txnVoid:
        typeLabel = l10n.stockMovementVoided;
        icon = Icons.undo_rounded;
        break;
      case AppConstants.txnAdjustment:
      default:
        typeLabel = l10n.stockMovementAdjustment;
        icon = Icons.tune_rounded;
    }

    // Reference: which bill this movement came from, if any — reason for a
    // manual Add/Remove Stock entry otherwise.
    final reference = invoiceId != null ? l10n.billNumberRef('$invoiceId') : reason;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showDivider
          ? BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: 1)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppFormatters.formatDate(createdAt),
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                const SizedBox(height: 2),
                Text(typeLabel,
                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (reference != null && reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(reference, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                ],
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(notes, style: TextStyle(color: c.textHint, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Text(
            '${isIncrease ? '+' : ''}$qtyChange',
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: c.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textHint, fontSize: 13)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
