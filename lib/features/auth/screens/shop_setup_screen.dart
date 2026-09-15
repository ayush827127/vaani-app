import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/shop.dart';
import '../repositories/shop_repository.dart';
import '../../subscription/repositories/subscription_repository.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class ShopSetupScreen extends StatefulWidget {
  const ShopSetupScreen({super.key});

  @override
  State<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends State<ShopSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(AppConstants.keyShopPhone) ?? '9999999999';

    final shop = Shop(
      name: _shopNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: phone,
      gstNumber: _gstCtrl.text.trim().isEmpty ? null : _gstCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final repo = getIt<ShopRepository>();
    final shopId = await repo.createShop(shop);
    await prefs.setBool(AppConstants.keyIsSetupComplete, true);
    await prefs.setInt(AppConstants.keyShopId, shopId);

    // Link with the admin backend, then sync — in that order, and awaited.
    // These used to fire in parallel (unawaited), so the very first sync
    // almost always ran before registration produced a shop token and
    // silently no-op'd, leaving the shop looking "Never synced" until the
    // next scheduled sync. Uses the OTP proof stashed by login_screen right
    // after verification.
    final otpToken = prefs.getString(AppConstants.keyPendingOtpToken);
    await prefs.remove(AppConstants.keyPendingOtpToken);
    await getIt<SubscriptionRepository>().refreshStatus(otpToken: otpToken);
    final syncResult = await getIt<DataSyncRepository>().syncNow();

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!syncResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Shop saved — couldn't reach the server yet, will sync automatically."),
        ),
      );
    }
    context.go('/home');
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _gstCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  l10n.setupYourShop,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  l10n.enterShopDetailsHint,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 32),
                // Shop logo placeholder
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariantDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryLight, width: 2),
                    ),
                    child: const Icon(Icons.add_a_photo_rounded, size: 36, color: AppColors.primaryLight),
                  ),
                ),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildField(
                        controller: _shopNameCtrl,
                        label: l10n.shopNameRequired,
                        hint: 'Gupta General Store',
                        validator: (v) => (v == null || v.trim().length < 2) ? l10n.shopNameHint : null,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _ownerNameCtrl,
                        label: l10n.ownerNameRequired,
                        hint: 'Ayush Gupta',
                        validator: (v) => (v == null || v.trim().isEmpty) ? l10n.ownerNameHint : null,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _gstCtrl,
                        label: l10n.gstNumberOptionalCaps,
                        hint: '07ABCDE1234F1Z1',
                        maxLength: 15,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _addressCtrl,
                        label: l10n.addressOptionalCaps,
                        hint: '123, Market Road, Delhi',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _save,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(l10n.saveContinue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            counterText: '',
            counterStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AppColors.surfaceVariantDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3D3B6E)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
