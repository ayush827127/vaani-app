import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/permission_service.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/item.dart';
import '../../../shared/widgets/barcode_scanner_screen.dart';
import '../repositories/item_repository.dart';
import '../repositories/category_repository.dart';
import '../widgets/category_picker_sheet.dart';
import '../../../l10n/l10n_extensions.dart';

/// One entry in the gallery being edited — either an existing ItemImage
/// (has [existingId]) or a freshly-picked local file not yet persisted
/// ([existingId] is null). Everything here is provisional until Save: adds,
/// removes and reordering only touch this list; the repository only sees
/// the final result, all at once, when the form is actually submitted —
/// same "nothing commits until Save" contract as every other field on this
/// form.
class _GalleryEntry {
  final int? existingId;
  final String? imagePath;
  final String? imageUrl;
  const _GalleryEntry({this.existingId, this.imagePath, this.imageUrl});
}

class AddItemScreen extends StatefulWidget {
  final int? itemId;
  const AddItemScreen({super.key, this.itemId});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _reorderCtrl = TextEditingController(text: '10');
  final _aliasCtrl = TextEditingController();

  String? _category;
  double _gstRate = 5.0;
  ItemType _itemType = ItemType.product;
  // Independently overridable from _itemType (see the note on
  // Item.inventoryEnabled) — but new items default it from the type picked,
  // since that's the right guess almost every time: a physical good tracks
  // stock, a service doesn't.
  bool _inventoryEnabled = true;
  bool _isLoading = false;
  bool _isGeneratingBarcode = false;
  bool _isEditing = false;
  Item? _existingItem;
  // The gallery being edited, and which entry (by index) is primary. Loaded
  // from item_images for an existing item; starts empty for a new one.
  List<_GalleryEntry> _images = [];
  int _primaryIndex = 0;
  final Set<int> _deletedExistingImageIds = {};
  List<String> _categories = [];
  int _shopId = 1;

