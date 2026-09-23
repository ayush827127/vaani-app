import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item image gallery — no image is valid, one is valid, several
            // are valid. The starred badge marks the primary (used anywhere
            // a single image is needed: item list/detail, invoice PDFs).
            _buildImageGallery(c, l10n),
            const SizedBox(height: 20),
            _buildField(l10n.itemName, _nameCtrl,
                validator: (v) => v?.trim().isEmpty == true ? l10n.required : null),
            _buildField(l10n.skuPhoneCode, _skuCtrl),
            const SizedBox(height: 4),
            _buildTypeSelector(c, l10n),
            const SizedBox(height: 16),
            _buildInventoryToggle(c, l10n),
            const SizedBox(height: 16),
            // Category — tappable picker
            _buildCategoryField(c, l10n),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _buildField(l10n.costPriceCurrency, _costCtrl,
                        type: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField(l10n.sellingPriceCurrency, _priceCtrl,
                      type: TextInputType.number,
                      validator: (v) {
                        if (v?.trim().isEmpty == true) return l10n.required;
                        if ((double.tryParse(v!) ?? 0) <= 0) return l10n.mustBeGreaterThanZero;
                        return null;
                      }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // GST Rate
            DropdownButtonFormField<double>(
              initialValue: _gstRate,
              dropdownColor: c.surface,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.gstRate,
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.inputBorder),
                ),
              ),
              items: AppConstants.gstRates
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text('${r.toInt()}%')))
                  .toList(),
              onChanged: (v) => setState(() => _gstRate = v ?? 5.0),
            ),
            if (_inventoryEnabled) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _buildField(l10n.stockQuantity, _stockCtrl,
                          type: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _buildField(l10n.reorderLevel, _reorderCtrl,
                          type: TextInputType.number)),
                ],
              ),
            ],
            _buildField(
              l10n.aliasesLabel,
              _aliasCtrl,
              hint: 'coke, cola, cold drink',
            ),
            // ── Barcode section ───────────────────────────────────────────
            _buildBarcodeSection(l10n, c),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_isEditing ? l10n.updateItem : l10n.saveItem),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

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
      ),
    );
  }
}
