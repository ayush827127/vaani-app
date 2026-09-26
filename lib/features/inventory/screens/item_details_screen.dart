import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/item.dart';
import '../../../shared/models/item_image.dart';
import '../repositories/item_repository.dart';
import '../../../shared/widgets/item_avatar.dart';
import '../../../l10n/l10n_extensions.dart';

class ItemDetailsScreen extends StatefulWidget {
  final int itemId;
  const ItemDetailsScreen({super.key, required this.itemId});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen>
    with SingleTickerProviderStateMixin {
  Item? _item;
  // The item's full gallery — items.imagePath/imageUrl (what ItemAvatar
  // reads) is only a denormalized cache of whichever one of these is
  // primary, kept for cheap single-image reads (list cards, invoice PDFs).
  // This screen is the one place that needs the complete collection.
  List<ItemImage> _images = [];
  List<Map<String, Object?>> _stockHistory = [];
  bool _isLoading = true;
  // Set only on a genuine load failure (e.g. a database error) — distinct
  // from `_item == null` after a *successful* load, which means the item
  // itself doesn't exist (already-deleted, bad id, ...) and gets its own
  // "not found" state below.
  String? _loadError;
  // Guards against a double-tap on Delete firing two deletes for the same
  // item while the first is still in flight.
  bool _isDeleting = false;
  late final TabController _tabController;
  String _txnFilter = 'all'; // all | purchases | sales | adjustments

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final repo = getIt<ItemRepository>();
      final item = await repo.getItemById(widget.itemId);
      // Stock History is meaningless for a service (regardless of what
      // inventoryEnabled happens to hold — see the same combined-flag
      // reasoning in build()), so it's not even fetched for one — nothing
      // to show, no point querying.
      final history = item != null && item.inventoryEnabled && item.itemType != ItemType.service
          ? await repo.getStockHistory(widget.itemId)
          : <Map<String, Object?>>[];
      final images = item != null ? await repo.getImages(widget.itemId) : <ItemImage>[];
      if (!mounted) return;
      setState(() {
        _item = item;
        _stockHistory = history;
        _images = images;
        _isLoading = false;
      });
    } catch (e, st) {
      // Never swallowed — logged with its real stack trace, with a plain
      // "couldn't load, try again" state on screen instead of a blank or
      // frozen page.
      debugPrint('[ItemDetailsScreen] load failed for item ${widget.itemId}: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _isLoading = false;
      });
    }
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

  // ── Image gallery ────────────────────────────────────────────────────
  //
  // items.imagePath/imageUrl (what the AppBar's small ItemAvatar reads) is
  // only a denormalized cache of the primary row in item_images — correct
  // for a list thumbnail, but this is the one screen that should show the
  // complete collection. A single image keeps the plain presentation (no
  // swipe chrome for one photo); two or more become a swipeable carousel
  // starting on the primary image, with a page counter and dot indicator.

  Widget _buildImageGallery(AppSemanticColors c) {
    if (_images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: _resolveItemImage(_images.first, c),
        ),
      );
    }
    final initialPage = _images.indexWhere((img) => img.isPrimary).clamp(0, _images.length - 1);
    return _ItemImageCarousel(images: _images, initialPage: initialPage);
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
    final currentStock = _item?.stockQuantity ?? 0;
    DateTime date = DateTime.now();
    String reason = reasons.first;
    // Guards the confirm button against a double-tap firing two adjustStock
    // calls for the same sheet while the first is still in flight.
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => StatefulBuilder(
        builder: (bsCtx, setSheetState) {
          final hasInput = ctrl.text.trim().isNotEmpty;
          final qty = int.tryParse(ctrl.text) ?? 0;
          final exceedsStock = !isAdd && qty > currentStock;
          final isValid = qty > 0 && !exceedsStock;
          final newStock = isAdd ? currentStock + qty : currentStock - qty;
          return Padding(
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
                    l10n.currentStock('$currentStock'),
                    style: TextStyle(color: c.textHint, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: TextStyle(color: c.textPrimary, fontSize: 18),
                    onChanged: (_) => setSheetState(() {}),
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
                  if (hasInput && !isValid) ...[
                    const SizedBox(height: 6),
                    Text(
                      exceedsStock ? l10n.stockExceedsAvailableError : l10n.stockQuantityRequiredError,
                      style: TextStyle(color: c.danger, fontSize: 12),
                    ),
                  ],
                  if (isValid) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$currentStock  →  $newStock',
                              style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                          Text('${isAdd ? '+' : '-'}$qty ${l10n.unitsLabel}',
                              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving ? null : () => Navigator.pop(bsCtx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: c.inputBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(l10n.cancel, style: TextStyle(color: c.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (!isValid || isSaving)
                              ? null
                              : () async {
                                  setSheetState(() => isSaving = true);
                                  final type = isAdd
                                      ? AppConstants.txnRestock
                                      : (reason == 'Damaged' ? AppConstants.txnDamage : AppConstants.txnAdjustment);
                                  try {
                                    await getIt<ItemRepository>().adjustStock(
                                      widget.itemId,
                                      isAdd ? qty : -qty,
                                      type,
                                      reason: reason,
                                      notes: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                                      date: date,
                                    );
                                    if (bsCtx.mounted) Navigator.pop(bsCtx);
                                    if (mounted) await _load();
                                  } catch (e, st) {
                                    // Never swallowed — logged with its real stack trace. Previously
                                    // unguarded: a DatabaseException here (e.g. a schema mismatch)
                                    // left the sheet silently stuck open with no error and no stock
                                    // change, indistinguishable from the button doing nothing.
                                    debugPrint(
                                        '[ItemDetailsScreen] adjustStock failed for item ${widget.itemId}: $e\n$st');
                                    if (bsCtx.mounted) {
                                      setSheetState(() => isSaving = false);
                                      ScaffoldMessenger.of(bsCtx).showSnackBar(SnackBar(
                                        content: Text(l10n.errorGeneric('$e')),
                                        backgroundColor: c.danger,
                                      ));
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(isAdd ? l10n.addStock : l10n.confirmAdjustment,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: color.withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteItem() async {
    if (_isDeleting) return; // already mid-delete — ignore a second tap
    final c = context.colors;
    final l10n = context.l10n;
    // showDialog's own Navigator.pop calls close only this dialog route —
    // there's nothing further needed here to "properly close" it beyond
    // letting this await resolve.
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
    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      // A soft delete (is_active = 0) — see ItemRepository.deleteItem's own
      // doc comment. item_images/item_aliases/stock history/past bills that
      // reference this item are deliberately left attached to the
      // now-inactive row, same as every other soft-deleted item, so past
      // invoices/reports stay intact.
      await getIt<ItemRepository>().deleteItem(widget.itemId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.itemDeleted), backgroundColor: c.success),
      );
      // The Inventory list already refreshes itself on return — see
      // inventory_screen.dart's `.then((_) => _loadItems())` on the push
      // that opened this screen — so popping here is the only handoff
      // needed for "refresh the list after delete".
      context.pop();
    } catch (e, st) {
      // Never swallowed — logged with its real stack trace, with a plain-
      // language message on screen instead of the app going quiet (the
      // black/frozen-screen failure mode this replaces).
      debugPrint('[ItemDetailsScreen] delete failed for item ${widget.itemId}: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorGeneric('$e')), backgroundColor: c.danger),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _copyBarcode(String barcode) {
    Clipboard.setData(ClipboardData(text: barcode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedToClipboard), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (_isLoading) {
      return Scaffold(body: const _DetailsSkeleton());
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: Text(l10n.item, style: TextStyle(color: c.textPrimary)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 44, color: c.textHint),
                const SizedBox(height: 12),
                Text(l10n.unableToLoadItem,
                    style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(l10n.pleaseTryAgain, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _load, child: Text(l10n.retryLabel)),
              ],
            ),
          ),
        ),
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
    // Two independent flags — itemType and inventoryEnabled are separately
    // settable (see Item.inventoryEnabled's doc comment), so neither one
    // alone is safe to use for both decisions. isServiceType drives only
    // the "Product"/"Service" label. showInventory is the sole authority
    // for whether any stock UI renders — Service is an absolute veto here
    // regardless of what inventoryEnabled happens to hold (old/stale data,
    // or a value that predates the item ever becoming a service), matching
    // "a Service must never display inventory controls even if old/
    // incorrect stock values exist in the database".
    final isServiceType = p.itemType == ItemType.service;
    final showInventory = p.inventoryEnabled && !isServiceType;
    final margin = p.sellingPrice > 0 ? ((p.sellingPrice - p.costPrice) / p.sellingPrice) * 100 : 0.0;
    final profitAmount = p.sellingPrice - p.costPrice;
    final stockMax = p.reorderLevel * 3;
    final stockRatio = stockMax > 0 ? (p.stockQuantity / stockMax).clamp(0.0, 1.0) : 0.0;
    final isOut = p.stockQuantity == 0;
    final isLow = !isOut && p.stockQuantity <= p.reorderLevel;
    final stockColor = isOut ? c.danger : (isLow ? c.warning : c.success);
    // Header badge uses the plain In/Low/Out wording; the Current Stock
    // card below uses "Good Stock" for the same healthy state instead —
    // deliberately different phrasing for the same 3-way status, matching
    // how each spot reads naturally in context.
    final headerStockLabel = isOut ? l10n.outOfStock : (isLow ? l10n.lowStock : l10n.inStock);
    final stockCardLabel = isOut ? l10n.outOfStock : (isLow ? l10n.lowStock : l10n.goodStockLabel);

    return Scaffold(
      appBar: _buildHeader(context, p, headerStockLabel, stockColor, isServiceType, showInventory),
      // NestedScrollView is what makes the tab bar pin at the top only once
      // scrolled to it, with everything above (image/pricing/stock/actions)
      // and everything below (each tab's own content) sharing ONE scroll
      // position — the previous plain Column had no scrolling at all above
      // the tabs, and squeezed the TabBarView into whatever height was left
      // over via Expanded, which is why the tab content felt cramped and
      // never moved together with the header.
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  if (_images.isNotEmpty) ...[
                    _buildImageGallery(c),
                    const SizedBox(height: 12),
                  ],
                  _buildPricingSummary(c, l10n, p, margin),
                  if (showInventory) ...[
                    const SizedBox(height: 12),
                    _buildCurrentStock(c, l10n, p, stockCardLabel, stockColor, stockRatio),
                    const SizedBox(height: 12),
                    _buildStockActions(c, l10n),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // SliverOverlapAbsorber is the required counterpart to the
          // SliverOverlapInjector each tab uses below — without it, the
          // injector has no absorbed extent to read and throws (a null-check
          // crash on every tab, which is exactly why all four went blank).
          // Only the pinned header needs absorbing; the scrollable content
          // above it isn't still overlapping anything once scrolled away.
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  indicatorColor: AppColors.primaryLight,
                  indicatorWeight: 2.5,
                  labelColor: AppColors.primaryLight,
                  unselectedLabelColor: c.textSecondary,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(text: l10n.overviewTabLabel, height: 52),
                    Tab(text: l10n.transactionsTabLabel, height: 52),
                    Tab(text: l10n.pricingTabLabel, height: 52),
                    Tab(text: l10n.detailsTabLabel, height: 52),
                  ],
                ),
                backgroundColor: c.surface,
                borderColor: c.divider,
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _OverviewTab(
              history: _stockHistory,
              showInventory: showInventory,
              onViewAll: () => _tabController.animateTo(1),
            ),
            _TransactionsTab(
              history: _stockHistory,
              showInventory: showInventory,
              filter: _txnFilter,
              onFilterChanged: (f) => setState(() => _txnFilter = f),
            ),
            _PricingTab(item: p, margin: margin, profitAmount: profitAmount),
            _DetailsTab(item: p, onCopyBarcode: _copyBarcode),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildHeader(BuildContext context, Item p, String stockLabel, Color stockColor,
      bool isServiceType, bool showInventory) {
    final c = context.colors;
    final l10n = context.l10n;
    final catColor = _categoryColor(p.category);
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: c.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: c.surface,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          ItemAvatar(item: p, size: 42, catColor: catColor, borderRadiusValue: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 2),
                Text(
                  p.category != null ? localizedCategory(l10n, p.category!) : l10n.uncategorized,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 2),
                if (isServiceType)
                  Text(l10n.itemTypeService,
                      style: const TextStyle(
                          color: AppColors.primaryLight, fontSize: 11.5, fontWeight: FontWeight.w600))
                else if (showInventory)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: stockColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(stockLabel,
                          style: TextStyle(color: stockColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  )
                else
                  // A Product with inventory tracking switched off — no
                  // stock dot (there's no stock being tracked to report).
                  Text(l10n.itemTypeProduct,
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
          color: c.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.surfaceBorder)),
          onSelected: (v) {
            if (v == 'edit') {
              context.push('/inventory/add', extra: p.id).then((_) => _load());
            } else if (v == 'delete') {
              _deleteItem();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18, color: c.textSecondary),
                const SizedBox(width: 10),
                Text(l10n.editItem, style: TextStyle(color: c.textPrimary)),
              ]),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: !_isDeleting,
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                const SizedBox(width: 10),
                Text(l10n.deleteItem, style: TextStyle(color: c.danger)),
              ]),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildPricingSummary(AppSemanticColors c, AppLocalizations l10n, Item p, double margin) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
              child: _PricingStat(
                  value: AppFormatters.formatCurrency(p.sellingPrice), label: l10n.sellingPrice, c: c)),
          _pricingDivider(c),
          Expanded(
              child:
                  _PricingStat(value: AppFormatters.formatCurrency(p.costPrice), label: l10n.costPrice, c: c)),
          _pricingDivider(c),
          Expanded(
              child: _PricingStat(
                  value: '${margin.toStringAsFixed(1)}%',
                  label: l10n.profitMargin,
                  c: c,
                  color: margin >= 20 ? c.success : c.warning)),
          _pricingDivider(c),
          Expanded(
              child: _PricingStat(value: '${p.gstRate.toInt()}%', label: l10n.gstRate, c: c)),
        ],
      ),
    );
  }

  Widget _pricingDivider(AppSemanticColors c) => Container(width: 1, height: 30, color: c.divider);

  Widget _buildCurrentStock(
      AppSemanticColors c, AppLocalizations l10n, Item p, String stockLabel, Color stockColor, double stockRatio) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.stockLevel,
                  style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stockColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: stockColor.withValues(alpha: 0.4)),
                ),
                child: Text(stockLabel,
                    style: TextStyle(fontSize: 11.5, color: stockColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${p.stockQuantity}',
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold, color: stockColor, fontFamily: 'Poppins')),
              const SizedBox(width: 6),
              Text(l10n.unitsLabel, style: TextStyle(color: c.textHint, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stockRatio,
              minHeight: 7,
              backgroundColor: c.surfaceBorder,
              valueColor: AlwaysStoppedAnimation<Color>(stockColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.reorderAt('${p.reorderLevel}'), style: TextStyle(color: c.textHint, fontSize: 11.5)),
              Text(l10n.stockValue(AppFormatters.formatCurrency(p.sellingPrice * p.stockQuantity)),
                  style: TextStyle(color: c.textHint, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockActions(AppSemanticColors c, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _addStock,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(l10n.addStock, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _removeStock,
            icon: const Icon(Icons.remove_rounded, size: 20),
            label: Text(l10n.adjust, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.warning,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Compact pricing stat (used only in the top summary strip) ──────────────

class _PricingStat extends StatelessWidget {
  final String value;
  final String label;
  final AppSemanticColors c;
  final Color? color;
  const _PricingStat({required this.value, required this.label, required this.c, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color ?? c.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: c.textHint, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ── Item image gallery ───────────────────────────────────────────────────
//
// Same local-file-then-network-then-placeholder resolution every other
// image read in this app uses (item_details' own header ItemAvatar,
// add_item_screen's picker gallery, shop logo, customer photos).
Widget _resolveItemImage(ItemImage img, AppSemanticColors c) {
  if (img.imagePath != null && File(img.imagePath!).existsSync()) {
    return Image.file(File(img.imagePath!), fit: BoxFit.cover, width: double.infinity);
  }
  if (img.imageUrl != null) {
    return Image.network(
      img.imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, __, ___) => Container(color: c.divider),
    );
  }
  return Container(color: c.divider);
}

class _ItemImageCarousel extends StatefulWidget {
  final List<ItemImage> images;
  final int initialPage;
  const _ItemImageCarousel({required this.images, required this.initialPage});

  @override
  State<_ItemImageCarousel> createState() => _ItemImageCarouselState();
}

class _ItemImageCarouselState extends State<_ItemImageCarousel> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _resolveItemImage(widget.images[i], c),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_page + 1}/${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ─────────────────────────────────────────────────────
//
// Keeps the page's real structure on screen while _load() is in flight,
// rather than a blank centered spinner.

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget block({double width = double.infinity, double height = 14, double radius = 6}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(radius)),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              block(width: 42, height: 42, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  block(width: 120, height: 15),
                  const SizedBox(height: 8),
                  block(width: 80, height: 11),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            block(height: 64, radius: 14),
            const SizedBox(height: 12),
            block(height: 130, radius: 16),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: block(height: 48, radius: 12)),
              const SizedBox(width: 10),
              Expanded(child: block(height: 48, radius: 12)),
            ]),
            const SizedBox(height: 20),
            block(width: 200, height: 13),
          ],
        ),
      ),
    );
  }
}

// ── Pinned tab bar (SliverPersistentHeader delegate) ─────────────────────
//
// What actually makes the tab bar "become sticky only after scrolling to
// it" rather than a permanently fixed bar: this sliver lives in
// NestedScrollView's headerSliverBuilder, right after the scrollable
// header content, with pinned: true — it scrolls normally with the rest
// of the header until it reaches the top of the viewport, then stays
// there while everything else (the header above, each tab's content
// below) keeps scrolling underneath it.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;
  const _TabBarDelegate(this.tabBar, {required this.backgroundColor, required this.borderColor});

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar ||
      backgroundColor != oldDelegate.backgroundColor ||
      borderColor != oldDelegate.borderColor;
}

// ── Shared per-tab scroll view ────────────────────────────────────────────
//
// The SliverOverlapInjector is the other half of the NestedScrollView
// boilerplate — it feeds back how much of the pinned tab bar is currently
// overlapping this tab's content, so each tab's own scroll position stays
// correctly in sync with the shared outer scroll instead of double-counting
// (or fighting over) the header's height. Every tab that's just a plain
// scrollable list of widgets (Overview, Pricing, Details) uses this; the
// one exception is Transactions, which has its own filter row above the
// list and builds its slivers directly for that reason.
class _TabScrollView extends StatelessWidget {
  final List<Widget> children;
  const _TabScrollView({required this.children});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ],
    );
  }
}

