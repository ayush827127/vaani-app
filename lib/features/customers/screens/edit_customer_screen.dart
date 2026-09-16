import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_colors.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/customer.dart';
import '../repositories/customer_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class EditCustomerScreen extends StatefulWidget {
  final Customer customer;
  const EditCustomerScreen({super.key, required this.customer});

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.customer.name);
  late final _phoneCtrl = TextEditingController(text: widget.customer.phone ?? '');
  late final _emailCtrl = TextEditingController(text: widget.customer.email ?? '');
  late final _addressCtrl = TextEditingController(text: widget.customer.address ?? '');

  String? _imagePath;
  bool _imageRemoved = false;
  bool _isLoading = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _imagePath = widget.customer.imagePath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, 'customer_images'));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final ext = p.extension(picked.path);
      final filename = 'customer_${DateTime.now().millisecondsSinceEpoch}$ext';
      final dest = p.join(imagesDir.path, filename);
      await File(picked.path).copy(dest);

      if (mounted) {
        setState(() {
          _imagePath = dest;
          _imageRemoved = false;
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
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primaryLight),
              title: Text(l10n.takeAPhoto,
                  style: TextStyle(color: c.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_imagePath != null)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: c.danger),
                title: Text(l10n.removeImage, style: TextStyle(color: c.danger)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _imagePath = null;
                    _imageRemoved = true;
                  });
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

    final repo = getIt<CustomerRepository>();
    final phone = _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();

    // Same duplicate-phone guard as adding a new customer — without it two
    // customer records could end up sharing a number with nothing to catch it.
    if (phone != null) {
      final dup = await repo.getCustomerByPhone(widget.customer.shopId, phone);
      if (dup != null && dup.id != widget.customer.id) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${dup.name} already has this phone number'),
          backgroundColor: context.colors.danger,
        ));
        return;
      }
    }

    final resolvedImagePath = _imageRemoved ? null : _imagePath;

    final updated = Customer(
      id: widget.customer.id,
      shopId: widget.customer.shopId,
      name: _nameCtrl.text.trim(),
      phone: phone,
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      totalPurchases: widget.customer.totalPurchases,
      totalBills: widget.customer.totalBills,
      totalOutstanding: widget.customer.totalOutstanding,
      advanceBalance: widget.customer.advanceBalance,
      lastVisit: widget.customer.lastVisit,
      imagePath: resolvedImagePath,
      createdAt: widget.customer.createdAt,
      updatedAt: DateTime.now(),
    );

    try {
      await repo.updateCustomer(updated);
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
    context.pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.customerUpdated), backgroundColor: successColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editCustomer),
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
            Center(
              child: GestureDetector(
                onTap: _showImageOptions,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: c.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _imagePath != null
                              ? AppColors.primaryLight
                              : c.surfaceBorder,
                          width: _imagePath != null ? 2 : 1,
                        ),
                      ),
                      child: _imagePath != null
                          ? ClipOval(
                              child: Image.file(
                                File(_imagePath!),
                                fit: BoxFit.cover,
                                width: 96,
                                height: 96,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.broken_image_rounded,
                                    size: 36,
                                    color: c.textHint),
                              ),
                            )
                          : const Icon(
                              Icons.add_a_photo_rounded,
                              size: 36,
                              color: AppColors.primaryLight,
                            ),
                    ),
                    Positioned(
                      bottom: -6,
                      right: -6,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _imagePath != null ? l10n.tapToChangeImage : l10n.addCustomerImage,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _nameCtrl,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.nameRequired),
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.nameRequired : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.phone),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.email),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(labelText: l10n.address),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(l10n.save, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
