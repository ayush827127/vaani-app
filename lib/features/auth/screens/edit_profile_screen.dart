import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/shop.dart';
import '../../../shared/widgets/shop_logo_image.dart';
import '../repositories/shop_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _upiIdCtrl = TextEditingController();

  bool _gstEnabled = true;
  double _defaultGstRate = 5.0;
  Shop? _shop;
  bool _loading = true;
  bool _saving = false;
  String? _logoPath;
  bool _logoRemoved = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    setState(() {
      _shop = shop;
      _loading = false;
      if (shop != null) {
        _shopNameCtrl.text = shop.name;
        _ownerNameCtrl.text = shop.ownerName;
        _gstCtrl.text = shop.gstNumber ?? '';
        _addressCtrl.text = shop.address ?? '';
        _upiIdCtrl.text = shop.upiId ?? '';
        _gstEnabled = shop.gstEnabled;
        _defaultGstRate = shop.defaultGstRate;
        _logoPath = shop.logoPath;
      }
    });
  }

  Future<void> _pickLogo(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(dir.path, 'shop_images'));
      if (!await imgDir.exists()) await imgDir.create(recursive: true);
      final ext = p.extension(picked.path);
      final dest = p.join(imgDir.path, 'logo_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(picked.path).copy(dest);
      if (mounted) setState(() { _logoPath = dest; _logoRemoved = false; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotPickImage('$e')), backgroundColor: context.colors.danger));
    }
  }

  void _showLogoOptions() {
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
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: c.surfaceBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primaryLight),
              title: Text(l10n.chooseFromGallery, style: TextStyle(color: c.textPrimary)),
              onTap: () { Navigator.pop(context); _pickLogo(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primaryLight),
              title: Text(l10n.takeAPhoto, style: TextStyle(color: c.textPrimary)),
              onTap: () { Navigator.pop(context); _pickLogo(ImageSource.camera); },
            ),
            if (_logoPath != null)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: c.danger),
                title: Text(l10n.removeImage, style: TextStyle(color: c.danger)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() { _logoPath = null; _logoRemoved = true; });
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
    if (_shop == null) return;
    setState(() => _saving = true);

    final updated = Shop(
      id: _shop!.id,
      name: _shopNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: _shop!.phone,
      gstNumber: _gstCtrl.text.trim().isEmpty ? null : _gstCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      upiId: _upiIdCtrl.text.trim().isEmpty ? null : _upiIdCtrl.text.trim(),
      logoPath: _logoRemoved ? null : _logoPath,
      currency: _shop!.currency,
      gstEnabled: _gstEnabled,
      defaultGstRate: _defaultGstRate,
      createdAt: _shop!.createdAt,
      updatedAt: DateTime.now(),
    );

    try {
      await getIt<ShopRepository>().updateShop(updated);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.profileUpdatedSuccess),
          backgroundColor: context.colors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.failedToSave('$e')), backgroundColor: context.colors.danger),
      );
    }
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _gstCtrl.dispose();
    _addressCtrl.dispose();
    _upiIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.editProfile, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: AppColors.primaryLight, strokeWidth: 2),
                      )
                    : Text(l10n.save, style: const TextStyle(color: AppColors.primaryLight, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop logo picker
                    Center(
                      child: GestureDetector(
                        onTap: _showLogoOptions,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Builder(builder: (context) {
                              // Falls back to the Cloudinary URL synced from
                              // the cloud when there's no local file — e.g.
                              // right after a reinstall, before the owner
                              // has picked a new logo on this device.
                              final logo = _logoRemoved
                                  ? null
                                  : resolveShopLogoImage(
                                      logoPath: _logoPath,
                                      logoUrl: _shop?.logoUrl,
                                      size: 88,
                                      errorBuilder: (_, __, ___) => _logoInitial(),
                                    );
                              return Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  gradient: logo != null ? null : c.heroGradient,
                                  color: logo != null ? Colors.transparent : null,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primaryLight, width: 2),
                                ),
                                child: ClipOval(child: logo ?? _logoInitial()),
                              );
                            }),
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(l10n.tapToChangeLogo,
                          style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 11)),
                    ),
                    const SizedBox(height: 22),

                    _sectionLabel(l10n.shopInformation),
                    _buildField(
                      controller: _shopNameCtrl,
                      label: l10n.shopName,
                      hint: 'Gupta General Store',
                      icon: Icons.store_rounded,
                      validator: (v) => (v == null || v.trim().length < 2) ? l10n.shopNameHint : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _ownerNameCtrl,
                      label: l10n.ownerName,
                      hint: 'Ayush Gupta',
                      icon: Icons.person_rounded,
                      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.ownerNameHint : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _addressCtrl,
                      label: l10n.addressOptionalLabel,
                      hint: '123, Market Road, Delhi',
                      icon: Icons.location_on_rounded,
                      maxLines: 2,
                    ),

                    const SizedBox(height: 24),
                    _sectionLabel(l10n.taxSettings),

                    // GST toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.surfaceBorder),
                      ),
                      child: SwitchListTile(
                        value: _gstEnabled,
                        onChanged: (v) => setState(() => _gstEnabled = v),
                        title: Text(l10n.gstEnabled, style: TextStyle(color: c.textPrimary, fontSize: 15)),
                        subtitle: Text(l10n.applyGstHint, style: TextStyle(color: c.textHint, fontSize: 12)),
                        activeThumbColor: AppColors.primaryLight,
                        activeTrackColor: AppColors.primaryLight.withValues(alpha: 0.4),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),

                    if (_gstEnabled) ...[
                      const SizedBox(height: 14),
                      Text(l10n.defaultGstRate, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: AppConstants.gstRates.map((rate) {
                          final selected = _defaultGstRate == rate;
                          return ChoiceChip(
                            label: Text('${rate.toStringAsFixed(0)}%'),
                            selected: selected,
                            onSelected: (_) => setState(() => _defaultGstRate = rate),
                            selectedColor: AppColors.primaryLight,
                            backgroundColor: c.surface,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : c.textSecondary,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            side: BorderSide(color: selected ? AppColors.primaryLight : c.surfaceBorder),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),
                    _sectionLabel(l10n.legal),
                    _buildField(
                      controller: _gstCtrl,
                      label: l10n.gstNumberOptional,
                      hint: '07ABCDE1234F1Z1',
                      icon: Icons.receipt_long_rounded,
                      maxLength: 15,
                      textCapitalization: TextCapitalization.characters,
                    ),

                    const SizedBox(height: 24),
                    _sectionLabel(l10n.paymentQr),
                    _buildField(
                      controller: _upiIdCtrl,
                      label: l10n.upiIdOptional,
                      hint: 'yourname@upi',
                      icon: Icons.qr_code_rounded,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.upiIdHint,
                      style: TextStyle(color: c.textHint, fontSize: 11, height: 1.5),
                    ),

                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(l10n.saveChanges, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _logoInitial() => Center(
        child: Text(
          _shop!.name.isNotEmpty ? _shop!.name[0].toUpperCase() : 'S',
          style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryLight),
        ),
      );

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.surfaceBorder),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(icon, color: AppColors.primaryLight, size: 20),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  textCapitalization: textCapitalization,
                  style: TextStyle(color: c.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: c.textDisabled),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
                  ),
                  validator: validator,
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ],
    );
  }
}
