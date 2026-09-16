import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../repositories/shop_repository.dart';
import '../services/otp_service.dart';
import '../../subscription/services/subscription_api_client.dart';
import '../../../l10n/l10n_extensions.dart';

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _otpSent = false;
  bool _isSending = false;
  bool _isVerifying = false;
  int _resendTimer = 0;

  String get _newPhone => _phoneCtrl.text.trim();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    try {
      await OtpService.instance.sendOtp(_newPhone);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _otpSent = true;
      _resendTimer = 60;
    });
    _startResendTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.otpSentToNumber(_newPhone)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startResendTimer() async {
    while (_resendTimer > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendTimer--);
    }
  }

  Future<void> _verifyAndUpdate() async {
    final l10n = context.l10n;
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enter6DigitOtp)),
      );
      return;
    }

    setState(() => _isVerifying = true);

    String? otpToken;
    try {
      otpToken = await OtpService.instance.verifyOtp(_newPhone, otp);
    } catch (e) {
      // Network failure (offline, timeout, server waking up) — not the same
      // as a wrong code, and previously left this screen stuck spinning
      // forever with no way to recover short of navigating away (login_screen
      // handles this same call with a try/catch; this one didn't).
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorGeneric('$e')), backgroundColor: AppColors.error),
      );
      return;
    }
    if (otpToken == null) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.incorrectOtp),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final shopId = prefs.getInt(AppConstants.keyShopId);
      if (shopId == null) throw Exception('Shop not found');

      // Update the backend first (and get a fresh token — the old one
      // embeds the old phone) — previously only the local row was updated,
      // so a re-login with the new number couldn't find this shop on the
      // backend and would be treated as a brand-new signup, orphaning the
      // cloud data.
      final currentToken = prefs.getString(AppConstants.keyShopBackendToken);
      if (currentToken != null) {
        final result = await getIt<SubscriptionApiClient>()
            .changePhone(currentToken, _newPhone, otpToken);
        await prefs.setString(AppConstants.keyShopBackendToken, result.token);
      }

      await getIt<ShopRepository>().updatePhone(shopId, _newPhone);
      await prefs.setString(AppConstants.keyShopPhone, _newPhone);

      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.mobileUpdatedSuccess),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } on PhoneAlreadyRegisteredException catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorGeneric('$e')), backgroundColor: AppColors.error),
      );
    }
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
        title: Text(
          l10n.changeMobileNumber,
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator
            _StepRow(step: _otpSent ? 2 : 1),
            const SizedBox(height: 32),

            if (!_otpSent) ...[
              Text(
                l10n.enterNewMobileNumber,
                style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.otpVerificationHint,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Form(
                key: _phoneFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newMobileNumber,
                      style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: c.surfaceBorder)),
                            ),
                            child: Text(
                              '+91',
                              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: 10,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: TextStyle(color: c.textPrimary, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: l10n.enter10DigitNumber,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(l10n.sendOtp, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                l10n.verifyNewNumber,
                style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.otpSentTo(_newPhone),
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 28),
              Text(
                l10n.enterOtp,
                style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(6, (i) {
                  return Expanded(
                    child: Container(
                      height: 64,
                      margin: EdgeInsets.only(
                        left: i == 0 ? 0 : 5,
                        right: i == 5 ? 0 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.surfaceBorder, width: 1.5),
                      ),
                      child: TextField(
                        controller: _otpControllers[i],
                        focusNode: _otpFocusNodes[i],
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                          height: 1,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 20),
                        ),
                        onChanged: (v) {
                          if (v.isNotEmpty && i < 5) {
                            _otpFocusNodes[i + 1].requestFocus();
                          } else if (v.isEmpty && i > 0) {
                            _otpFocusNodes[i - 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false;
                      _resendTimer = 0;
                      for (final c in _otpControllers) {
                        c.clear();
                      }
                    }),
                    child: Text(l10n.changeNumber, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  ),
                  _resendTimer > 0
                      ? Text(
                          l10n.resendIn('$_resendTimer'),
                          style: TextStyle(color: c.textHint, fontSize: 13),
                        )
                      : TextButton(
                          onPressed: _sendOtp,
                          child: Text(l10n.resendOtp, style: const TextStyle(color: AppColors.primaryLight, fontSize: 13)),
                        ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyAndUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(l10n.verifyUpdate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        _StepDot(index: 1, active: step >= 1, done: step > 1, label: l10n.stepNewNumber),
        Expanded(
          child: Container(
            height: 2,
            color: step > 1 ? AppColors.primaryLight : context.colors.surfaceBorder,
          ),
        ),
        _StepDot(index: 2, active: step >= 2, done: false, label: l10n.stepVerifyOtp),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final bool active;
  final bool done;
  final String label;

  const _StepDot({required this.index, required this.active, required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = active ? AppColors.primaryLight : c.surfaceBorder;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    '$index',
                    style: TextStyle(color: active ? Colors.white : c.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: active ? c.textSecondary : c.textDisabled, fontSize: 11)),
      ],
    );
  }
}
