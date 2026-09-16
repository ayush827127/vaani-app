import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/cart_item.dart';

// ── VoiceAction sealed hierarchy ──────────────────────────────────────────────

sealed class VoiceAction {
  const VoiceAction();
}

final class SetQuantityAction extends VoiceAction {
  final int productId;
  final String productName;
  final int quantity;
  final bool inventoryWarning;
  const SetQuantityAction({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.inventoryWarning = false,
  });
}

final class IncreaseQuantityAction extends VoiceAction {
  final int productId;
  final String productName;
  final int delta;
  const IncreaseQuantityAction({
    required this.productId,
    required this.productName,
    required this.delta,
  });
}

final class DecreaseQuantityAction extends VoiceAction {
  final int productId;
  final String productName;
  final int delta;
  const DecreaseQuantityAction({
    required this.productId,
    required this.productName,
    required this.delta,
  });
}

final class RemoveItemAction extends VoiceAction {
  final int productId;
  final String productName;
  const RemoveItemAction({required this.productId, required this.productName});
}

final class ClearCartAction extends VoiceAction {
  const ClearCartAction();
}

final class UpdatePriceAction extends VoiceAction {
  final int productId;
  final String productName;
  final double price;
  const UpdatePriceAction({
    required this.productId,
    required this.productName,
    required this.price,
  });
}

final class DiscountAction extends VoiceAction {
  final String discountType; // 'percent' | 'flat'
  final double value;
  const DiscountAction({required this.discountType, required this.value});
}

final class PaymentModeAction extends VoiceAction {
  final String mode; // 'cash' | 'upi' | 'card' | 'credit'
  const PaymentModeAction({required this.mode});
}

final class SelectCustomerAction extends VoiceAction {
  final int customerId;
  final String customerName;
  const SelectCustomerAction({
    required this.customerId,
    required this.customerName,
  });
}

final class CustomerNotFoundAction extends VoiceAction {
  final String name;
  final String? phone;
  const CustomerNotFoundAction({required this.name, this.phone});
}

final class UnknownProductAction extends VoiceAction {
  final String rawName;
  const UnknownProductAction({required this.rawName});
}

final class UnknownAction extends VoiceAction {
  final String message;
  const UnknownAction({required this.message});
}

// ── BillingContext ─────────────────────────────────────────────────────────────

class BillingContext {
  final List<Product> products;
  final List<Customer> customers;
  final List<CartItem> cartItems;
  final String paymentMode;
  final String discountType;
  final double discountValue;
  final String? customerName;

  const BillingContext({
    required this.products,
    required this.customers,
    required this.cartItems,
    required this.paymentMode,
    required this.discountType,
    required this.discountValue,
    this.customerName,
  });
}

// ── VoiceParseResult ───────────────────────────────────────────────────────────

class VoiceParseResult {
  final List<VoiceAction> actions;
  final String? failureReason;

  const VoiceParseResult({required this.actions, this.failureReason});

  bool get succeeded => failureReason == null && actions.isNotEmpty;
}

// ── VoiceActionParser ──────────────────────────────────────────────────────────

class VoiceActionParser {
  static const _tag = '[VoiceParser]';

  final String _backendBaseUrl;
  final String _shopToken;
  final http.Client _client;

  /// [backendBaseUrl] is `BACKEND_API_BASE_URL` and [shopToken] is the cached
  /// shop backend token — the LLM call is proxied through our own backend so
  /// the provider API key never ships inside the app.
  VoiceActionParser(this._backendBaseUrl, this._shopToken) : _client = http.Client();

