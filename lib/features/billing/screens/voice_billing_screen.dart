import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/permission_service.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/product.dart';
import '../../inventory/repositories/product_repository.dart';
import '../services/voice_action_parser.dart';
import '../services/action_executor.dart';
import 'billing_screen.dart';
import '../../../l10n/l10n_extensions.dart';

class VoiceBillingScreen extends ConsumerStatefulWidget {
  const VoiceBillingScreen({super.key});

  @override
  ConsumerState<VoiceBillingScreen> createState() => _VoiceBillingScreenState();
}

class _VoiceBillingScreenState extends ConsumerState<VoiceBillingScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  String _recognizedText = '';
  int _shopId = 1;
  List<Product> _allProducts = [];
  VoiceActionParser? _voiceParser;
  List<VoiceAction> _parsedActions = [];
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.2)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1);

    // Initialize the voice parser once (proxied through our backend).
    final backendBaseUrl = dotenv.env['BACKEND_API_BASE_URL'] ?? '';
    final shopToken = prefs.getString(AppConstants.keyShopBackendToken);
    if (backendBaseUrl.isNotEmpty && shopToken != null && shopToken.isNotEmpty) {
      _voiceParser = VoiceActionParser(backendBaseUrl, shopToken);
    }

    // Load the full product catalog for the parser to match against
    final products = await getIt<ProductRepository>().getAllProducts(_shopId);
    if (mounted) setState(() => _allProducts = products);

    final granted = await PermissionService.requestMicrophone(context);
    if (!granted || !mounted) {
      setState(() => _speechAvailable = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
          if (_recognizedText.isNotEmpty) _parseVoiceInput(_recognizedText);
        }
      },
    );
    setState(() => _speechAvailable = available);
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() {
        _isListening = true;
        _recognizedText = '';
        _parsedActions = [];
      });
      await _speech.listen(
        onResult: (r) => setState(() => _recognizedText = r.recognizedWords),
        listenOptions: SpeechListenOptions(partialResults: true, localeId: 'hi_IN'),
      );
    }
  }

  Future<void> _parseVoiceInput(String input) async {
    if (_voiceParser == null || _allProducts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_voiceParser == null
              ? 'Voice billing needs an internet connection to set up.'
              : 'Product catalog is empty. Add products first.'),
          backgroundColor: context.colors.danger,
        ));
      }
      return;
    }

    final ctx = BillingContext(
      products: _allProducts,
      customers: const [],
      cartItems: ref.read(cartProvider),
      paymentMode: 'upi',
      discountType: 'none',
      discountValue: 0,
    );

    VoiceParseResult result;
    try {
      result = await _voiceParser!.parse(input, ctx);
    } catch (e, st) {
      debugPrint('[VoiceScreen] parse() threw: $e\n$st');
      result = VoiceParseResult(
        actions: [],
        failureReason: '[unexpected] ${e.runtimeType}: $e',
      );
    }

    if (!mounted) return;

    if (!result.succeeded) {
      final reason = result.failureReason ?? '[no-actions] No actions.';
      debugPrint('[VoiceScreen] parse failed: $reason');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(reason.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')),
        backgroundColor: context.colors.danger,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    setState(() => _parsedActions = result.actions);
  }

  void _applyActions() {
    final productsById = {
      for (final p in _allProducts) if (p.id != null) p.id!: p
    };
    final executor = ActionExecutor(ref: ref, productsById: productsById);
    final execResult = executor.execute(_parsedActions);

    final cartActions = execResult.messages.length;
    final successColor = context.colors.success;
    context.pop();

    if (cartActions > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(execResult.messages.join(' · ')),
        backgroundColor: successColor,
        duration: const Duration(seconds: 3),
      ));
    }
    if (execResult.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(execResult.errors.join(', ')),
        backgroundColor: context.colors.danger,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.voiceBillingTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mic button
                GestureDetector(
                  onTap: _speechAvailable ? _toggleListening : null,
                  child: AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Transform.scale(
                      scale: _isListening ? _pulseAnim.value : 1.0,
                      child: child,
                    ),
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isListening
                              ? [AppColors.error, const Color(0xFF991B1B)]
                              : [AppColors.primaryLight, AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? AppColors.error : AppColors.primary)
                                .withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isListening
                      ? l10n.listeningEllipsis
                      : (_speechAvailable ? l10n.tapToSpeak : l10n.micUnavailable),
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary),
                ),
                const SizedBox(height: 32),
                // Suggestion chips
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    '"do Coke, teen Maggi"',
                    '"char Parle G"',
                    '"2 aata, ek namak"',
                  ]
                      .map((s) => Chip(
                            label: Text(s,
                                style: TextStyle(fontSize: 12, color: c.textSecondary)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                if (_recognizedText.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        Text(l10n.recognizedText,
                            style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        const SizedBox(height: 8),
                        Text(
                          _recognizedText,
                          style: TextStyle(
                              fontSize: 16,
                              color: c.textPrimary,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Results panel
          if (_parsedActions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: c.surfaceBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_parsedActions.where((a) => a is! UnknownProductAction && a is! UnknownAction).length} action(s) ready',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ..._parsedActions.map(
                    (action) {
                      final isError = action is UnknownProductAction ||
                          action is UnknownAction;
                      final label = switch (action) {
                        SetQuantityAction() =>
                          '${action.productName} × ${action.quantity}',
                        IncreaseQuantityAction() =>
                          '+${action.delta} ${action.productName}',
                        DecreaseQuantityAction() =>
                          '−${action.delta} ${action.productName}',
                        RemoveItemAction() => 'Remove ${action.productName}',
                        ClearCartAction() => 'Clear cart',
                        UpdatePriceAction() =>
                          '${action.productName} → ₹${action.price.toStringAsFixed(0)}',
                        DiscountAction() =>
                          'Discount: ${action.discountType == "percent" ? "${action.value}%" : "₹${action.value}"}',
                        PaymentModeAction() =>
                          'Payment: ${action.mode.toUpperCase()}',
                        SelectCustomerAction() =>
                          'Customer: ${action.customerName}',
                        CustomerNotFoundAction() =>
                          'Add customer: ${action.name}',
                        UnknownProductAction() =>
                          'Not found: "${action.rawName}"',
                        UnknownAction() => 'Unknown: ${action.message}',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              isError
                                  ? Icons.cancel_rounded
                                  : Icons.check_circle_rounded,
                              size: 20,
                              color: isError ? c.danger : c.success,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(label,
                                  style: TextStyle(
                                      color:
                                          isError ? c.danger : c.textPrimary,
                                      fontSize: 14)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _parsedActions.any((a) =>
                            a is! UnknownProductAction && a is! UnknownAction)
                        ? _applyActions
                        : null,
                    child: const Text('Apply to Cart'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

