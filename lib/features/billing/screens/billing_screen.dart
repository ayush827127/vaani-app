import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/voice_action_parser.dart';
import '../services/action_executor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/constants.dart';
import '../../../core/di/injector.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../inventory/repositories/product_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../providers/billing_providers.dart';
import '../../../shared/widgets/hamburger_icon.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../../shared/widgets/barcode_scanner_screen.dart';
import '../../../shared/widgets/shell_scaffold_key.dart';
import '../../../core/utils/permission_service.dart';
import '../widgets/payment_bottom_sheet.dart';
import '../../../l10n/l10n_extensions.dart';

// ── Cart provider ─────────────────────────────────────────────────────────────

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addProduct(Product product, {int qty = 1}) {
    final idx = state.indexWhere((c) => c.product.id == product.id);
    if (idx >= 0) {
      final updated = List<CartItem>.from(state);
      // copyWith preserves any price override already on this line — a
      // plain CartItem(...) reconstruction would silently reset it.
      updated[idx] = updated[idx].copyWith(quantity: updated[idx].quantity + qty);
      state = updated;
    } else {
      state = [...state, CartItem(product: product, quantity: qty)];
    }
  }

  void updateQuantity(int productId, int qty) {
    if (qty <= 0) {
      removeProduct(productId);
      return;
    }
    state = state
        .map((c) => c.product.id == productId ? c.copyWith(quantity: qty) : c)
        .toList();
  }

  void removeProduct(int productId) {
    state = state.where((c) => c.product.id != productId).toList();
  }

  void updatePrice(int productId, double price) {
    debugPrint('[CartNotifier] updatePrice(id=$productId, price=$price) '
        '— items before: ${state.length}');
    state = state
        .map((c) => c.product.id == productId
            ? CartItem(product: c.product, quantity: c.quantity, overridePrice: price)
            : c)
        .toList();
    debugPrint('[CartNotifier] updatePrice done — items after: ${state.length}');
  }

  void resetPrice(int productId) {
    debugPrint('[CartNotifier] resetPrice(id=$productId)');
    state = state
        .map((c) => c.product.id == productId
            ? CartItem(product: c.product, quantity: c.quantity)
            : c)
        .toList();
    debugPrint('[CartNotifier] resetPrice done');
  }

  void clear() => state = [];

  double get subtotal => state.fold(0, (s, c) => s + c.lineTotal);
  double get gstAmount => state.fold(0, (s, c) => s + c.gstAmount);
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());