// ── Overview tab ─────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final List<Map<String, Object?>> history;
  // Whether this item tracks inventory at all — a Service (or a Product
  // with tracking switched off) never has stock movements to show here,
  // regardless of what `history` happens to contain (it's already always
  // empty for those via _load()'s own gating, but this is the explicit,
  // data-independent authority so stale/old rows could never leak through).
  final bool showInventory;
  final VoidCallback onViewAll;
  const _OverviewTab({required this.history, required this.showInventory, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (!showInventory) {
      return _TabScrollView(
        children: [
          _EmptyState(
            icon: Icons.design_services_rounded,
            title: l10n.trackInventoryOffHint,
            subtitle: '',
          ),
        ],
      );
    }

    final recent = history.take(3).toList();

    return _TabScrollView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.recentActivityLabel,
                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            if (recent.isNotEmpty)
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                child: Text(l10n.viewAll,
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.noRecentActivity,
            subtitle: l10n.noRecentActivitySubtitle,
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.surfaceBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++)
                  _StockHistoryRow(row: recent[i], showDivider: i > 0),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Transactions tab ─────────────────────────────────────────────────────

class _TransactionsTab extends StatelessWidget {
  final List<Map<String, Object?>> history;
  final bool showInventory;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  const _TransactionsTab({
    required this.history,
    required this.showInventory,
    required this.filter,
    required this.onFilterChanged,
  });

  List<Map<String, Object?>> _filtered() {
    if (filter == 'all') return history;
    return history.where((row) {
      final type = row['type'] as String? ?? '';
      switch (filter) {
        case 'purchases':
          return type == AppConstants.txnRestock;
        case 'sales':
          return type == AppConstants.txnSale;
        case 'adjustments':
          return type != AppConstants.txnRestock && type != AppConstants.txnSale;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    if (!showInventory) {
      return _TabScrollView(
        children: [
          _EmptyState(
            icon: Icons.design_services_rounded,
            title: l10n.trackInventoryOffHint,
            subtitle: '',
          ),
        ],
      );
    }

    final rows = _filtered();
    final chips = <(String, String)>[
      ('all', l10n.filterAllTransactions),
      ('purchases', l10n.filterPurchases),
      ('sales', l10n.filterSales),
      ('adjustments', l10n.filterAdjustments),
    ];

    // Built directly as slivers (rather than through _TabScrollView) since
    // the filter chip row scrolls away with everything else here — it's
    // not a second sticky header, just the first item in this tab's list —
    // and the rows themselves stay lazily built via SliverChildBuilderDelegate
    // (a stock history can be long), matching the previous ListView.builder.
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (value, label) = chips[i];
                  final active = filter == value;
                  return GestureDetector(
                    onTap: () => onFilterChanged(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primaryLight : c.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? AppColors.primaryLight : c.inputBorder),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : c.textSecondary)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (rows.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: _EmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.noStockHistoryYet,
                subtitle: l10n.noRecentActivitySubtitle,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.surfaceBorder),
                  ),
                  child: _StockHistoryRow(row: rows[i], showDivider: false, showTime: true),
                ),
                childCount: rows.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Pricing tab ───────────────────────────────────────────────────────────

class _PricingTab extends StatelessWidget {
  final Item item;
  final double margin;
  final double profitAmount;
  const _PricingTab({required this.item, required this.margin, required this.profitAmount});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return _TabScrollView(
      children: [
        Text(l10n.priceInformationLabel,
            style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _InfoCardGroup(c: c, rows: [
          (l10n.sellingPrice, AppFormatters.formatCurrency(item.sellingPrice), null),
          (l10n.costPrice, AppFormatters.formatCurrency(item.costPrice), null),
          (l10n.profit, AppFormatters.formatCurrency(profitAmount), profitAmount >= 0 ? c.success : c.danger),
          (l10n.profitMargin, '${margin.toStringAsFixed(1)}%', margin >= 20 ? c.success : c.warning),
        ]),
        const SizedBox(height: 20),
        Text(l10n.taxInformationLabel,
            style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _InfoCardGroup(c: c, rows: [
          (l10n.gstRate, '${item.gstRate.toInt()}%', null),
        ]),
      ],
    );
  }
}

class _InfoCardGroup extends StatelessWidget {
  final AppSemanticColors c;
  final List<(String, String, Color?)> rows;
  const _InfoCardGroup({required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: i > 0
                  ? BoxDecoration(border: Border(top: BorderSide(color: c.divider)))
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(rows[i].$1, style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                  Text(rows[i].$2,
                      style: TextStyle(
                          color: rows[i].$3 ?? c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Details tab ───────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  final Item item;
  final void Function(String barcode) onCopyBarcode;
  const _DetailsTab({required this.item, required this.onCopyBarcode});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final p = item;
    return _TabScrollView(
      children: [
        Text(l10n.itemDetails, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.surfaceBorder),
          ),
          child: Column(
            children: [
              if (p.sku != null) _DetailRow(l10n.skuCode, p.sku!),
              _DetailRow(
                l10n.barcode,
                p.barcode ?? l10n.noBarcodeAssigned,
                trailing: p.barcode != null
                    ? IconButton(
                        icon: Icon(Icons.copy_rounded, size: 16, color: c.textHint),
                        tooltip: l10n.copiedToClipboard,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => onCopyBarcode(p.barcode!),
                      )
                    : null,
              ),
              _DetailRow(l10n.category, p.category != null ? localizedCategory(l10n, p.category!) : l10n.uncategorized),
              _DetailRow(l10n.itemTypeLabel, p.itemType == ItemType.service ? l10n.itemTypeService : l10n.itemTypeProduct),
              if (p.inventoryEnabled && p.itemType != ItemType.service)
                _DetailRow(l10n.reorderLevel, '${p.reorderLevel} ${l10n.unitsLabel}'),
              _DetailRow(l10n.addedOn, AppFormatters.formatDate(p.createdAt)),
              _DetailRow(l10n.lastUpdated, AppFormatters.formatDate(p.updatedAt), isLast: p.aliases.isEmpty),
              if (p.aliases.isNotEmpty) _DetailRow(l10n.voiceAliases, p.aliases.join(', '), isLast: true),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: c.textHint),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: c.textHint, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final bool isLast;
  const _DetailRow(this.label, this.value, {this.trailing, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: isLast ? null : BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textHint, fontSize: 13)),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock history row (shared by Overview's "Recent Activity" and the full
// Transactions list) ─────────────────────────────────────────────────────
//
// Every stock change — Add/Remove Stock entries, sales, and void/return
// reversals alike — already lands in inventory_transactions (see
// ItemRepository.adjustStock and InvoiceRepository's create/void/return);
// this just displays that one existing audit trail.

class _StockHistoryRow extends StatelessWidget {
  final Map<String, Object?> row;
  final bool showDivider;
  final bool showTime;
  const _StockHistoryRow({required this.row, required this.showDivider, this.showTime = false});

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
    final dateText = showTime
        ? '${AppFormatters.formatDate(createdAt)} · ${AppFormatters.formatTime(createdAt)}'
        : AppFormatters.formatDate(createdAt);

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
                Text(typeLabel,
                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (reference != null && reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(reference, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                ],
                const SizedBox(height: 2),
                Text(dateText, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(notes,
                      style: TextStyle(color: c.textHint, fontSize: 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
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
