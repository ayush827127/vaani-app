import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/product.dart';
import '../repositories/product_repository.dart';
import '../repositories/category_repository.dart';
import '../widgets/category_picker_sheet.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../../shared/widgets/barcode_scanner_screen.dart';
import '../../../core/utils/permission_service.dart';
import '../../../l10n/l10n_extensions.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Product> _all = [];
  List<Product> _filtered = [];
  List<String> _categories = [];
  bool _isLoading = true;
  int _shopId = 1;
  String _searchQuery = '';
  String? _selectedCategory;
  String _stockFilter = 'all'; // all | low | out
  String _sortOption = 'name_az';

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final results = await Future.wait([
      getIt<ProductRepository>().getAllProducts(_shopId),
      getIt<CategoryRepository>().getCategories(_shopId),
    ]);
    if (!mounted) return;
    setState(() {
      _all = results[0] as List<Product>;
      _categories = results[1] as List<String>;
      _isLoading = false;
    });
    _applyFilters();
  }

  Future<void> _showCreateCategoryDialog() async {
    await showCategoryPicker(
      context: context,
      shopId: _shopId,
      selected: null,
      onSelected: (cat) {
        setState(() {
          _selectedCategory = cat;
          _applyFilters();
        });
      },
      onCreated: (cat) {
        if (!_categories.contains(cat)) {
          setState(() => _categories = ([..._categories, cat]..sort()));
        }
      },
    );
  }

  void _applyFilters() {
    setState(() {
      var list = _all.where((p) {
        final q = _searchQuery.toLowerCase();
        final matchesSearch = _searchQuery.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            (p.sku?.toLowerCase().contains(q) ?? false) ||
            (p.barcode?.toLowerCase().contains(q) ?? false) ||
            p.aliases.any((a) => a.toLowerCase().contains(q));
        final matchesCategory =
            _selectedCategory == null || p.category == _selectedCategory;
        final matchesStock = _stockFilter == 'all' ||
            (_stockFilter == 'low' &&
                p.stockQuantity > 0 &&
                p.stockQuantity <= p.reorderLevel) ||
            (_stockFilter == 'out' && p.stockQuantity == 0);
        return matchesSearch && matchesCategory && matchesStock;
      }).toList();

      switch (_sortOption) {
        case 'name_za':
          list.sort((a, b) => b.name.compareTo(a.name));
          break;
        case 'stock_lh':
          list.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
          break;
        case 'stock_hl':
          list.sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
          break;
        case 'recent':
          list.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
          break;
        default: // name_az
          list.sort((a, b) => a.name.compareTo(b.name));
      }

      _filtered = list;
    });
  }

  int _categoryCount(String category) =>
      _all.where((p) => p.category == category).length;

  Future<void> _scanBarcode() async {
    final granted = await PermissionService.requestCamera(context);
    if (!granted || !mounted) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    final product = await getIt<ProductRepository>().getProductByBarcode(_shopId, code.trim());
    if (!mounted) return;
    if (product != null && product.id != null) {
      context.push('/inventory/product/${product.id}').then((_) => _loadProducts());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.productNotFound),
        backgroundColor: context.colors.danger,
      ));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            context.push('/inventory/add').then((_) => _loadProducts()),
        backgroundColor: AppColors.primaryLight,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildCategoryChips(),
            _buildSortBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryLight))
                  : _filtered.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadProducts,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _ProductCard(
                              product: _filtered[i],
                              onTap: () => context
                                  .push(
                                      '/inventory/product/${_filtered[i].id}')
                                  .then((_) => _loadProducts()),
                              onDelete: () => _confirmDelete(_filtered[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.go('/home'),
          ),
          Expanded(
            child: Text(
              context.l10n.products,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list_rounded,
              color: _stockFilter != 'all'
                  ? AppColors.primaryLight
                  : c.textSecondary,
              size: 24,
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.inputBorder),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(color: c.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: context.l10n.searchProductsHint,
            hintStyle: TextStyle(color: c.textHint),
            prefixIcon: Icon(Icons.search_rounded,
                color: isDark ? c.textHint : AppColors.primaryLight, size: 22),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear_rounded,
                        color: c.textHint, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                      _applyFilters();
                    },
                  ),
                IconButton(
                  icon: Icon(Icons.qr_code_scanner_rounded,
                      color: c.textHint, size: 22),
                  onPressed: _scanBarcode,
                ),
              ],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onChanged: (v) {
            setState(() => _searchQuery = v);
            _applyFilters();
          },
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final l10n = context.l10n;
    final c = context.colors;

    // No categories yet — show empty state row
    if (_categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: GestureDetector(
          onTap: _showCreateCategoryDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.primaryLight.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded,
                    color: AppColors.primaryLight, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${l10n.categoryNotFound}. ${l10n.createCategory}',
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // "All" chip
          _CategoryChip(
            label: l10n.all,
            count: _all.length,
            selected: _selectedCategory == null,
            onTap: () => setState(() {
              _selectedCategory = null;
              _applyFilters();
            }),
          ),
          // Dynamic category chips from DB
          ..._categories.map((cat) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _CategoryChip(
                  label: localizedCategory(l10n, cat),
                  count: _categoryCount(cat),
                  selected: _selectedCategory == cat,
                  onTap: () => setState(() {
                    _selectedCategory =
                        _selectedCategory == cat ? null : cat;
                    _applyFilters();
                  }),
                ),
              )),
          // "+" chip to create a new category
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: _showCreateCategoryDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.inputBorder),
                ),
                child: Icon(Icons.add_rounded,
                    color: c.textHint, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            l10n.productsCount(_filtered.length),
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.inputBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortOption,
                dropdownColor: c.surface,
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: c.textHint, size: 18),
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Poppins'),
                isDense: true,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _sortOption = v);
                    _applyFilters();
                  }
                },
                items: [
                  DropdownMenuItem(
                      value: 'name_az', child: Text(l10n.sortNameAZ)),
                  DropdownMenuItem(
                      value: 'name_za', child: Text(l10n.sortNameZA)),
                  DropdownMenuItem(
                      value: 'stock_lh', child: Text(l10n.sortStockLowHigh)),
                  DropdownMenuItem(
                      value: 'stock_hl', child: Text(l10n.sortStockHighLow)),
                  DropdownMenuItem(
                      value: 'recent', child: Text(l10n.sortRecentlyAdded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    final c = context.colors;
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.filterByStock,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _FilterOption(l10n.allProducts, _stockFilter == 'all', () {
              setState(() {
                _stockFilter = 'all';
                _applyFilters();
              });
              Navigator.pop(context);
            }),
            _FilterOption(l10n.lowStock, _stockFilter == 'low', () {
              setState(() {
                _stockFilter = _stockFilter == 'low' ? 'all' : 'low';
                _applyFilters();
              });
              Navigator.pop(context);
            }, color: c.warning),
            _FilterOption(l10n.outOfStock, _stockFilter == 'out', () {
              setState(() {
                _stockFilter = _stockFilter == 'out' ? 'all' : 'out';
                _applyFilters();
              });
              Navigator.pop(context);
            }, color: c.danger),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deleteProduct,
            style: TextStyle(color: c.textPrimary, fontFamily: 'Poppins')),
        content: Text(
          l10n.deleteProductConfirm(product.name),
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel,
                style: TextStyle(color: c.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete,
                style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && product.id != null) {
      await getIt<ProductRepository>().deleteProduct(product.id!);
      _loadProducts();
    }
  }

  Widget _buildEmptyState() {
    final c = context.colors;
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inventory_2_outlined,
                size: 36, color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? l10n.noProductsMatch(_searchQuery)
                : l10n.noProductsYet,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.addFirstProductHint,
            style: TextStyle(color: c.textHint, fontSize: 13),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () =>
                context.push('/inventory/add').then((_) => _loadProducts()),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addProduct),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared small widgets ────────────────────────────────────────────────────

class _FilterOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterOption(this.label, this.selected, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    final sc = context.colors;
    final c = color ?? AppColors.primaryLight;
    return ListTile(
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? c : sc.textHint,
        size: 20,
      ),
      title: Text(label,
          style: TextStyle(
              color: selected ? c : sc.textSecondary, fontSize: 14)),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected && isDark
              ? const LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? (isDark ? null : AppColors.primaryLightTheme)
              : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : c.inputBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : c.textSecondary,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : c.divider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? Colors.white : c.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Product Card ────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductCard(
      {required this.product,
      required this.onTap,
      required this.onDelete});

  Color _stockColor(AppSemanticColors c) {
    if (product.stockQuantity == 0) return c.danger;
    if (product.stockQuantity <= product.reorderLevel) return c.warning;
    return c.success;
  }

  String _stockLabel(AppLocalizations l10n) {
    if (product.stockQuantity == 0) return l10n.outLabel;
    if (product.stockQuantity <= product.reorderLevel) return l10n.lowLabel;
    return l10n.inStock;
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

  double get _margin {
    if (product.sellingPrice <= 0 || product.costPrice <= 0) return 0;
    return ((product.sellingPrice - product.costPrice) /
            product.sellingPrice) *
        100;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final catColor = _categoryColor(product.category);
    final stockColor = _stockColor(c);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: Row(
          children: [
            // Left: product image / initial avatar
            ProductAvatar(
              product: product,
              size: 50,
              catColor: catColor,
              borderRadiusValue: 12,
            ),
            const SizedBox(width: 12),
            // Center: name + category badge + price + margin
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (product.category != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            localizedCategory(l10n, product.category!),
                            style: TextStyle(
                                fontSize: 10,
                                color: catColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        AppFormatters.formatCurrency(product.sellingPrice),
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (product.costPrice > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          l10n.marginPercent(_margin.toStringAsFixed(0)),
                          style: TextStyle(
                              color: c.textHint, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: stock status dot + qty label
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: stockColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _stockLabel(l10n),
                      style: TextStyle(
                          color: stockColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.qtyLabel('${product.stockQuantity}'),
                  style: TextStyle(
                      color: c.textHint, fontSize: 12),
                ),
              ],
            ),
            // Three-dot overflow menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: c.textHint, size: 20),
              color: c.surface,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: c.surfaceBorder)),
              onSelected: (v) {
                if (v == 'view') onTap();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'view',
                  child: Row(children: [
                    Icon(Icons.visibility_rounded,
                        size: 18, color: c.textSecondary),
                    const SizedBox(width: 10),
                    Text(l10n.viewDetails,
                        style:
                            TextStyle(color: c.textPrimary, fontSize: 13)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: c.danger),
                    const SizedBox(width: 10),
                    Text(l10n.delete,
                        style: TextStyle(
                            color: c.danger, fontSize: 13)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