// ── BillingScreen ─────────────────────────────────────────────────────────────

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final _searchCtrl = TextEditingController();
  final _tts = FlutterTts();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Customer? _selectedCustomer;
  int _shopId = 1;

  VoiceActionParser? _voiceParser;
  List<Customer> _customers = [];
  bool _isPttProcessing = false;

  String _discountType = 'none';
  double _discountValue = 0;
  String _paymentMode = 'upi';
  bool _isGridView = true;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _initTts();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload the product list whenever this screen becomes active again
    // (e.g. returning from product edit via a different route).
    if (_shopId > 0) _loadProducts();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
      _isGridView = prefs.getBool('billing_grid_view') ?? true;
    });
    final backendBaseUrl = dotenv.env['BACKEND_API_BASE_URL'] ?? '';
    final shopToken = prefs.getString(AppConstants.keyShopBackendToken);
    if (backendBaseUrl.isNotEmpty && shopToken != null && shopToken.isNotEmpty) {
      _voiceParser = VoiceActionParser(backendBaseUrl, shopToken);
    }
    await _loadProducts();
    final customers = await getIt<CustomerRepository>().getAllCustomers(_shopId);
    if (mounted) setState(() => _customers = customers);
  }

  Future<void> _loadProducts() async {
    final products = await getIt<ProductRepository>().getAllProducts(_shopId);
    if (mounted) {
      setState(() {
        _allProducts = products;
        _filteredProducts = List.from(products);
      });
    }
  }

  void _filterProducts() {
    final lower = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchSearch = lower.isEmpty ||
            p.name.toLowerCase().contains(lower) ||
            (p.sku?.toLowerCase().contains(lower) ?? false) ||
            (p.barcode?.toLowerCase().contains(lower) ?? false) ||
            p.aliases.any((a) => a.toLowerCase().contains(lower));
        final matchCat =
            _selectedCategory == null || p.category == _selectedCategory;
        return matchSearch && matchCat;
      }).toList();
    });
  }

  Future<void> _scanAndAddToCart() async {
    final granted = await PermissionService.requestCamera(context);
    if (!granted || !mounted) return;
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    print('[Barcode] Scanner returned raw: "${code.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}" (len:${code.length})');
    final product = await getIt<ProductRepository>().getProductByBarcode(_shopId, code);
    if (!mounted) return;
    if (product != null) {
      final currentQty = ref
              .read(cartProvider)
              .where((c) => c.product.id == product.id)
              .firstOrNull
              ?.quantity ??
          0;
      if (currentQty >= product.stockQuantity) {
        _showStockLimitSnack(product);
        return;
      }
      ref.read(cartProvider.notifier).addProduct(product);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${product.name} added to cart'),
        backgroundColor: context.colors.success,
        duration: const Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.barcodeNotRegistered),
        backgroundColor: context.colors.danger,
      ));
    }
  }

  void _increaseQty(Product product) {
    final currentQty = ref
            .read(cartProvider)
            .where((c) => c.product.id == product.id)
            .firstOrNull
            ?.quantity ??
        0;
    if (currentQty >= product.stockQuantity) {
      _showStockLimitSnack(product);
      return;
    }
    ref.read(cartProvider.notifier).addProduct(product);
  }

  void _showStockLimitSnack(Product product) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(product.stockQuantity <= 0
          ? '${product.name} is out of stock'
          : 'Only ${product.stockQuantity} of ${product.name} in stock'),
      backgroundColor: context.colors.danger,
      duration: const Duration(seconds: 2),
    ));
  }

  void _decreaseQty(Product product) {
    final items =
        ref.read(cartProvider).where((c) => c.product.id == product.id).toList();
    if (items.isEmpty) return;
    final qty = items.first.quantity;
    if (qty <= 1) {
      ref.read(cartProvider.notifier).removeProduct(product.id!);
    } else {
      ref.read(cartProvider.notifier).updateQuantity(product.id!, qty - 1);
    }
  }

  double _calcDiscount(double subtotal) {
    double raw;
    if (_discountType == 'percent') {
      raw = subtotal * _discountValue / 100;
    } else if (_discountType == 'flat') {
      raw = _discountValue;
    } else {
      raw = 0;
    }
    // A discount can never exceed the bill it's applied to (and never goes
    // negative) — otherwise GST would be charged on a negative taxable
    // value and the grand total could go negative.
    if (raw < 0) return 0;
    if (raw > subtotal) return subtotal;
    return raw;
  }

  // GST is charged on the post-discount taxable value, not the sticker
  // price — the discount is spread across items proportionally to their
  // share of the pre-discount subtotal, then each item is taxed at its own
  // GST rate on what's left. Must be called with a [discount] already
  // clamped to [0, subtotal] (see _calcDiscount).
  double _calcGst(List<CartItem> items, double subtotal, double discount) {
    if (subtotal <= 0) return 0;
    final discountRatio = discount / subtotal;
    return items.fold<double>(
        0, (s, c) => s + c.lineTotal * (1 - discountRatio) * c.product.gstRate / 100);
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CartSheet(),
    );
  }

  void _showVoiceSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => _VoiceSheet(
        allProducts: _allProducts,
        customers: _customers,
        parser: _voiceParser,
        discountType: _discountType,
        discountValue: _discountValue,
        paymentMode: _paymentMode,
        selectedCustomer: _selectedCustomer,
        onDiscountChanged: (t, v) =>
            setState(() { _discountType = t; _discountValue = v; }),
        onPaymentModeChanged: (m) => setState(() => _paymentMode = m),
        onCustomerChanged: (c) => setState(() => _selectedCustomer = c),
        onCustomerNotFound: (name, phone) =>
            _showAddCustomerDialog(name, phone),
      ),
    );
  }

  Future<void> _handleVoiceCommand(String transcript) async {
    debugPrint('[PTT] _handleVoiceCommand: transcript="$transcript" parser=${_voiceParser != null} products=${_allProducts.length}');

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

    setState(() => _isPttProcessing = true);

    final ctx = BillingContext(
      products: _allProducts,
      customers: _customers,
      cartItems: ref.read(cartProvider),
      paymentMode: _paymentMode,
      discountType: _discountType,
      discountValue: _discountValue,
      customerName: _selectedCustomer?.name,
    );

    VoiceParseResult result;
    try {
      result = await _voiceParser!.parse(transcript, ctx);
    } catch (e, st) {
      debugPrint('[PTT] parse() threw: $e\n$st');
      result = VoiceParseResult(
        actions: [],
        failureReason: '[unexpected] ${e.runtimeType}: $e',
      );
    }

    if (!mounted) return;
    setState(() => _isPttProcessing = false);
    debugPrint('[PTT] parse() → ${result.actions.length} actions, failure="${result.failureReason}"');

    if (!result.succeeded) {
      final reason = result.failureReason ?? '[no-actions] No actions.';
      debugPrint('[PTT] FAIL: $reason');
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_pttUserMessage(reason)),
        backgroundColor: context.colors.danger,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () =>
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ));
      return;
    }

    final productsById = {for (final p in _allProducts) if (p.id != null) p.id!: p};
    final executor = ActionExecutor(ref: ref, productsById: productsById);
    final execResult = executor.execute(result.actions);

    // Apply non-cart state changes
    if (execResult.discountChanged) {
      setState(() {
        _discountType = execResult.newDiscountType!;
        _discountValue = execResult.newDiscountValue!;
      });
    }
    if (execResult.paymentModeChanged) {
      setState(() => _paymentMode = execResult.newPaymentMode!);
    }
    if (execResult.customerChanged && execResult.newCustomerId != null) {
      final customer =
          _customers.where((c) => c.id == execResult.newCustomerId).firstOrNull;
      if (customer != null) setState(() => _selectedCustomer = customer);
    }

    if (!mounted) return;

    // Show success summary
    final allMsgs = [
      ...execResult.messages,
      ...execResult.warnings.map((w) => '⚠ $w'),
    ];
    if (allMsgs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(allMsgs.join(' · ')),
        backgroundColor: context.colors.success,
        duration: const Duration(seconds: 3),
      ));
    }

    // Show errors (products not found, etc.)
    if (execResult.errors.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(execResult.errors.join(', ')),
        backgroundColor: context.colors.danger,
        duration: const Duration(seconds: 3),
      ));
    }

    // TTS confirmation
    if (execResult.messages.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _tts.speak(execResult.messages.join('. '));
    }

    // Customer not found dialog — show after a brief delay so snackbar clears
    if (execResult.shouldShowCustomerDialog &&
        execResult.customerNotFoundAction != null &&
        mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showAddCustomerDialog(
          execResult.customerNotFoundAction!.name,
          execResult.customerNotFoundAction!.phone,
        );
      }
    }
  }

  String _pttUserMessage(String reason) {
    if (reason.contains('[empty-transcript]')) return "Didn't catch that. Please speak again.";
    if (reason.contains('[empty-catalog]')) return 'No products in catalog. Add products first.';
    if (reason.contains('[groq-timeout]') || reason.contains('[gemini-timeout]')) {
      return 'AI took too long. Check internet connection.';
    }
    if (reason.contains('[http-401]')) {
      return 'API key invalid or revoked. Generate a new key at console.groq.com and update .env';
    }
    if (reason.contains('[http-429]')) return 'Rate limit hit. Wait a moment and try again.';
    if (reason.contains('[http-400]')) {
      return 'AI request failed (bad request). Check model name and API key.';
    }
    if (reason.contains('[http-')) return 'AI service error (${_extractHttpCode(reason)}). Check internet.';
    if (reason.contains('[json-')) return 'AI response was malformed. Try again.';
    if (reason.contains('[no-actions]') || reason.contains('[no-valid-actions]')) {
      return "Couldn't understand the command. Try saying product names clearly.";
    }
    return "Voice command failed. Check logcat for [VoiceParser] tags.";
  }

  String _extractHttpCode(String reason) {
    final m = RegExp(r'\[http-(\d+)\]').firstMatch(reason);
    return m != null ? 'HTTP ${m.group(1)}' : 'error';
  }

  Future<void> _showAddCustomerDialog(String name, String? phone) async {
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController(text: phone ?? '');

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // Use ctx (the dialog's BuildContext) for all InheritedWidget lookups
        // to avoid registering stale dependencies on the parent element.
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Customer Not Found',
              style: TextStyle(color: c.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add as new customer?',
                  style: TextStyle(color: c.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add Customer',
                  style: TextStyle(color: AppColors.primaryLight)),
            ),
          ],
        );
      },
    );

    final enteredName = nameCtrl.text.trim();
    final enteredPhone = phoneCtrl.text.trim();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    if (shouldAdd != true || !mounted) return;

    try {
      final now = DateTime.now();
      final customer = Customer(
        shopId: _shopId,
        name: enteredName.isEmpty ? name : enteredName,
        phone: enteredPhone.isEmpty ? null : enteredPhone,
        createdAt: now,
        updatedAt: now,
      );
      final id = await getIt<CustomerRepository>().insertCustomer(customer);
      final saved = Customer(
        id: id,
        shopId: customer.shopId,
        name: customer.name,
        phone: customer.phone,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
      );
      if (mounted) {
        setState(() {
          _selectedCustomer = saved;
          _customers = [..._customers, saved];
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${saved.name} added as customer'),
          backgroundColor: context.colors.success,
        ));
      }
    } catch (e) {
      debugPrint('[BillingScreen] Failed to add customer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to add customer'),
          backgroundColor: context.colors.danger,
        ));
      }
    }
  }

  Future<void> _editItemPrice(Product product) async {
    debugPrint('[PriceEdit] Opening for "${product.name}" (id=${product.id})');

    final cart = ref.read(cartProvider);
    final item = cart.where((c) => c.product.id == product.id).firstOrNull;
    if (item == null) {
      debugPrint('[PriceEdit] Product not found in cart — aborting');
      return;
    }

    debugPrint('[PriceEdit] effectivePrice=${item.effectivePrice}, '
        'overridePrice=${item.overridePrice}, qty=${item.quantity}');

    // _PriceEditDialog is a StatefulWidget that owns its TextEditingController.
    // State.dispose() is called only after the dialog's exit animation finishes
    // (children unmount before parents), so the controller is never disposed
    // while EditableText is still in the tree — that was the cause of the
    // _dependents.isEmpty assertion.
    final result = await showDialog<_PriceEditResult>(
      context: context,
      builder: (_) => _PriceEditDialog(
        productName: product.name,
        defaultPrice: product.sellingPrice,
        currentPrice: item.effectivePrice,
        hasOverride: item.overridePrice != null,
      ),
    );

    debugPrint('[PriceEdit] Dialog returned: '
        '${result == null ? "cancelled" : result.reset ? "reset" : "price=${result.price}"}');

    if (result == null || !mounted) {
      debugPrint('[PriceEdit] No change (cancelled or unmounted)');
      return;
    }

    if (result.reset) {
      debugPrint('[PriceEdit] Calling resetPrice(${product.id})');
      ref.read(cartProvider.notifier).resetPrice(product.id!);
    } else if (result.price != null) {
      debugPrint('[PriceEdit] Calling updatePrice(${product.id}, ${result.price})');
      ref.read(cartProvider.notifier).updatePrice(product.id!, result.price!);
    }

    debugPrint('[PriceEdit] Done');
  }

  void _showDiscountSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DiscountSheet(
        type: _discountType,
        value: _discountValue,
        onApply: (type, val) => setState(() {
          _discountType = type;
          _discountValue = val;
        }),
      ),
    );
  }

  void _showPaymentSheet() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.cartEmptySnack),
          backgroundColor: context.colors.danger));
      return;
    }
    final n = ref.read(cartProvider.notifier);
    final subtotal = n.subtotal;
    final discount = _calcDiscount(subtotal);
    final gst = _calcGst(cart, subtotal, discount);
    final grandTotal = subtotal - discount + gst;

    showPaymentSheet(
      context: context,
      shopId: _shopId,
      cartItems: cart,
      subtotal: subtotal,
      gstAmount: gst,
      discountAmount: discount,
      grandTotal: grandTotal,
      discountType: _discountType,
      discountValue: _discountValue,
      initialPaymentMode: _paymentMode,
      initialCustomer: _selectedCustomer,
      onSuccess: () {
        ref.read(cartProvider.notifier).clear();
        setState(() {
          _selectedCustomer = null;
          _discountType = 'none';
          _discountValue = 0;
          _paymentMode = 'upi';
        });
      },
    );
  }

  void _confirmClear() {
    final c = context.colors;
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.clearCart, style: TextStyle(color: c.textPrimary)),
        content: Text(l10n.removeAllItemsConfirm,
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.cancel,
                  style: TextStyle(color: c.textSecondary))),
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.pop(dialogCtx);
            },
            child: Text(l10n.clear, style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final customers =
        await getIt<CustomerRepository>().getAllCustomers(shopId);
    if (!mounted) return;
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CustomerPickerSheet(customers: customers),
    );
    if (selected != null) setState(() => _selectedCustomer = selected);
  }

  List<String> get _uniqueCategories {
    final cats = _allProducts
        .where((p) => p.category?.isNotEmpty == true)
        .map((p) => p.category!)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  int _categoryCount(String cat) =>
      _allProducts.where((p) => p.category == cat).length;

  Future<void> _toggleView() async {
    final next = !_isGridView;
    setState(() => _isGridView = next);
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('billing_grid_view', next);
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(0.9);
      await _tts.setPitch(1.0);
    } catch (_) {
      // TTS engine unavailable — voice confirmation will be silent
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(voiceTriggerProvider, (_, __) => _showVoiceSheet());
    ref.listen<String?>(pttTranscriptProvider, (_, transcript) {
      if (transcript != null && transcript.isNotEmpty) {
        debugPrint('[PTT] Transcript received in BillingScreen: "$transcript"');
        ref.read(pttTranscriptProvider.notifier).state = null;
        _handleVoiceCommand(transcript);
      }
    });

    final cart = ref.watch(cartProvider);
    final pttRecording = ref.watch(pttRecordingProvider);
    final partialTranscript = ref.watch(pttPartialTranscriptProvider);
    final showPttOverlay = pttRecording || _isPttProcessing;
    final n = ref.read(cartProvider.notifier);
    final subtotal = n.subtotal;
    final discount = _calcDiscount(subtotal);
    final gst = _calcGst(cart, subtotal, discount);
    final total = subtotal - discount + gst;
    final cartQtyMap = {for (final c in cart) c.product.id!: c.quantity};
    final cartOverrideMap = {
      for (final c in cart)
        if (c.overridePrice != null) c.product.id!: c.overridePrice!
    };

    return Scaffold(
      bottomNavigationBar: cart.isEmpty
          ? null
          : _buildStickySummary(
              cart: cart,
              subtotal: subtotal,
              gst: gst,
              discount: discount,
              total: total),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            _buildHeader(cart),
            const SizedBox(height: 16),
            // ── Search bar ───────────────────────────────────────────────────
            _buildSearchBar(),
            const SizedBox(height: 16),
            // ── Category chips (only when categories exist) ──────────────────
            if (_uniqueCategories.isNotEmpty) ...[
              _buildCategoryChips(),
              const SizedBox(height: 16),
            ],
            // ── Products count + view toggle ──────────────────────────────────
            _buildViewToggleBar(),
            const SizedBox(height: 8),
            // ── Product list / grid ───────────────────────────────────────────
            Expanded(child: _buildProductArea(cartQtyMap, cartOverrideMap)),
            // ── PTT live transcript + AI processing overlay ───────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, 1), end: Offset.zero)
                    .animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showPttOverlay
                  ? _PTTOverlay(
                      key: const ValueKey('ptt_overlay'),
                      transcript: partialTranscript,
                      isProcessing: _isPttProcessing,
                    )
                  : const SizedBox.shrink(key: ValueKey('ptt_empty')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(List<CartItem> cart) {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const HamburgerIcon(),
            onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: Text(
              l10n.newBill,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
          ),
          if (cart.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded,
                  color: c.danger.withValues(alpha: 0.8), size: 22),
              onPressed: _confirmClear,
              tooltip: l10n.clearCartTooltip,
            ),
          GestureDetector(
            onTap: _selectCustomer,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.inputBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_rounded,
                      size: 13, color: c.textSecondary),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 90),
                    child: Text(
                      _selectedCustomer?.name ?? l10n.walkIn,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 14, color: c.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.inputBorder),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(color: c.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: context.l10n.searchProductsByNameHint,
            hintStyle: TextStyle(color: c.textHint, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded,
                color: isDark ? c.textHint : AppColors.primaryLight, size: 22),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear_rounded,
                        color: c.textHint, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      _filterProducts();
                    },
                  ),
                IconButton(
                  icon: Icon(Icons.qr_code_scanner_rounded,
                      color: c.textHint, size: 22),
                  onPressed: _scanAndAddToCart,
                ),
              ],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onChanged: (_) => _filterProducts(),
        ),
      ),
    );
  }

  // ── Category chips ──────────────────────────────────────────────────────────

  Widget _buildCategoryChips() {
    final cats = _uniqueCategories;
    final l10n = context.l10n;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CatChip(
            label: l10n.all,
            count: _allProducts.length,
            selected: _selectedCategory == null,
            onTap: () => setState(() {
              _selectedCategory = null;
              _filterProducts();
            }),
          ),
          ...cats.map((cat) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _CatChip(
                  label: localizedCategory(l10n, cat),
                  count: _categoryCount(cat),
                  selected: _selectedCategory == cat,
                  onTap: () => setState(() {
                    _selectedCategory = _selectedCategory == cat ? null : cat;
                    _filterProducts();
                  }),
                ),
              )),
        ],
      ),
    );
  }

  // ── View toggle bar ─────────────────────────────────────────────────────────

  Widget _buildViewToggleBar() {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            l10n.productsCount(_filteredProducts.length),
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewToggleBtn(
                  icon: Icons.grid_view_rounded,
                  label: l10n.gridView,
                  active: _isGridView,
                  onTap: _isGridView ? null : _toggleView,
                ),
                _ViewToggleBtn(
                  icon: Icons.view_list_rounded,
                  label: l10n.listView,
                  active: !_isGridView,
                  onTap: !_isGridView ? null : _toggleView,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Product area ────────────────────────────────────────────────────────────

  Widget _buildProductArea(
      Map<int, int> cartQtyMap, Map<int, double> cartOverrideMap) {
    if (_allProducts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      );
    }
    if (_filteredProducts.isEmpty) {
      final c = context.colors;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: c.textSecondary),
            const SizedBox(height: 12),
            Text(
              context.l10n.noProductsMatch(_searchCtrl.text),
              style: TextStyle(color: c.textHint, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
        ),
        itemCount: _filteredProducts.length,
        itemBuilder: (_, i) {
          final p = _filteredProducts[i];
          return _ProductGridCard(
            product: p,
            cartQty: cartQtyMap[p.id] ?? 0,
            overridePrice: cartOverrideMap[p.id],
            onIncrease: () => _increaseQty(p),
            onDecrease: () => _decreaseQty(p),
            onEditPrice: () => _editItemPrice(p),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      itemCount: _filteredProducts.length,
      itemBuilder: (_, i) {
        final p = _filteredProducts[i];
        return _ProductListTile(
          product: p,
          cartQty: cartQtyMap[p.id] ?? 0,
          overridePrice: cartOverrideMap[p.id],
          onIncrease: () => _increaseQty(p),
          onDecrease: () => _decreaseQty(p),
          onEditPrice: () => _editItemPrice(p),
        );
      },
    );
  }

  // ── Sticky summary ──────────────────────────────────────────────────────────

  Widget _buildStickySummary({
    required List<CartItem> cart,
    required double subtotal,
    required double gst,
    required double discount,
    required double total,
  }) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final c = context.colors;
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08), blurRadius: 12)
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad > 0 ? bottomPad : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Three-column summary
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: items + subtotal — tap to review cart
              Expanded(
                child: GestureDetector(
                  onTap: _showCartSheet,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Icon(Icons.shopping_bag_outlined,
                            size: 12, color: c.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          l10n.itemCountLabel(cart.length),
                          style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 11),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.keyboard_arrow_up_rounded,
                            size: 12, color: AppColors.primaryLight),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        AppFormatters.formatCurrency(subtotal),
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              Container(width: 1, height: 36, color: c.divider),
              const SizedBox(width: 10),
              // Middle: discount + tax
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _showDiscountSheet,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            discount > 0
                                ? '-${AppFormatters.formatCurrency(discount)}'
                                : l10n.addDiscount,
                            style: const TextStyle(
                                color: AppColors.primaryLight, fontSize: 11),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.edit_rounded,
                              size: 10, color: AppColors.primaryLight),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.taxLabel(AppFormatters.formatCurrency(gst)),
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: c.divider),
              const SizedBox(width: 10),
              // Right: total + savings
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppFormatters.formatCurrency(total),
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins'),
                    ),
                    Text(
                      l10n.youSave(AppFormatters.formatCurrency(discount)),
                      style: TextStyle(
                          color: discount > 0
                              ? c.success
                              : c.textSecondary,
                          fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Payment mode chips (scrollable full-width row)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppConstants.paymentModes.map((mode) {
                final isSelected = _paymentMode == mode;
                return GestureDetector(
                  onTap: () => setState(() => _paymentMode = mode),
                  child: Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary
                          : c.divider,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      localizedPaymentMode(l10n, mode).toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? Colors.white
                              : c.textSecondary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Proceed button — full width below payment chips
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: cart.isNotEmpty ? _showPaymentSheet : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cart.isNotEmpty
                    ? AppColors.primaryLight
                    : c.divider,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cart.isEmpty ? l10n.proceed : l10n.payAmount(AppFormatters.formatCurrency(total)),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cart.isNotEmpty
                            ? Colors.white
                            : c.textDisabled),
                  ),
                  if (cart.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared drawer item ─────────────────────────────────────────────────────────

// ── Category chip ──────────────────────────────────────────────────────────────

class _CatChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected && isDark
              ? const LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? (isDark ? null : AppColors.primaryLightTheme)
              : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.transparent : c.inputBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : c.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
            const SizedBox(width: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : c.divider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 10,
                      color: selected ? Colors.white : c.textHint,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── View toggle button ─────────────────────────────────────────────────────────

class _ViewToggleBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ViewToggleBtn(
      {required this.icon,
      required this.label,
      required this.active,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? Colors.white : c.textHint),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? Colors.white : c.textHint,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ── Product Grid Card ──────────────────────────────────────────────────────────

class _ProductGridCard extends StatelessWidget {
  final Product product;
  final int cartQty;
  final double? overridePrice;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onEditPrice;

  const _ProductGridCard({
    required this.product,
    required this.cartQty,
    required this.onIncrease,
    required this.onDecrease,
    required this.onEditPrice,
    this.overridePrice,
  });

  static const _palette = [
    Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF16A34A),
    Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF0891B2),
    Color(0xFF65A30D), Color(0xFF9333EA), Color(0xFFD97706),
  ];

  Color get _catColor =>
      _palette[(product.category ?? '').hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    final inStock = product.stockQuantity > 0;
    final inCart = cartQty > 0;
    final catColor = _catColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final c = context.colors;
        final l10n = context.l10n;

        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // ── Adaptive card padding ──────────────────────────────────────────
        final pad    = (h * 0.068).clamp(6.0, 9.0);
        final innerW = w - pad * 2;
        final innerH = h - pad * 2;

        // ── Left column: avatar (32 % of inner width) ──────────────────────
        final leftW    = innerW * 0.32;
        final hGap     = (innerW * 0.055).clamp(6.0, 10.0);
        final avatarSz = leftW.clamp(32.0, 54.0);

        // ── Right column sizes (derived from inner height) ─────────────────
        final nameFontSz = (innerH * 0.148).clamp(10.5, 13.0);
        final prFontSz   = (innerH * 0.172).clamp(11.0, 15.0);
        final ppv        = (innerH * 0.040).clamp(3.0,  5.5);   // price pad V per side
        final pmv        = (innerH * 0.030).clamp(2.0,  4.0);   // price margin V per side
        final stFontSz   = (innerH * 0.092).clamp(8.0,  10.0);
        final stPadV     = (innerH * 0.022).clamp(1.5,  3.0);
        final btnSz      = (innerH * 0.252).clamp(22.0, 28.0);
        final qtyFontSz  = (innerH * 0.162).clamp(12.0, 15.0);

        final priceAccent = overridePrice != null
            ? const Color(0xFFE67E22)
            : AppColors.primaryLight;

        return Container(
          decoration: BoxDecoration(
            color: inCart
                ? AppColors.primary.withValues(alpha: 0.08)
                : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: inCart
                  ? AppColors.primaryLight.withValues(alpha: 0.5)
                  : c.surfaceBorder,
              width: inCart ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left: avatar, vertically centered ─────────────────────
                SizedBox(
                  width: leftW,
                  child: Center(
                    child: ProductAvatar(
                      product: product,
                      size: avatarSz,
                      catColor: catColor,
                      borderRadiusValue: (avatarSz * 0.23).clamp(8.0, 12.0),
                    ),
                  ),
                ),
                SizedBox(width: hGap),
                // ── Right: name → price → stock → [spacer] → qty ──────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        product.name,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: nameFontSz,
                            fontWeight: FontWeight.w600,
                            height: 1.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Price — tap-to-edit zone when in cart
                      GestureDetector(
                        onTap: inCart ? onEditPrice : null,
                        child: Container(
                          margin: EdgeInsets.symmetric(vertical: pmv),
                          padding: EdgeInsets.symmetric(
                              horizontal: 6, vertical: ppv),
                          decoration: inCart
                              ? BoxDecoration(
                                  color: priceAccent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: priceAccent
                                          .withValues(alpha: 0.45)),
                                )
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppFormatters.formatCurrency(
                                    overridePrice ?? product.sellingPrice),
                                style: TextStyle(
                                    color: priceAccent,
                                    fontSize: prFontSz,
                                    fontWeight: FontWeight.bold),
                              ),
                              if (inCart) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.edit_rounded,
                                    size: (prFontSz * 0.82).clamp(10.0, 13.0),
                                    color: priceAccent),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Stock badge
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 5, vertical: stPadV),
                        decoration: BoxDecoration(
                          color: inStock
                              ? c.success.withValues(alpha: 0.15)
                              : c.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          inStock
                              ? l10n.qtyColon('${product.stockQuantity}')
                              : l10n.outOfStockBadge,
                          style: TextStyle(
                              fontSize: stFontSz,
                              color: inStock ? c.success : c.danger,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      // Qty controls: - count +
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _QtyBtn(
                            icon: Icons.remove,
                            onTap: cartQty > 0 ? onDecrease : null,
                            active: cartQty > 0,
                            size: btnSz,
                          ),
                          Text(
                            '$cartQty',
                            style: TextStyle(
                                color: cartQty > 0
                                    ? c.textPrimary
                                    : c.textDisabled,
                                fontSize: qtyFontSz,
                                fontWeight: FontWeight.bold),
                          ),
                          _QtyBtn(
                            icon: Icons.add,
                            onTap: inStock ? onIncrease : null,
                            active: inStock,
                            size: btnSz,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Product List Tile ──────────────────────────────────────────────────────────

class _ProductListTile extends StatelessWidget {
  final Product product;
  final int cartQty;
  final double? overridePrice;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onEditPrice;

  const _ProductListTile({
    required this.product,
    required this.cartQty,
    required this.onIncrease,
    required this.onDecrease,
    required this.onEditPrice,
    this.overridePrice,
  });

  static const _palette = [
    Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF16A34A),
    Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF0891B2),
    Color(0xFF65A30D), Color(0xFF9333EA), Color(0xFFD97706),
  ];

  Color get _catColor =>
      _palette[(product.category ?? '').hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final inStock = product.stockQuantity > 0;
    final inCart = cartQty > 0;
    final catColor = _catColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: inCart
            ? AppColors.primary.withValues(alpha: 0.08)
            : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inCart
              ? AppColors.primaryLight.withValues(alpha: 0.4)
              : c.surfaceBorder,
          width: inCart ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Product image / initial avatar
          ProductAvatar(
            product: product,
            size: 44,
            catColor: catColor,
            borderRadiusValue: 10,
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // Price — tap-to-edit zone with visible border when in cart
                    GestureDetector(
                      onTap: inCart ? onEditPrice : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: inCart
                            ? BoxDecoration(
                                color: (overridePrice != null
                                        ? const Color(0xFFE67E22)
                                        : AppColors.primaryLight)
                                    .withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (overridePrice != null
                                          ? const Color(0xFFE67E22)
                                          : AppColors.primaryLight)
                                      .withValues(alpha: 0.40),
                                ),
                              )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppFormatters.formatCurrency(
                                  overridePrice ?? product.sellingPrice),
                              style: TextStyle(
                                  color: overridePrice != null
                                      ? const Color(0xFFE67E22)
                                      : AppColors.primaryLight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (inCart) ...[
                              const SizedBox(width: 5),
                              Icon(Icons.edit_rounded,
                                  size: 14,
                                  color: overridePrice != null
                                      ? const Color(0xFFE67E22)
                                      : AppColors.primaryLight),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: inStock
                            ? c.success.withValues(alpha: 0.15)
                            : c.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        inStock
                            ? l10n.inStockQty('${product.stockQuantity}')
                            : l10n.outLabel,
                        style: TextStyle(
                            fontSize: 9,
                            color: inStock ? c.success : c.danger,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Qty controls
          Row(
            children: [
              _QtyBtn(
                  icon: Icons.remove,
                  onTap: cartQty > 0 ? onDecrease : null,
                  active: cartQty > 0),
              SizedBox(
                width: 34,
                child: Text(
                  '$cartQty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: cartQty > 0 ? c.textPrimary : c.textDisabled,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
              _QtyBtn(
                  icon: Icons.add,
                  onTap: inStock ? onIncrease : null,
                  active: inStock),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Qty button ────────────────────────────────────────────────────────────────

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final double size;

  const _QtyBtn(
      {required this.icon,
      required this.onTap,
      required this.active,
      this.size = 28});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active && onTap != null
              ? cs.primary
              : c.divider,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: active && onTap != null ? Colors.white : c.textDisabled,
        ),
      ),
    );
  }
}

// ── Cart Review Sheet ─────────────────────────────────────────────────────────

class _CartSheet extends ConsumerStatefulWidget {
  const _CartSheet();

  @override
  ConsumerState<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<_CartSheet> {
  final Map<int, TextEditingController> _ctrls = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(CartItem item) {
    return _ctrls.putIfAbsent(
      item.product.id!,
      () => TextEditingController(
          text: item.effectivePrice.toStringAsFixed(0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final c = context.colors;

    final double total =
        cart.fold(0, (s, item) => s + item.lineTotal);

    return SafeArea(
      top: false,
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Cart (${cart.length})',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Tap price to edit',
                        style: TextStyle(color: c.textHint, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: c.divider),
                ],
              ),
            ),

            // Items list
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                shrinkWrap: true,
                itemCount: cart.length,
                separatorBuilder: (_, __) => Divider(color: c.divider, height: 1),
                itemBuilder: (_, i) {
                  final item = cart[i];
                  final ctrl = _ctrlFor(item);
                  final isOverridden = item.overridePrice != null &&
                      item.overridePrice != item.product.sellingPrice;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Product name
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Qty stepper
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CartItemQtyBtn(
                              icon: Icons.remove_rounded,
                              onTap: () {
                                if (item.quantity <= 1) {
                                  notifier.removeProduct(item.product.id!);
                                } else {
                                  notifier.updateQuantity(
                                      item.product.id!, item.quantity - 1);
                                }
                              },
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${item.quantity}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _CartItemQtyBtn(
                              icon: Icons.add_rounded,
                              onTap: () {
                                if (item.quantity >= item.product.stockQuantity) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        'Only ${item.product.stockQuantity} of ${item.product.name} in stock'),
                                    backgroundColor: c.danger,
                                    duration: const Duration(seconds: 2),
                                  ));
                                  return;
                                }
                                notifier.updateQuantity(
                                    item.product.id!, item.quantity + 1);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),

                        // Price (editable)
                        SizedBox(
                          width: 72,
                          height: 36,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isOverridden
                                  ? AppColors.primaryLight
                                  : c.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹',
                              prefixStyle: TextStyle(
                                color: isOverridden
                                    ? AppColors.primaryLight
                                    : c.textSecondary,
                                fontSize: 12,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              filled: true,
                              fillColor: isOverridden
                                  ? AppColors.primaryLight.withValues(alpha: 0.08)
                                  : c.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: isOverridden
                                        ? AppColors.primaryLight
                                        : c.inputBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: isOverridden
                                        ? AppColors.primaryLight
                                        : c.inputBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: AppColors.primaryLight, width: 1.5),
                              ),
                            ),
                            onChanged: (val) {
                              final price = double.tryParse(val);
                              if (price != null && price > 0) {
                                notifier.updatePrice(item.product.id!, price);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Footer: total + done
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.divider)),
              ),
              child: Row(
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                        color: c.textSecondary, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    AppFormatters.formatCurrency(total),
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Done',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemQtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CartItemQtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppColors.primaryLight),
      ),
    );
  }
}

// ── Inline Voice Sheet ────────────────────────────────────────────────────────

class _VoiceSheet extends ConsumerStatefulWidget {
  final List<Product> allProducts;
  final List<Customer> customers;
  final VoiceActionParser? parser;
  final String discountType;
  final double discountValue;
  final String paymentMode;
  final Customer? selectedCustomer;
  final void Function(String type, double value) onDiscountChanged;
  final void Function(String mode) onPaymentModeChanged;
  final void Function(Customer customer) onCustomerChanged;
  final void Function(String name, String? phone) onCustomerNotFound;

  const _VoiceSheet({
    required this.allProducts,
    required this.customers,
    this.parser,
    required this.discountType,
    required this.discountValue,
    required this.paymentMode,
    this.selectedCustomer,
    required this.onDiscountChanged,
    required this.onPaymentModeChanged,
    required this.onCustomerChanged,
    required this.onCustomerNotFound,
  });

  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet>
    with SingleTickerProviderStateMixin {
  final _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  String _recognized = '';
  List<VoiceAction> _parsedActions = [];
  bool _isParsingAI = false;
  bool _isApplying = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _initAndListen();
  }

  Future<void> _initAndListen() async {
    final granted = await PermissionService.requestMicrophone(context);
    if (!granted || !mounted) {
      setState(() => _speechAvailable = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            mounted &&
            _isListening) {
          setState(() => _isListening = false);
          if (_recognized.isNotEmpty) _parseResults(_recognized);
        }
      },
    );
    if (!mounted) return;
    setState(() => _speechAvailable = available);
    if (available) _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _recognized = '';
      _parsedActions = [];
      _isParsingAI = false;
    });
    await _speech.listen(
      onResult: (r) {
        if (mounted && r.recognizedWords.isNotEmpty) {
          setState(() => _recognized = r.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: 'hi_IN',
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _stopAndParse() async {
    setState(() => _isListening = false);
    await _speech.stop();
    if (_recognized.isNotEmpty) await _parseResults(_recognized);
  }

  Future<void> _parseResults(String input) async {
    if (!mounted || widget.parser == null) {
      if (mounted && widget.parser == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Voice parser not ready. Check API key.'),
          backgroundColor: context.colors.danger,
        ));
      }
      return;
    }
    setState(() => _isParsingAI = true);

    final cart = ref.read(cartProvider);
    final ctx = BillingContext(
      products: widget.allProducts,
      customers: widget.customers,
      cartItems: cart,
      paymentMode: widget.paymentMode,
      discountType: widget.discountType,
      discountValue: widget.discountValue,
      customerName: widget.selectedCustomer?.name,
    );

    VoiceParseResult? result;
    try {
      result = await widget.parser!.parse(input, ctx);
    } catch (e, st) {
      debugPrint('[VoiceSheet] parse() threw: $e\n$st');
    }

    if (!mounted) return;
    setState(() {
      _parsedActions = result?.actions ?? [];
      _isParsingAI = false;
    });

    if (result == null || !result.succeeded) {
      final reason =
          result?.failureReason ?? '[no-parser] Parse failed.';
      final msg = reason.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '');
      debugPrint('[VoiceSheet] parse failed: $reason');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: context.colors.danger,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  void _applyActions() {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    final productsById = {
      for (final p in widget.allProducts) if (p.id != null) p.id!: p
    };
    final executor = ActionExecutor(ref: ref, productsById: productsById);
    final execResult = executor.execute(_parsedActions);

    // Trigger parent callbacks for non-cart state changes
    if (execResult.discountChanged) {
      widget.onDiscountChanged(
          execResult.newDiscountType!, execResult.newDiscountValue!);
    }
    if (execResult.paymentModeChanged) {
      widget.onPaymentModeChanged(execResult.newPaymentMode!);
    }
    if (execResult.customerChanged && execResult.newCustomerId != null) {
      final customer = widget.customers
          .where((c) => c.id == execResult.newCustomerId)
          .firstOrNull;
      if (customer != null) widget.onCustomerChanged(customer);
    }
    if (execResult.shouldShowCustomerDialog &&
        execResult.customerNotFoundAction != null) {
      widget.onCustomerNotFound(
        execResult.customerNotFoundAction!.name,
        execResult.customerNotFoundAction!.phone,
      );
    }

    // Capture context-dependent values BEFORE pop — the sheet's context becomes
    // invalid once Navigator.pop() starts the exit animation.
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;
    final dangerColor = context.colors.danger;
    final allMsgs = [
      ...execResult.messages,
      ...execResult.warnings.map((w) => '⚠ $w'),
    ];
    final errors = List<String>.from(execResult.errors);

    Navigator.pop(context);

    if (allMsgs.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(allMsgs.join(' · ')),
        backgroundColor: successColor,
        duration: const Duration(seconds: 3),
      ));
    }
    if (errors.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(errors.join(', ')),
        backgroundColor: dangerColor,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _pulse.dispose();
    super.dispose();
  }

  IconData _actionIcon(VoiceAction action) {
    return switch (action) {
      SetQuantityAction() => Icons.shopping_cart_rounded,
      IncreaseQuantityAction() => Icons.add_shopping_cart_rounded,
      DecreaseQuantityAction() => Icons.remove_shopping_cart_rounded,
      RemoveItemAction() => Icons.delete_outline_rounded,
      ClearCartAction() => Icons.delete_sweep_rounded,
      UpdatePriceAction() => Icons.currency_rupee_rounded,
      DiscountAction() => Icons.local_offer_rounded,
      PaymentModeAction() => Icons.payment_rounded,
      SelectCustomerAction() => Icons.person_rounded,
      CustomerNotFoundAction() => Icons.person_add_rounded,
      UnknownProductAction() => Icons.cancel_rounded,
      UnknownAction() => Icons.help_outline_rounded,
    };
  }

  String _actionLabel(VoiceAction action) {
    return switch (action) {
      SetQuantityAction() =>
        '${action.productName} × ${action.quantity}${action.inventoryWarning ? " ⚠ low stock" : ""}',
      IncreaseQuantityAction() =>
        '+${action.delta} more ${action.productName}',
      DecreaseQuantityAction() =>
        '−${action.delta} from ${action.productName}',
      RemoveItemAction() => 'Remove ${action.productName}',
      ClearCartAction() => 'Clear entire cart',
      UpdatePriceAction() =>
        '${action.productName} → ₹${action.price.toStringAsFixed(0)}',
      DiscountAction() =>
        'Discount: ${action.discountType == "percent" ? "${action.value.toStringAsFixed(0)}%" : "₹${action.value.toStringAsFixed(0)}"}',
      PaymentModeAction() => 'Payment: ${action.mode.toUpperCase()}',
      SelectCustomerAction() => 'Customer: ${action.customerName}',
      CustomerNotFoundAction() => 'Add customer: ${action.name}',
      UnknownProductAction() => 'Not found: "${action.rawName}"',
      UnknownAction() => 'Unknown: ${action.message}',
    };
  }

  bool _isErrorAction(VoiceAction action) =>
      action is UnknownProductAction || action is UnknownAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final hasActions = _parsedActions.isNotEmpty;
    final validCount =
        _parsedActions.where((a) => !_isErrorAction(a)).length;

    final statusText = _isParsingAI
        ? 'AI is analyzing...'
        : _isListening
            ? l10n.listeningTapToStop
            : hasActions
                ? l10n.tapMicSpeakAgain
                : _speechAvailable
                    ? l10n.tapMicToSpeak
                    : l10n.micUnavailable;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.surfaceBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            // Mic button
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _isListening ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: GestureDetector(
                onTap: _speechAvailable
                    ? (_isListening ? _stopAndParse : _startListening)
                    : null,
                child: Container(
                  width: 100,
                  height: 100,
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
                        color: (_isListening
                                ? AppColors.error
                                : AppColors.primary)
                            .withValues(alpha: 0.45),
                        blurRadius: 28,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(statusText,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins')),
            // Recognized transcript
            if (_recognized.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.surfaceBorder),
                ),
                child: Text('"$_recognized"',
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center),
              ),
            ],
            // AI processing spinner
            if (_isParsingAI) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 10),
                  Text('AI is understanding your voice...',
                      style: TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 13,
                          fontFamily: 'Poppins')),
                ],
              ),
            ],
            // Action preview list
            if (hasActions && !_isParsingAI) ...[
              const SizedBox(height: 14),
              ..._parsedActions.map((action) {
                final isError = _isErrorAction(action);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(
                      _actionIcon(action),
                      size: 18,
                      color: isError ? c.danger : c.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _actionLabel(action),
                        style: TextStyle(
                            color: isError ? c.danger : c.textPrimary,
                            fontSize: 13),
                      ),
                    ),
                  ]),
                );
              }),
            ],
            // Action buttons
            if (hasActions && !_isListening && !_isParsingAI) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: validCount > 0 ? _applyActions : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text('Apply $validCount action${validCount == 1 ? "" : "s"}'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _startListening,
                child: Text(l10n.speakAgain,
                    style: TextStyle(color: c.textSecondary)),
              ),
            ],
            // Hint chips when idle
            if (!_isListening && !hasActions && !_isParsingAI) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children:
                    ['"do Coke, teen Maggi"', '"GPay karo"', '"Rahul customer"']
                        .map((s) => Chip(
                              label: Text(s,
                                  style: TextStyle(
                                      fontSize: 11, color: c.textSecondary)),
                              backgroundColor:
                                  Theme.of(context).scaffoldBackgroundColor,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Price edit result ─────────────────────────────────────────────────────────

class _PriceEditResult {
  final double? price;
  final bool reset;
  const _PriceEditResult({this.price, this.reset = false});
}

// ── Price edit dialog ─────────────────────────────────────────────────────────
//
// Root cause of the _dependents.isEmpty assertion:
//   When the controller was created outside showDialog and disposed after
//   `await showDialog` returned, the dialog's exit animation was still running
//   and the TextField was still in the widget tree — still attached to the
//   controller. Disposing the controller while EditableText is mounted leaves
//   the InheritedElement dependency tracking in an inconsistent state, so the
//   assertion fires when the overlay is unmounted.
//
// Fix: own the TextEditingController inside a StatefulWidget. Flutter unmounts
// children before parents, so EditableTextState.dispose() (which removes the
// listener) runs before _PriceEditDialogState.dispose() (which calls
// _ctrl.dispose()). The controller is never disposed while a TextField is still
// attached.

class _PriceEditDialog extends StatefulWidget {
  final String productName;
  final double defaultPrice;
  final double currentPrice;
  final bool hasOverride;

  const _PriceEditDialog({
    required this.productName,
    required this.defaultPrice,
    required this.currentPrice,
    required this.hasOverride,
  });

  @override
  State<_PriceEditDialog> createState() => _PriceEditDialogState();
}

class _PriceEditDialogState extends State<_PriceEditDialog> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final text = widget.currentPrice
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'\.?0+$'), '');
    _ctrl = TextEditingController(text: text);
    debugPrint('[PriceEdit] _PriceEditDialogState.initState — controller created');
  }

  @override
  void dispose() {
    // Called AFTER the exit animation completes (EditableTextState.dispose() has
    // already removed its listener), so this dispose is safe.
    debugPrint('[PriceEdit] _PriceEditDialogState.dispose — controller disposed '
        'after exit animation');
    _ctrl.dispose();
    super.dispose();
  }

  void _onApply() {
    final text = _ctrl.text.trim();
    final val = double.tryParse(text);
    debugPrint('[PriceEdit] Apply pressed: text="$text", parsed=$val');
    if (val == null || val <= 0) return;
    Navigator.pop(context, _PriceEditResult(price: val));
  }

  @override
  Widget build(BuildContext context) {
    // context is this dialog widget's own BuildContext — InheritedWidget lookups
    // here are properly scoped and cleaned up when the dialog is unmounted.
    final c = context.colors;
    debugPrint('[PriceEdit] _PriceEditDialog.build');
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.productName,
        style: TextStyle(
            color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default: ${AppFormatters.formatCurrency(widget.defaultPrice)}',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle:
                  const TextStyle(color: AppColors.primaryLight, fontSize: 18),
              labelText: 'Price for this bill',
              labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.primaryLight, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _onApply(),
          ),
        ],
      ),
      actions: [
        if (widget.hasOverride)
          TextButton(
            onPressed: () {
              debugPrint('[PriceEdit] Reset to default pressed');
              Navigator.pop(context, const _PriceEditResult(reset: true));
            },
            child: Text('Reset to default',
                style: TextStyle(color: c.danger)),
          ),
        TextButton(
          onPressed: () {
            debugPrint('[PriceEdit] Cancel pressed');
            Navigator.pop(context);
          },
          child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
        ),
        TextButton(
          onPressed: _onApply,
          child: const Text('Apply',
              style: TextStyle(color: AppColors.primaryLight)),
        ),
      ],
    );
  }
}

