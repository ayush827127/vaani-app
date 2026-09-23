import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/product.dart';
import '../repositories/product_repository.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../../l10n/l10n_extensions.dart';

class ProductDetailsScreen extends StatefulWidget {
  final int productId;
  const ProductDetailsScreen({super.key, required this.productId});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Product? _product;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final product = await getIt<ProductRepository>().getProductById(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = product;
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

  Future<void> _addStock() async {
    final c = context.colors;
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(bsCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle_outline_rounded, color: c.success),
                const SizedBox(width: 10),
                Text(l10n.addStock, style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.currentStock('${_product?.stockQuantity ?? 0}'),
              style: TextStyle(color: c.textHint, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: c.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                labelText: l10n.unitsToAdd,
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final qty = int.tryParse(ctrl.text) ?? 0;
                  if (qty > 0) {
                    await getIt<ProductRepository>()
                        .adjustStock(widget.productId, qty, 'restock', notes: 'Manual restock');
                    if (bsCtx.mounted) Navigator.pop(bsCtx);
                    _load();
                  }
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.addStock, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeStock() async {
    final c = context.colors;
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(bsCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.remove_circle_outline_rounded, color: c.warning),
                const SizedBox(width: 10),
                Text(l10n.adjustStock, style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.currentStock('${_product?.stockQuantity ?? 0}'),
              style: TextStyle(color: c.textHint, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: c.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                labelText: l10n.unitsToRemoveAdjust,
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final qty = int.tryParse(ctrl.text) ?? 0;
                  if (qty > 0) {
                    await getIt<ProductRepository>()
                        .adjustStock(widget.productId, -qty, 'adjustment', notes: 'Manual adjustment');
                    if (bsCtx.mounted) Navigator.pop(bsCtx);
                    _load();
                  }
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.confirmAdjustment, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.warning,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deleteProduct, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          l10n.removeProductConfirm(_product?.name ?? ''),
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
      await getIt<ProductRepository>().deleteProduct(widget.productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.productDeleted), backgroundColor: c.success),
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

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: Text(l10n.product, style: TextStyle(color: c.textPrimary)),
        ),
        body: Center(child: Text(l10n.productNotFound, style: TextStyle(color: c.textHint))),
      );
    }

    final p = _product!;
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
                onPressed: _deleteProduct,
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
                      ProductAvatar(
                        product: p,
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
                      if (p.category != null) ...[
                        const SizedBox(height: 4),
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

                // Stock section
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

                // Product details
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
                      Text(l10n.productDetails,
                          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (p.sku != null) _DetailRow(l10n.skuCode, p.sku!),
                      _DetailRow(
                        l10n.barcode,
                        p.barcode ?? l10n.noBarcodeAssigned,
                      ),
                      _DetailRow(l10n.category, p.category != null ? localizedCategory(l10n, p.category!) : l10n.uncategorized),
                      _DetailRow(l10n.reorderLevel, '${p.reorderLevel} ${l10n.unitsLabel}'),
                      _DetailRow(l10n.addedOn, AppFormatters.formatDate(p.createdAt)),
                      _DetailRow(l10n.lastUpdated, AppFormatters.formatDate(p.updatedAt)),
                      if (p.aliases.isNotEmpty)
                        _DetailRow(l10n.voiceAliases, p.aliases.join(', ')),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
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

                OutlinedButton.icon(
                  onPressed: _deleteProduct,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(l10n.deleteProduct),
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
