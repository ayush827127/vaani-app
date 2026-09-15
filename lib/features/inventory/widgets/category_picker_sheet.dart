import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/injector.dart';
import '../repositories/category_repository.dart';
import '../../../l10n/l10n_extensions.dart';

/// Shows a modal bottom sheet for picking or creating a category.
///
/// [shopId] — the shop to scope categories to.
/// [selected] — currently selected category (may be null).
/// [onSelected] — called with the chosen category name.
/// [onCreated] — called after a new category is created (with its name),
///               so the caller can update its local list without a full reload.
Future<void> showCategoryPicker({
  required BuildContext context,
  required int shopId,
  required String? selected,
  required ValueChanged<String> onSelected,
  ValueChanged<String>? onCreated,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryPickerSheet(
      shopId: shopId,
      selected: selected,
      onSelected: onSelected,
      onCreated: onCreated,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  final int shopId;
  final String? selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onCreated;

  const _CategoryPickerSheet({
    required this.shopId,
    required this.selected,
    required this.onSelected,
    this.onCreated,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  List<String> _categories = [];
  bool _loading = true;
  bool _showCreate = false;
  final _newCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await getIt<CategoryRepository>().getCategories(widget.shopId);
    if (!mounted) return;
    setState(() {
      _categories = list;
      _loading = false;
    });
  }

  Future<void> _createCategory() async {
    final name = _newCtrl.text.trim();
    if (name.isEmpty) return;
    await getIt<CategoryRepository>().addCategory(widget.shopId, name);
    widget.onCreated?.call(name);
    widget.onSelected(name);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final pad = MediaQuery.of(context).padding.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1B3A) : AppColors.scaffoldLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, pad > 0 ? pad + 8 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.category,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    CircularProgressIndicator(color: AppColors.primaryLight),
              ))
            else ...[
              // Empty state
              if (_categories.isEmpty && !_showCreate)
                _buildEmptyState(c, l10n)
              // Category list
              else if (!_showCreate) ...[
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _categories.length,
                    itemBuilder: (_, i) {
                      final cat = _categories[i];
                      final isSelected = cat == widget.selected;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected
                              ? AppColors.primaryLight
                              : c.textHint,
                          size: 20,
                        ),
                        title: Text(
                          cat,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primaryLight
                                : c.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                        onTap: () {
                          widget.onSelected(cat);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 16),
              ],

              // Create category form
              if (_showCreate) ...[
                TextField(
                  controller: _newCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  style: TextStyle(color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: l10n.categoryNameHint,
                    hintStyle: TextStyle(color: c.textHint),
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primaryLight, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  onSubmitted: (_) => _createCategory(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            setState(() => _showCreate = false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.surfaceBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(l10n.cancel,
                            style:
                                TextStyle(color: c.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _createCategory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          l10n.createCategory,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // "Create category" action row
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: AppColors.primaryLight, size: 18),
                  ),
                  title: Text(
                    l10n.createCategory,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () => setState(() => _showCreate = true),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(dynamic c, dynamic l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.label_outline_rounded,
                  size: 30, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.categoryNotFound,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.noCategoriesYet,
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showCreate = true),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.createCategory),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