// ── Discount Sheet ────────────────────────────────────────────────────────────

class _DiscountSheet extends StatefulWidget {
  final String type;
  final double value;
  final Function(String, double) onApply;

  const _DiscountSheet(
      {required this.type, required this.value, required this.onApply});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  late String _type;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.type == 'none' ? 'percent' : widget.type;
    _ctrl.text = widget.value > 0 ? widget.value.toString() : '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.addDiscount,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
          const SizedBox(height: 16),
          Row(
            children: ['percent', 'flat'].map((t) {
              return GestureDetector(
                onTap: () => setState(() => _type = t),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _type == t
                        ? cs.primary
                        : c.divider,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    t == 'percent' ? l10n.percentageOption : l10n.flatAmountOption,
                    style: TextStyle(
                        color: _type == t ? Colors.white : c.textSecondary),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: _type == 'flat' ? '₹ ' : '',
              suffixText: _type == 'percent' ? '%' : '',
              hintText: '0',
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  widget.onApply('none', 0);
                  Navigator.pop(context);
                },
                child: Text(l10n.remove),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(_type, double.tryParse(_ctrl.text) ?? 0);
                  Navigator.pop(context);
                },
                child: Text(l10n.apply),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ── Customer Picker Sheet ─────────────────────────────────────────────────────

class _CustomerPickerSheet extends StatelessWidget {
  final List<Customer> customers;
  const _CustomerPickerSheet({required this.customers});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.l10n.selectCustomer,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
        ),
        Divider(color: c.divider),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customers.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.3),
                child: Text(customers[i].name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white)),
              ),
              title: Text(customers[i].name,
                  style: TextStyle(color: c.textPrimary)),
              subtitle: Text(customers[i].phone ?? '',
                  style: TextStyle(
                      color: c.textSecondary)),
              onTap: () => Navigator.pop(context, customers[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── PTT Live Transcript Overlay ───────────────────────────────────────────────

class _PTTOverlay extends StatelessWidget {
  final String transcript;
  final bool isProcessing;

  const _PTTOverlay({
    super.key,
    required this.transcript,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryLight.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isProcessing
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI is analyzing...',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.mic_rounded, color: AppColors.primaryLight, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Listening...',
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      if (transcript.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          transcript,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