  // ── Wizard state ──────────────────────────────────────────────────────
  // All three steps read/write the *same* controllers/fields above — moving
  // between steps only changes which of them are built on screen, so
  // nothing entered is ever lost switching back and forth.
  int _currentStep = 0;
  bool _moreOptionsExpanded = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initShopId();
    if (widget.itemId != null) {
      _isEditing = true;
      _loadItem();
    }
  }

  Future<void> _initShopId() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final cats = await getIt<CategoryRepository>().getCategories(_shopId);
    if (mounted) setState(() => _categories = cats);
  }

  Future<void> _loadItem() async {
    try {
      final repo = getIt<ItemRepository>();
      final item = await repo.getItemById(widget.itemId!);
      if (item == null || !mounted) return;
      final gallery = await repo.getImages(widget.itemId!);
      if (!mounted) return;
      setState(() {
        _existingItem = item;
        _nameCtrl.text = item.name;
        _skuCtrl.text = item.sku ?? '';
        _barcodeCtrl.text = item.barcode ?? '';
        _costCtrl.text = item.costPrice.toString();
        _priceCtrl.text = item.sellingPrice.toString();
        _stockCtrl.text = item.stockQuantity.toString();
        _reorderCtrl.text = item.reorderLevel.toString();
        _aliasCtrl.text = item.aliases.join(', ');
        _category = item.category;
        _gstRate = item.gstRate;
        _itemType = item.itemType;
        _inventoryEnabled = item.inventoryEnabled;
        _images = gallery
            .map((g) => _GalleryEntry(existingId: g.id, imagePath: g.imagePath, imageUrl: g.imageUrl))
            .toList();
        _primaryIndex = gallery.isEmpty ? 0 : gallery.indexWhere((g) => g.isPrimary).clamp(0, gallery.length - 1);
      });
    } catch (e, st) {
      // Never swallowed — logged with its real stack trace. A failure here
      // (e.g. a database error) previously left the form silently blank
      // with no explanation; this at least tells the user something went
      // wrong instead of the screen just quietly not working.
      debugPrint('[AddItemScreen] failed to load item ${widget.itemId}: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.errorGeneric('$e')),
        backgroundColor: context.colors.danger,
      ));
    }
  }

  /// Copies a picked file into the app's documents directory (same
  /// treatment every other picked image in this app gets) and appends it
  /// to the gallery being edited. The very first image added becomes
  /// primary automatically.
  Future<void> _addPickedFile(XFile picked) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, 'item_images'));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final ext = p.extension(picked.path);
      final filename = 'item_${DateTime.now().millisecondsSinceEpoch}_${_images.length}$ext';
      final dest = p.join(imagesDir.path, filename);
      await File(picked.path).copy(dest);

      if (mounted) {
        setState(() {
          _images.add(_GalleryEntry(imagePath: dest));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.couldNotPickImage('$e')),
          backgroundColor: context.colors.danger,
        ));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickMultiImage(maxWidth: 800, maxHeight: 800, imageQuality: 85);
    for (final file in picked) {
      await _addPickedFile(file);
    }
  }

  Future<void> _pickFromCamera() async {
    // Routed through the shared permission check (same one the barcode
    // scanner already uses below) instead of relying on image_picker's own
    // internal handling — that path never told the user why nothing
    // happened if camera access had been permanently denied.
    final granted = await PermissionService.requestCamera(context);
    if (!granted || !mounted) return;
    final picked =
        await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked != null) await _addPickedFile(picked);
  }

  void _removeImageAt(int index) {
    setState(() {
      final removed = _images.removeAt(index);
      if (removed.existingId != null) _deletedExistingImageIds.add(removed.existingId!);
      if (_images.isEmpty) {
        _primaryIndex = 0;
      } else if (_primaryIndex >= _images.length) {
        _primaryIndex = _images.length - 1;
      } else if (index < _primaryIndex) {
        _primaryIndex--;
      }
    });
  }

  void _setPrimary(int index) => setState(() => _primaryIndex = index);

  void _moveImage(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _images.length) return;
    setState(() {
      final item = _images.removeAt(index);
      _images.insert(target, item);
      // The primary designation follows whichever entry it was on, not the
      // slot — keep it pointed at the same image after the reorder.
      if (_primaryIndex == index) {
        _primaryIndex = target;
      } else if (_primaryIndex == target) {
        _primaryIndex = index;
      }
    });
  }

  void _showImageOptions() {
    final c = context.colors;
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.surfaceBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primaryLight),
              title: Text(l10n.chooseFromGallery,
                  style: TextStyle(color: c.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primaryLight),
              title: Text(l10n.takeAPhoto,
                  style: TextStyle(color: c.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickFromCamera();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Wizard navigation ────────────────────────────────────────────────

  void _goToStep(int step) => setState(() => _currentStep = step);

  void _goNextStep() {
    // Only the fields belonging to the step currently on screen are mounted
    // as FormFields at any given time, so validate() here only checks
    // those — it can't fail on a field the user hasn't reached yet.
    if (!_formKey.currentState!.validate()) return;
    if (_currentStep < 2) setState(() => _currentStep += 1);
  }

  void _goBackStep() {
    if (_currentStep > 0) setState(() => _currentStep -= 1);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final repo = getIt<ItemRepository>();

    final barcodeValue = _barcodeCtrl.text.trim().isEmpty
        ? null
        : _barcodeCtrl.text.trim();

    // Validate barcode uniqueness before saving.
    if (barcodeValue != null) {
      final isUnique = await repo.isBarcodeUnique(
        barcodeValue,
        excludeItemId: _existingItem?.id,
      );
      if (!isUnique) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.duplicateBarcodeError),
          backgroundColor: context.colors.danger,
        ));
        return;
      }
    }

    final aliases = _aliasCtrl.text
        .split(',')
        .map((a) => a.trim().toLowerCase())
        .where((a) => a.isNotEmpty)
        .toList();

    // imagePath/imageUrl are deliberately left off this object — they're
    // now a denormalized cache the gallery below keeps in sync
    // (ItemRepository._syncPrimaryCache), not written directly by this form.
    final item = Item(
      id: _existingItem?.id,
      shopId: shopId,
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      barcode: barcodeValue,
      category: _category,
      costPrice: double.tryParse(_costCtrl.text) ?? 0,
      sellingPrice: double.parse(_priceCtrl.text),
      gstRate: _gstRate,
      // Stock fields are hidden in the UI (and meaningless) once inventory
      // tracking is off — force them to 0 rather than saving whatever was
      // last typed/loaded, so a service never shows a stale stock count.
      stockQuantity: _inventoryEnabled ? (int.tryParse(_stockCtrl.text) ?? 0) : 0,
      reorderLevel: _inventoryEnabled ? (int.tryParse(_reorderCtrl.text) ?? 10) : 0,
      itemType: _itemType,
      inventoryEnabled: _inventoryEnabled,
      aliases: aliases,
      createdAt: _existingItem?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Previously unguarded — a DatabaseException here (e.g. the barcode
    // uniqueness race: isBarcodeUnique() above only checks active items,
    // but the DB's unique index covers every row, so reusing a just-deleted
    // item's barcode could still throw here) left the form permanently
    // stuck on its loading spinner with no error shown and no way to retry.
    try {
      int itemId;
      if (_isEditing) {
        itemId = _existingItem!.id!;
        await repo.updateItem(item);
      } else {
        itemId = await repo.insertItem(item);
      }

      // Gallery: apply removals first, then persist every remaining entry
      // (new local picks get inserted; existing ones are already rows —
      // just need their final order), then set primary/order to match
      // exactly what's on screen. All provisional until this point, same
      // as the rest of the form.
      for (final id in _deletedExistingImageIds) {
        await repo.removeImage(itemId, id);
      }
      final finalIds = <int>[];
      for (final entry in _images) {
        if (entry.existingId != null) {
          finalIds.add(entry.existingId!);
        } else {
          finalIds.add(await repo.addImage(itemId, imagePath: entry.imagePath));
        }
      }
      if (finalIds.isNotEmpty) {
        await repo.reorderImages(itemId, finalIds);
        await repo.setPrimaryImage(itemId, finalIds[_primaryIndex.clamp(0, finalIds.length - 1)]);
      }

      // Persist category in categories table so it's available for other items
      if (_category != null) {
        await getIt<CategoryRepository>().addCategory(_shopId, _category!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.errorGeneric('$e')),
        backgroundColor: context.colors.danger,
      ));
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    final successColor = context.colors.success;
    final l10n = context.l10n;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? l10n.itemUpdated : l10n.itemAdded),
        backgroundColor: successColor,
      ),
    );
  }

  Future<void> _scanBarcodeForItem() async {
    final granted = await PermissionService.requestCamera(context);
    if (!granted || !mounted) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && mounted) {
      setState(() => _barcodeCtrl.text = code.trim().replaceAll(RegExp(r'[\r\n\t]'), ''));
    }
  }

  Future<void> _generateBarcodeForItem() async {
    setState(() => _isGeneratingBarcode = true);
    final code = await getIt<ItemRepository>().generateUniqueBarcode();
    if (!mounted) return;
    setState(() {
      _barcodeCtrl.text = code;
      _isGeneratingBarcode = false;
    });
    _openBarcodePreview(code);
  }

  void _openBarcodePreview(String barcode) {
    final name = _nameCtrl.text.trim();
    context.push('/inventory/barcode-preview', extra: {
      'barcode': barcode,
      'itemName': name.isNotEmpty ? name : barcode,
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _reorderCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editItem : l10n.addItem),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildStepIndicator(c, l10n),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: switch (_currentStep) {
                  0 => _buildStep1(c, l10n),
                  1 => _buildStep2(c, l10n),
                  _ => _buildStep3(c, l10n),
                },
              ),
            ),
            _buildStepActions(c, l10n),
          ],
        ),
      ),
    );
  }

  // ── Step indicator ───────────────────────────────────────────────────

  Widget _buildStepIndicator(AppSemanticColors c, AppLocalizations l10n) {
    final labels = [l10n.basicDetailsStepLabel, l10n.inventoryStepLabel, l10n.reviewStepLabel];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final connectorDone = (i ~/ 2) < _currentStep;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                height: 2,
                color: connectorDone ? AppColors.primaryLight : c.divider,
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex < _currentStep;
          final isActive = stepIndex == _currentStep;
          final active = isDone || isActive;
          return SizedBox(
            width: 72,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.primaryLight : c.surface,
                    border: Border.all(color: active ? AppColors.primaryLight : c.inputBorder, width: 1.5),
                  ),
                  child: isDone
                      ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                      : Text('${stepIndex + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isActive ? Colors.white : c.textHint)),
                ),
                const SizedBox(height: 5),
                Text(
                  labels[stepIndex],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      color: isActive ? AppColors.primaryLight : c.textHint,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepActions(AppSemanticColors c, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _goBackStep,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(l10n.backLabel),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: c.inputBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : (_currentStep < 2 ? _goNextStep : _save),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_currentStep < 2 ? Icons.arrow_forward_rounded : Icons.check_rounded, size: 18),
              label: Text(_currentStep < 2 ? l10n.continueLabel : (_isEditing ? l10n.updateItem : l10n.saveItem)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1 — Basic Details ───────────────────────────────────────────

  Widget _buildStep1(AppSemanticColors c, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageGallery(c, l10n),
        const SizedBox(height: 20),
        _buildField(l10n.itemName, _nameCtrl,
            validator: (v) => v?.trim().isEmpty == true ? l10n.itemNameRequiredError : null),
        const SizedBox(height: 4),
        _buildTypeSelector(c, l10n),
        const SizedBox(height: 16),
        _buildCategoryField(c, l10n),
        const SizedBox(height: 20),
        Text(l10n.priceInformationLabel,
            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _buildPricingCard(c, l10n),
        const SizedBox(height: 16),
        DropdownButtonFormField<double>(
          initialValue: _gstRate,
          dropdownColor: c.surface,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(
            labelText: l10n.gstRate,
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.inputBorder),
            ),
          ),
          items: AppConstants.gstRates.map((r) => DropdownMenuItem(value: r, child: Text('${r.toInt()}%'))).toList(),
          onChanged: (v) => setState(() => _gstRate = v ?? 5.0),
        ),
        const SizedBox(height: 20),
        _buildBarcodeSection(l10n, c),
      ],
    );
  }

  Widget _buildPricingCard(AppSemanticColors c, AppLocalizations l10n) {
    final cost = double.tryParse(_costCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final profit = price - cost;
    // Guarded against a zero selling price — otherwise this divides by zero
    // and would render NaN/Infinity while the user is still mid-typing.
    final margin = price > 0 ? (profit / price) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildField(l10n.costPriceCurrency, _costCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {})),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(l10n.sellingPriceCurrency, _priceCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v?.trim().isEmpty == true) return l10n.required;
                      if ((double.tryParse(v!) ?? 0) <= 0) return l10n.sellingPriceInvalidError;
                      return null;
                    }),
              ),
            ],
          ),
          Divider(height: 20, color: c.divider),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _calcStat(c, l10n.profit, AppFormatters.formatCurrency(profit), profit >= 0 ? c.success : c.danger),
              _calcStat(c, l10n.profitMargin, '${margin.toStringAsFixed(1)}%', margin >= 20 ? c.success : c.warning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calcStat(AppSemanticColors c, String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textHint, fontSize: 11)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
      ],
    );
  }

  // ── Step 2 — Inventory ───────────────────────────────────────────────

  Widget _buildStep2(AppSemanticColors c, AppLocalizations l10n) {
    final reorder = int.tryParse(_reorderCtrl.text) ?? 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInventoryToggle(c, l10n),
        if (_inventoryEnabled) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildField(l10n.initialStockLabel, _stockCtrl,
                    type: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n != null && n < 0) return l10n.initialStockNegativeError;
                      return null;
                    }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(l10n.reorderLevel, _reorderCtrl,
                    type: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n != null && n < 0) return l10n.reorderLevelNegativeError;
                      return null;
                    }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildLowStockHint(c, l10n, reorder),
        ] else if (_itemType == ItemType.service) ...[
          const SizedBox(height: 12),
          _buildServiceInventoryHint(c, l10n),
        ],
        const SizedBox(height: 20),
        _buildMoreOptionsSection(c, l10n),
      ],
    );
  }

  Widget _buildLowStockHint(AppSemanticColors c, AppLocalizations l10n, int reorder) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primaryLight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.lowStockAlertHint('$reorder'),
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceInventoryHint(AppSemanticColors c, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.design_services_rounded, color: c.textHint, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.serviceNoInventoryHint, style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreOptionsSection(AppSemanticColors c, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _moreOptionsExpanded = !_moreOptionsExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.moreOptionsLabel,
                        style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Icon(_moreOptionsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: c.textHint),
                ],
              ),
            ),
          ),
          if (_moreOptionsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  _buildField(l10n.skuPhoneCode, _skuCtrl),
                  _buildField(l10n.aliasesLabel, _aliasCtrl, hint: 'coke, cola, cold drink'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 3 — Review ──────────────────────────────────────────────────

  Widget _buildStep3(AppSemanticColors c, AppLocalizations l10n) {
    final cost = double.tryParse(_costCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final profit = price - cost;
    final margin = price > 0 ? (profit / price) * 100 : 0.0;
    final stock = int.tryParse(_stockCtrl.text) ?? 0;
    final reorder = int.tryParse(_reorderCtrl.text) ?? 10;
    final sku = _skuCtrl.text.trim();
    final aliases = _aliasCtrl.text.trim();
    final barcode = _barcodeCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReviewPreviewCard(c, l10n),
        const SizedBox(height: 18),
        _sectionLabel(c, l10n.pricingSummaryLabel, onEdit: () => _goToStep(0)),
        const SizedBox(height: 8),
        _buildSummaryCard(c, [
          (l10n.costPrice, AppFormatters.formatCurrency(cost), null),
          (l10n.sellingPrice, AppFormatters.formatCurrency(price), null),
          (l10n.profit, AppFormatters.formatCurrency(profit), profit >= 0 ? c.success : c.danger),
          (l10n.profitMargin, '${margin.toStringAsFixed(1)}%', margin >= 20 ? c.success : c.warning),
          (l10n.gstRate, '${_gstRate.toInt()}%', null),
        ]),
        if (_inventoryEnabled) ...[
          const SizedBox(height: 18),
          _sectionLabel(c, l10n.inventorySummaryLabel, onEdit: () => _goToStep(1)),
          const SizedBox(height: 8),
          _buildSummaryCard(c, [
            (l10n.trackInventoryLabel, l10n.yesLabel, null),
            (l10n.initialStockLabel, '$stock ${l10n.unitsLabel}', null),
            (l10n.reorderLevel, '$reorder ${l10n.unitsLabel}', null),
          ]),
        ],
        if (sku.isNotEmpty || aliases.isNotEmpty || barcode.isNotEmpty) ...[
          const SizedBox(height: 18),
          // Barcode lives on Step 1, SKU/Aliases in Step 2's More Options —
          // Step 1 is the sensible edit target either way, since Continue
          // from there reaches Step 2 with everything already filled in.
          _sectionLabel(c, l10n.additionalInfoLabel, onEdit: () => _goToStep(0)),
          const SizedBox(height: 8),
          _buildSummaryCard(c, [
            if (barcode.isNotEmpty) (l10n.barcode, barcode, null),
            if (sku.isNotEmpty) (l10n.skuPhoneCode, sku, null),
            if (aliases.isNotEmpty) (l10n.voiceAliases, aliases, null),
          ]),
        ],
      ],
    );
  }

  Widget _sectionLabel(AppSemanticColors c, String label, {VoidCallback? onEdit}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Text(context.l10n.edit,
                style: const TextStyle(color: AppColors.primaryLight, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildSummaryCard(AppSemanticColors c, List<(String, String, Color?)> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration:
                  i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: c.divider))) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(rows[i].$1, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: rows[i].$3 ?? c.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReviewPreviewCard(AppSemanticColors c, AppLocalizations l10n) {
    final hasImage = _images.isNotEmpty;
    final primaryImage = hasImage ? _images[_primaryIndex.clamp(0, _images.length - 1)] : null;

    Widget avatar;
    if (primaryImage?.imagePath != null && File(primaryImage!.imagePath!).existsSync()) {
      avatar = Image.file(File(primaryImage.imagePath!), fit: BoxFit.cover, width: 56, height: 56);
    } else if (primaryImage?.imageUrl != null) {
      avatar = Image.network(primaryImage!.imageUrl!, fit: BoxFit.cover, width: 56, height: 56);
    } else {
      final initial = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim()[0].toUpperCase() : '?';
      avatar = Container(
        width: 56,
        height: 56,
        color: c.divider,
        alignment: Alignment.center,
        child: Text(initial, style: TextStyle(color: c.textHint, fontWeight: FontWeight.bold, fontSize: 20)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: avatar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameCtrl.text.trim().isEmpty ? l10n.itemName.replaceAll(' *', '') : _nameCtrl.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _category != null ? localizedCategory(l10n, _category!) : l10n.uncategorized,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _itemType == ItemType.service ? l10n.itemTypeService : l10n.itemTypeProduct,
                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _goToStep(0),
            child: Text(l10n.edit,
                style: const TextStyle(color: AppColors.primaryLight, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Shared building blocks (unchanged from the previous single-page form) ─

  Widget _buildTypeSelector(AppSemanticColors c, AppLocalizations l10n) {
    Widget segment(ItemType type, String label, IconData icon) {
      final selected = _itemType == type;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            _itemType = type;
            // Re-guess inventory tracking from the newly picked type — the
            // right default almost always, and the user can still flip it
            // independently right below.
            _inventoryEnabled = type == ItemType.product;
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? Colors.white : c.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : c.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.itemTypeLabel,
            style: TextStyle(color: c.textHint, fontSize: 12, height: 1.2)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.inputBorder),
          ),
          child: Row(
            children: [
              segment(ItemType.product, l10n.itemTypeProduct, Icons.inventory_2_rounded),
              const SizedBox(width: 4),
              segment(ItemType.service, l10n.itemTypeService, Icons.design_services_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryToggle(AppSemanticColors c, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.inputBorder),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.trackInventoryLabel,
            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(
          _inventoryEnabled ? l10n.trackInventoryHint : l10n.trackInventoryOffHint,
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
        value: _inventoryEnabled,
        activeThumbColor: AppColors.primaryLight,
        onChanged: (v) => setState(() => _inventoryEnabled = v),
      ),
    );
  }

  Widget _buildImageGallery(AppSemanticColors c, AppLocalizations l10n) {
    const tile = 84.0;
    return SizedBox(
      height: tile + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length + 1, // +1 for the trailing Add tile
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == _images.length) {
            // Add tile
            return GestureDetector(
              onTap: _showImageOptions,
              child: Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.surfaceBorder, style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded,
                        size: 26, color: AppColors.primaryLight),
                    const SizedBox(height: 4),
                    Text(
                      _images.isEmpty ? l10n.addItemImage : l10n.addLabel,
                      style: TextStyle(color: c.textSecondary, fontSize: 10),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }

          final entry = _images[index];
          final isPrimary = index == _primaryIndex;
          final image = entry.imagePath != null && File(entry.imagePath!).existsSync()
              ? Image.file(File(entry.imagePath!), fit: BoxFit.cover, width: tile, height: tile)
              : entry.imageUrl != null
                  ? Image.network(entry.imageUrl!, fit: BoxFit.cover, width: tile, height: tile)
                  : Container(color: c.divider);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => _setPrimary(index),
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isPrimary ? AppColors.primaryLight : c.surfaceBorder,
                        width: isPrimary ? 2 : 1),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
                ),
              ),
              // Primary star — also doubles as the tap target to make a
              // non-primary image the primary one.
              Positioned(
                top: -6,
                left: -6,
                child: GestureDetector(
                  onTap: () => _setPrimary(index),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isPrimary ? AppColors.primary : c.textHint,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(Icons.star_rounded, size: 12, color: Colors.white),
                  ),
                ),
              ),
              // Remove
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removeImageAt(index),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: c.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                  ),
                ),
              ),
              // Reorder — only worth showing once there's something to
              // reorder against.
              if (_images.length > 1)
                Positioned(
                  bottom: 2,
                  left: 2,
                  right: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _reorderButton(Icons.chevron_left_rounded,
                          enabled: index > 0, onTap: () => _moveImage(index, -1)),
                      _reorderButton(Icons.chevron_right_rounded,
                          enabled: index < _images.length - 1, onTap: () => _moveImage(index, 1)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _reorderButton(IconData icon, {required bool enabled, required VoidCallback onTap}) {
    if (!enabled) return const SizedBox(width: 20, height: 20);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }

  Widget _buildCategoryField(AppSemanticColors c, AppLocalizations l10n) {
    final hasCategory = _category != null;
    final isEmpty = _categories.isEmpty && !hasCategory;

    return InkWell(
      onTap: () => showCategoryPicker(
        context: context,
        shopId: _shopId,
        selected: _category,
        onSelected: (cat) => setState(() => _category = cat),
        onCreated: (cat) => setState(
            () => _categories = ([..._categories, cat]..sort())),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.inputBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.category,
                    style: TextStyle(
                        color: c.textHint,
                        fontSize: 12,
                        height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEmpty
                        ? '${l10n.categoryNotFound}. ${l10n.createCategory}'
                        : hasCategory
                            ? _category!
                            : l10n.selectCategory,
                    style: TextStyle(
                      color: isEmpty
                          ? AppColors.primaryLight
                          : hasCategory
                              ? c.textPrimary
                              : c.textHint,
                      fontSize: 15,
                      fontWeight: isEmpty || hasCategory
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isEmpty
                  ? Icons.add_circle_outline_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: isEmpty ? AppColors.primaryLight : c.textHint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeSection(AppLocalizations l10n, AppSemanticColors c) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primaryLight),
      padding: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _barcodeCtrl,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(
            labelText: l10n.barcode,
            hintText: 'e.g. 8901234567890 or VAI000001',
            suffixIcon: _barcodeCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: c.textHint, size: 18),
                    onPressed: () => setState(() => _barcodeCtrl.clear()),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _scanBarcodeForItem,
                style: buttonStyle,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: Text(l10n.scanBarcode,
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isGeneratingBarcode ? null : _generateBarcodeForItem,
                style: buttonStyle,
                icon: _isGeneratingBarcode
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryLight),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(l10n.generateBarcode,
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        if (_barcodeCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _openBarcodePreview(_barcodeCtrl.text.trim()),
                icon: const Icon(Icons.barcode_reader, size: 16,
                    color: AppColors.primaryLight),
                label: Text(l10n.previewPrint,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.primaryLight)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
              if (_isEditing) ...[
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () => setState(() => _barcodeCtrl.clear()),
                  icon: Icon(Icons.remove_circle_outline_rounded,
                      size: 16, color: c.danger),
                  label: Text(l10n.removeBarcode,
                      style: TextStyle(fontSize: 13, color: c.danger)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
    String? hint,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        style: TextStyle(color: context.colors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}