  /// The backend and its database both run on free-tier hosts that idle-sleep
  /// after a few minutes and take a few seconds to wake — the very first
  /// request after a lull can come back as a transient 5xx while the shop's
  /// connection pool is still spinning up, even though the service is
  /// healthy moments later. One silent retry papers over exactly that case
  /// without changing what the user sees for a real (non-transient) failure.
  Future<http.Response> _postWithRetry(String endpoint, String prompt) async {
    Future<http.Response> attempt() => _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $_shopToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'prompt': prompt}),
        )
        .timeout(const Duration(seconds: 25));

    debugPrint('$_tag POST $endpoint  timeout=25s');
    var sw = Stopwatch()..start();
    var response = await attempt();
    debugPrint('$_tag HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');

    if (response.statusCode >= 500) {
      debugPrint('$_tag transient ${response.statusCode}, retrying once after backend wake-up delay');
      await Future.delayed(const Duration(seconds: 3));
      sw = Stopwatch()..start();
      response = await attempt();
      debugPrint('$_tag retry HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms');
    }

    debugPrint('$_tag ─── RAW RESPONSE BODY ───────────────────────────');
    _logChunked(response.body);
    debugPrint('$_tag ─── END RESPONSE ────────────────────────────────');
    return response;
  }

  Future<VoiceParseResult> parse(
    String transcript,
    BillingContext context,
  ) async {
    debugPrint('$_tag ═══ parse() ════════════════════════════════════════');
    debugPrint('$_tag transcript (${transcript.length} chars): "$transcript"');
    debugPrint('$_tag catalog: ${context.products.length} products, cart: ${context.cartItems.length} items');

    if (transcript.trim().isEmpty) {
      debugPrint('$_tag FAIL [empty-transcript]');
      return const VoiceParseResult(
        actions: [],
        failureReason: '[empty-transcript] STT returned no text.',
      );
    }
    if (context.products.isEmpty) {
      return const VoiceParseResult(
        actions: [],
        failureReason: '[empty-catalog] No products in catalog — add products first.',
      );
    }

    final prompt = _buildPrompt(transcript, context);
    debugPrint('$_tag ─── PROMPT (${prompt.length} chars) ───────────────');
    _logChunked(prompt);
    debugPrint('$_tag ─── END PROMPT ─────────────────────────────────────');

    final endpoint = '$_backendBaseUrl/api/shop/voice/parse';
    String rawText;
    try {
      final response = await _postWithRetry(endpoint, prompt);

      if (response.statusCode != 200) {
        String hint = '';
        if (response.statusCode == 401) hint = 'Shop not linked to backend yet.';
        if (response.statusCode == 429) hint = 'Rate limit exceeded.';
        if (response.statusCode == 504) hint = 'Voice AI timed out.';
        return VoiceParseResult(
          actions: [],
          failureReason: '[http-${response.statusCode}] $hint ${response.body}',
        );
      }

      final envelope = jsonDecode(response.body) as Map<String, dynamic>;
      rawText = (envelope['data']?['text'] as String?)?.trim() ?? '';
      debugPrint('$_tag content (${rawText.length} chars): "$rawText"');
    } on TimeoutException catch (e, st) {
      debugPrint('$_tag FAIL [voice-timeout]: $e\n$st');
      return const VoiceParseResult(
        actions: [],
        failureReason: '[voice-timeout] Voice AI did not respond within 25 seconds.',
      );
    } catch (e, st) {
      debugPrint('$_tag FAIL [voice-api]: ${e.runtimeType}: $e\n$st');
      return VoiceParseResult(
        actions: [],
        failureReason: '[voice-api] ${e.runtimeType}: $e',
      );
    }

    if (rawText.isEmpty) {
      return const VoiceParseResult(
        actions: [],
        failureReason: '[groq-empty] Groq returned an empty response.',
      );
    }

    // Strip markdown fences
    var text = rawText;
    if (text.startsWith('```')) {
      text = text
          .replaceAll(RegExp(r'^```\w*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
      debugPrint('$_tag stripped markdown fences → "$text"');
    }

    List<dynamic> jsonList;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        return VoiceParseResult(
          actions: [],
          failureReason:
              '[json-not-array] AI returned ${decoded.runtimeType} instead of a JSON array.',
        );
      }
      jsonList = decoded;
      debugPrint('$_tag JSON decoded OK — ${jsonList.length} action(s)');
    } catch (e, st) {
      debugPrint('$_tag FAIL [json-parse]: $e\n$st');
      return VoiceParseResult(
        actions: [],
        failureReason: '[json-parse] AI returned invalid JSON: $e',
      );
    }

    if (jsonList.isEmpty) {
      return const VoiceParseResult(
        actions: [],
        failureReason: '[no-actions] AI returned no actions.',
      );
    }

    final actions = <VoiceAction>[];
    for (var i = 0; i < jsonList.length; i++) {
      if (jsonList[i] is! Map<String, dynamic>) continue;
      final item = jsonList[i] as Map<String, dynamic>;
      debugPrint('$_tag action[$i]: $item');
      final action = _parseAction(item, context);
      if (action != null) actions.add(action);
    }

    debugPrint('$_tag ─── RESULT: ${actions.length} valid action(s) ───');

    if (actions.isEmpty) {
      return const VoiceParseResult(
        actions: [],
        failureReason: '[no-valid-actions] No valid actions could be parsed.',
      );
    }

    return VoiceParseResult(actions: actions);
  }

  VoiceAction? _parseAction(Map<String, dynamic> item, BillingContext ctx) {
    final type = item['action']?.toString() ?? '';
    debugPrint('$_tag   type="$type"');

    switch (type) {
      case 'set_quantity':
      case 'increase_quantity':
      case 'decrease_quantity':
      case 'remove_item':
        final productName = item['product']?.toString() ?? '';
        final product = _findProduct(productName, ctx.products);
        if (product == null) {
          debugPrint('$_tag   product not found: "$productName"');
          return UnknownProductAction(rawName: productName);
        }
        if (type == 'remove_item') {
          return RemoveItemAction(productId: product.id!, productName: product.name);
        }
        final qty = _parseInt(item['quantity'] ?? item['delta']);
        if (type == 'set_quantity') {
          final hasWarning =
              product.stockQuantity > 0 && qty > product.stockQuantity;
          return SetQuantityAction(
            productId: product.id!,
            productName: product.name,
            quantity: qty.clamp(1, 9999),
            inventoryWarning: hasWarning,
          );
        }
        if (type == 'increase_quantity') {
          return IncreaseQuantityAction(
            productId: product.id!,
            productName: product.name,
            delta: qty.clamp(1, 9999),
          );
        }
        // decrease_quantity
        return DecreaseQuantityAction(
          productId: product.id!,
          productName: product.name,
          delta: qty.clamp(1, 9999),
        );

      case 'clear_cart':
        return const ClearCartAction();

      case 'update_price':
        final productName = item['product']?.toString() ?? '';
        final product = _findProduct(productName, ctx.products);
        if (product == null) return UnknownProductAction(rawName: productName);
        final price = _parseDouble(item['price']);
        if (price <= 0) return null;
        return UpdatePriceAction(
          productId: product.id!,
          productName: product.name,
          price: price,
        );

      case 'discount':
        final discountType = item['discount_type']?.toString() ?? 'percent';
        final value = _parseDouble(item['value']);
        return DiscountAction(
          discountType: discountType == 'flat' ? 'flat' : 'percent',
          value: value,
        );

      case 'payment_mode':
        final mode = _normalizePaymentMode(item['mode']?.toString() ?? '');
        return PaymentModeAction(mode: mode);

      case 'select_customer':
      case 'customer_not_found':
        final nameOrPhone = item['name']?.toString() ?? '';
        final phone = item['phone']?.toString() ?? '';
        if (type == 'select_customer') {
          Customer? customer;
          if (phone.isNotEmpty) {
            customer = ctx.customers
                .where((c) => c.phone == phone)
                .firstOrNull;
          }
          customer ??= _findCustomer(nameOrPhone, ctx.customers);
          if (customer != null) {
            return SelectCustomerAction(
              customerId: customer.id!,
              customerName: customer.name,
            );
          }
        }
        return CustomerNotFoundAction(
          name: nameOrPhone.isNotEmpty ? nameOrPhone : phone,
          phone: phone.isNotEmpty ? phone : null,
        );

      case 'unknown_product':
        return UnknownProductAction(
            rawName: item['product']?.toString() ?? '');

      default:
        debugPrint('$_tag   unknown action type: "$type"');
        return UnknownAction(
          message: item['message']?.toString() ?? 'Unknown: $type',
        );
    }
  }

  String _buildPrompt(String transcript, BillingContext ctx) {
    final productCatalog = ctx.products.map((p) {
      final aliases = p.aliases.isNotEmpty ? p.aliases.join(', ') : '-';
      final stock =
          p.stockQuantity > 0 ? 'stock=${p.stockQuantity}' : 'stock=unlimited';
      return '  id=${p.id} name="${p.name}" aliases="$aliases" price=${p.sellingPrice} $stock';
    }).join('\n');

    final cartStr = ctx.cartItems.isEmpty
        ? '  (empty)'
        : ctx.cartItems
            .map((c) =>
                '  id=${c.product.id} name="${c.product.name}" qty=${c.quantity} price=${c.effectivePrice}')
            .join('\n');

    final customerStr = ctx.customers.isEmpty
        ? '  (none)'
        : ctx.customers
            .map((c) =>
                '  id=${c.id} name="${c.name}" phone="${c.phone ?? ""}"')
            .join('\n');

    return '''You are a smart billing assistant for an Indian kirana/retail store. Convert the shopkeeper's spoken command into a JSON array of billing actions.

SPOKEN COMMAND: "$transcript"

CURRENT CART:
$cartStr

PAYMENT MODE: ${ctx.paymentMode}
DISCOUNT: ${ctx.discountType == 'none' ? 'none' : '${ctx.discountValue} ${ctx.discountType}'}
CUSTOMER: ${ctx.customerName ?? '(none)'}

PRODUCT CATALOG:
$productCatalog

CUSTOMERS:
$customerStr

LANGUAGE: Command may be in Hindi (Devanagari script), Roman transliteration, English, or mixed.
Hindi numbers in Devanagari: एक=1, दो=2, तीन=3, चार=4, पाँच=5, छह=6, सात=7, आठ=8, नौ=9, दस=10, बीस=20
Hindi numbers in Roman: ek=1, do=2, teen=3, char/chaar=4, paanch=5, chhe=6, saat=7, aath=8, nau=9, das=10
Ignore fillers: लेना, देना, दीजिए, मुझे, wala, please (but "aur" = "more of")

CRITICAL RULES:
1. "2 Pepsi" or "दो Pepsi" → set_quantity qty=2 (ABSOLUTE SET, even if already in cart — last qty wins)
2. "2 aur Pepsi" or "2 more Pepsi" or "2 और Pepsi" → increase_quantity delta=2 (add to existing)
3. Multiple items → multiple actions in the array
4. Product not in catalog → unknown_product
5. Payment: "cash"/"nakad"/"नकद" → cash, "gpay"/"paytm"/"phonepe"/"upi" → upi, "card"/"swipe" → card, "udhar"/"credit"/"उधार" → credit
6. "sab hatao"/"clear karo"/"saaf karo"/"सब हटाओ" → clear_cart
7. Price update: "Pepsi 20 rupay" or "20 ka Pepsi" → update_price (price only, no quantity)
   COMBINED quantity + price: when the command mentions BOTH a quantity AND a price for the same product,
   emit TWO separate actions — set_quantity first, then update_price — for that product.
   Price markers: rupay / rupaye / rs / rupees / ₹ and connectors se / mein / ka / wala signal a price.
   Example: "do Pepsi 40 rupay mein" → set_quantity(Pepsi,2) + update_price(Pepsi,40)
   Example: "Pepsi 40rs se do pcs" → set_quantity(Pepsi,2) + update_price(Pepsi,40)
   Example: "teen Coke 30 ka"       → set_quantity(Coke,3)  + update_price(Coke,30)
8. Discount: "10 percent off" or "50 rupay discount" → discount action
9. Customer selection: name/phone mentioned → select_customer (find from customer list) or customer_not_found
10. Only include actions with high confidence (>0.6)

AVAILABLE ACTION TYPES:
set_quantity: {"action":"set_quantity","product":"<EXACT name from catalog>","quantity":<int>}
increase_quantity: {"action":"increase_quantity","product":"<EXACT name from catalog>","delta":<int>}
decrease_quantity: {"action":"decrease_quantity","product":"<EXACT name from catalog>","delta":<int>}
remove_item: {"action":"remove_item","product":"<EXACT name from catalog>"}
clear_cart: {"action":"clear_cart"}
update_price: {"action":"update_price","product":"<EXACT name from catalog>","price":<float>}
discount: {"action":"discount","discount_type":"percent"|"flat","value":<float>}
payment_mode: {"action":"payment_mode","mode":"cash"|"upi"|"card"|"credit"}
select_customer: {"action":"select_customer","name":"<spoken name>","phone":"<spoken phone or empty string>"}
customer_not_found: {"action":"customer_not_found","name":"<name>","phone":"<phone or empty string>"}
unknown_product: {"action":"unknown_product","product":"<spoken name>"}
unknown: {"action":"unknown","message":"<what was unclear>"}

COMBINED COMMAND EXAMPLES (quantity + price in one utterance — always two actions):
"do Pepsi 40 rupay mein"  → [{"action":"set_quantity","product":"Pepsi","quantity":2},{"action":"update_price","product":"Pepsi","price":40}]
"Pepsi 40rs se do pcs"    → [{"action":"set_quantity","product":"Pepsi","quantity":2},{"action":"update_price","product":"Pepsi","price":40}]
"teen Coke 30 ka"         → [{"action":"set_quantity","product":"Coke","quantity":3},{"action":"update_price","product":"Coke","price":30}]
"ek namak 18 rupay"       → [{"action":"set_quantity","product":"Namak","quantity":1},{"action":"update_price","product":"Namak","price":18}]

IMPORTANT: Product field must contain the EXACT name from the catalog above (copy verbatim). Do NOT invent product names.

Return ONLY a JSON array, no markdown, no backticks, no explanation:
[{"action":"...","product":"...","quantity":...}]''';
  }

  Product? _findProduct(String name, List<Product> products) {
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return null;
    for (final p in products) {
      if (p.name.toLowerCase() == lower) return p;
    }
    for (final p in products) {
      if (p.aliases.any((a) => a.toLowerCase() == lower)) return p;
    }
    for (final p in products) {
      final pn = p.name.toLowerCase();
      if (pn.contains(lower) || lower.contains(pn)) return p;
    }
    for (final p in products) {
      if (p.aliases.any((a) {
        final al = a.toLowerCase();
        return al.contains(lower) || lower.contains(al);
      })) {
        return p;
      }
    }
    return null;
  }

  Customer? _findCustomer(String query, List<Customer> customers) {
    final lower = query.toLowerCase().trim();
    if (lower.isEmpty) return null;
    for (final c in customers) {
      if (c.name.toLowerCase() == lower) return c;
    }
    for (final c in customers) {
      final cn = c.name.toLowerCase();
      if (cn.contains(lower) || lower.contains(cn)) return c;
    }
    return null;
  }

  String _normalizePaymentMode(String raw) {
    final lower = raw.toLowerCase();
    if (['cash', 'nakad', 'नकद'].any((s) => lower.contains(s))) return 'cash';
    if (['gpay', 'paytm', 'phonepe', 'bhim', 'upi', 'google pay']
        .any((s) => lower.contains(s))) {
      return 'upi';
    }
    if (['card', 'debit', 'swipe'].any((s) => lower.contains(s))) return 'card';
    if (['udhar', 'credit', 'उधार'].any((s) => lower.contains(s))) {
      return 'credit';
    }
    return 'upi';
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 1;
    return 1;
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static void _logChunked(String text) {
    const chunkSize = 900;
    for (var i = 0; i < text.length; i += chunkSize) {
      debugPrint(text.substring(i, (i + chunkSize).clamp(0, text.length)));
    }
  }
}
