import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/network_error.dart';
import '../../../core/services/backend_warmup.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/shop.dart';
import '../repositories/shop_repository.dart';
import '../services/otp_service.dart';
import '../../demo/demo_data_seeder.dart';
import '../../subscription/repositories/subscription_repository.dart';
import '../../sync/repositories/data_sync_repository.dart';
import '../../../l10n/l10n_extensions.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _otpSent = false;
  bool _isLoading = false;
  bool _isSendingOtp = false;
  int _resendTimer = 0;

  // Guards against the recursive onChanged calls that firing programmatic
  // text updates (autofill/paste distribution below) triggers on each of
  // the 6 controllers.
  bool _distributingOtp = false;

  @override
  void initState() {
    super.initState();
    // Give the backend a head start waking up (Render free tier sleeps
    // after ~15 min idle) — by the time the user finishes typing their
    // phone number and taps Send OTP, it's more likely already awake.
    warmUpBackend();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSendingOtp = true);
    final phone = _phoneController.text.trim();
    try {
      await OtpService.instance.sendOtp(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      _showNetworkError(e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      _otpSent = true;
      _resendTimer = 60;
    });
    _startResendTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.otpSentToNumber(phone)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Handles both normal single-digit typing AND a full code landing in one
  /// shot — which is how both SMS autofill and a manual paste deliver it:
  /// Android fills whichever field is focused with the entire code, not one
  /// digit per box, and framework maxLength enforcement would otherwise
  /// truncate that unless every box accepts more than 1 character (see the
  /// `maxLength: 6` on each field below).
  void _handleOtpChanged(int index, String value) {
    if (_distributingOtp) return;

    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      _distributingOtp = true;
      for (var i = 0; i < _otpControllers.length; i++) {
        _otpControllers[i].text = i < digits.length ? digits[i] : '';
      }
      _distributingOtp = false;
      if (digits.length >= 6) {
        _otpFocusNodes[5].unfocus();
      } else if (digits.isNotEmpty) {
        _otpFocusNodes[digits.length.clamp(0, 5)].requestFocus();
      }
      TextInput.finishAutofillContext();
      _autoSubmitIfComplete();
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    _autoSubmitIfComplete();
  }

  /// Shows the friendly message plus the raw exception type/text in smaller
  /// print underneath — temporary extra visibility while tracking down a
  /// real connectivity failure that isn't just the backend's free-tier host
  /// waking up (see [technicalErrorDetail]).
  void _showNetworkError(Object e, {String Function(String)? wrap}) {
    final friendly = wrap != null ? wrap(friendlyNetworkError(e)) : friendlyNetworkError(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(friendly),
            const SizedBox(height: 4),
            Text(
              technicalErrorDetail(e),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _autoSubmitIfComplete() {
    if (_isLoading || _isSendingOtp) return;
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length == 6) _verifyOtp();
  }

  void _startResendTimer() async {
    while (_resendTimer > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendTimer--);
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enter6DigitOtp)),
      );
      return;
    }

    final phone = _phoneController.text.trim();
    setState(() => _isLoading = true);

    String? otpToken;
    try {
      otpToken = await OtpService.instance.verifyOtp(phone, otp);
    } catch (e) {
      // Network failure (offline, timeout, server waking up) — NOT the same
      // as a wrong code, so it must not show "Incorrect OTP".
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showNetworkError(e);
      return;
    }
    if (otpToken == null) {
      if (!mounted) return;
      _distributingOtp = true;
      for (final c in _otpControllers) {
        c.clear();
      }
      _distributingOtp = false;
      _otpFocusNodes[0].requestFocus();
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.incorrectOtp),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final repo = getIt<ShopRepository>();
      final shop = await repo.getShopByPhone(phone);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);
      await prefs.setString(AppConstants.keyShopPhone, phone);

      if (shop != null) {
        // Local DB already has this shop (same device, already set up).
        await prefs.setBool(AppConstants.keyIsSetupComplete, true);
        await prefs.setInt(AppConstants.keyShopId, shop.id!);
        if (!mounted) return;
        setState(() => _isLoading = false);
        unawaited(getIt<SubscriptionRepository>().refreshStatus(otpToken: otpToken));
        unawaited(getIt<DataSyncRepository>().syncNow());
        if (!mounted) return;
        context.go('/home');
        return;
      }

      // No local record for this phone — could be a genuinely new user, or
      // a returning user on a fresh install/reinstall/new device whose shop
      // only lives in the cloud. Ask the backend before assuming "new" and
      // sending them to Setup, so a returning user never ends up with a
      // second, empty shop shadowing their real data.
      final cloudShop = await getIt<SubscriptionRepository>()
          .checkExistingCloudShop(phone, otpToken);

      if (cloudShop != null) {
        final shopMap = cloudShop.shop;
        final now = DateTime.now();
        final newShop = Shop(
          name: shopMap['name'] as String,
          ownerName: shopMap['ownerName'] as String,
          phone: phone,
          gstNumber: shopMap['gstNumber'] as String?,
          address: shopMap['address'] as String?,
          upiId: shopMap['upiId'] as String?,
          currency: shopMap['currency'] as String? ?? 'INR',
          gstEnabled: shopMap['gstEnabled'] as bool? ?? true,
          defaultGstRate: (shopMap['defaultGstRate'] as num?)?.toDouble() ?? 5.0,
          createdAt: now,
          updatedAt: now,
        );
        final shopId = await repo.createShop(newShop);
        await prefs.setBool(AppConstants.keyIsSetupComplete, true);
        await prefs.setInt(AppConstants.keyShopId, shopId);

        // Await (don't fire-and-forget) this first sync — it's what actually
        // pulls the shop's products/customers/invoices down onto this
        // device, so the user shouldn't land on an empty dashboard while it
        // happens invisibly in the background.
        final syncResult = await getIt<DataSyncRepository>().syncNow();
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (!syncResult.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Signed in — couldn't reach the server to pull your shop data yet, will retry automatically.",
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        context.go('/home');
      } else {
        // Backend confirmed: no shop exists for this phone anywhere.
        await prefs.setString(AppConstants.keyPendingOtpToken, otpToken);
        if (!mounted) return;
        setState(() => _isLoading = false);
        context.go('/setup');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showNetworkError(e, wrap: l10n.loginError);
    }
  }

  Future<void> _useDemoMode() async {
    final l10n = context.l10n;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2B5E),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF7C3AED)),
            const SizedBox(height: 20),
            Text(
              l10n.settingUpDemoStore,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
    try {
      await DemoDataSeeder.seed();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);
      await prefs.setBool(AppConstants.keyIsSetupComplete, true);
      await prefs.setBool(AppConstants.keyIsDemoMode, true);
      await prefs.setInt(AppConstants.keyShopId, 1);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.demoSetupFailed('$e')), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_rounded, size: 52, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.welcomeBack,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _otpSent ? l10n.enterOtpSentHint : l10n.signInHint,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.mobileNumber,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariantDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3D3B6E)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                              decoration: const BoxDecoration(
                                border: Border(right: BorderSide(color: Color(0xFF3D3B6E))),
                              ),
                              child: const Text(
                                '+91',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                enabled: !_otpSent,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  color: _otpSent ? Colors.white54 : Colors.white,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.enter10DigitNumber,
                                  hintStyle: const TextStyle(color: Colors.white38),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return l10n.enterMobileNumberValidator;
                                  if (v.length != 10) return l10n.enter10DigitNumber;
                                  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v)) {
                                    return l10n.enterValidIndianMobile;
                                  }
                                  return null;
                                },
                              ),
                            ),
                            if (_otpSent)
                              TextButton(
                                onPressed: () => setState(() {
                                  _otpSent = false;
                                  _resendTimer = 0;
                                  for (final c in _otpControllers) {
                                    c.clear();
                                  }
                                }),
                                child: Text(
                                  l10n.change,
                                  style: const TextStyle(color: AppColors.primaryLight, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // OTP fields
                      if (_otpSent) ...[
                        const SizedBox(height: 28),
                        Text(
                          l10n.enterOtp,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        AutofillGroup(
                          child: Row(
                            children: List.generate(6, (i) {
                              return Expanded(
                                child: Container(
                                  height: 64,
                                  margin: EdgeInsets.only(
                                    left: i == 0 ? 0 : 5,
                                    right: i == 5 ? 0 : 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariantDark,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF4D4B82), width: 1.5),
                                  ),
                                  child: TextField(
                                    controller: _otpControllers[i],
                                    focusNode: _otpFocusNodes[i],
                                    textAlign: TextAlign.center,
                                    // Not 1 — whichever box is focused when
                                    // SMS autofill (or a manual paste) fires
                                    // receives the FULL 6-digit code at
                                    // once, not a digit at a time. A
                                    // maxLength of 1 would silently truncate
                                    // that before onChanged ever saw it.
                                    maxLength: 6,
                                    keyboardType: TextInputType.number,
                                    autofillHints: const [AutofillHints.oneTimeCode],
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1,
                                    ),
                                    decoration: const InputDecoration(
                                      counterText: '',
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 20),
                                    ),
                                    onChanged: (v) => _handleOtpChanged(i, v),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _resendTimer > 0
                              ? Text(
                                  l10n.resendOtpIn('$_resendTimer'),
                                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                                )
                              : TextButton(
                                  onPressed: _sendOtp,
                                  child: Text(
                                    l10n.resendOtp,
                                    style: const TextStyle(color: AppColors.primaryLight, fontSize: 13),
                                  ),
                                ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isSendingOtp) ? null : (_otpSent ? _verifyOtp : _sendOtp),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            disabledBackgroundColor: AppColors.primaryLight.withValues(alpha: 0.5),
                          ),
                          child: (_isLoading || _isSendingOtp)
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(
                                  _otpSent ? l10n.verifyLogin : l10n.sendOtp,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),

                      if (_isLoading || _isSendingOtp) ...[
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: double.infinity,
                          child: Text(
                            "Connecting… this can take up to a minute if the server was asleep.",
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFF3D3B6E))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.or, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                          ),
                          const Expanded(child: Divider(color: Color(0xFF3D3B6E))),
                        ],
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: (_isLoading || _isSendingOtp) ? null : _useDemoMode,
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                          label: Text(
                            l10n.exploreDemoStore,
                            style: const TextStyle(fontSize: 15),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurfaceVariantDark,
                            side: const BorderSide(color: Color(0xFF3D3B6E)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  l10n.termsPrivacyNotice,
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
