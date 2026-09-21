import '../../../core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/product.dart';
import '../providers/billing_providers.dart';
import '../screens/billing_screen.dart';
import 'voice_action_parser.dart';

class ActionExecutionResult {
  final List<String> messages;
  final List<String> warnings;
  final List<String> errors;
  final bool shouldShowCustomerDialog;
  final CustomerNotFoundAction? customerNotFoundAction;
  final bool discountChanged;
  final String? newDiscountType;
  final double? newDiscountValue;
  final bool paymentModeChanged;
  final String? newPaymentMode;
  final bool customerChanged;
  final int? newCustomerId;
  final String? newCustomerName;

  const ActionExecutionResult({
    this.messages = const [],
    this.warnings = const [],
    this.errors = const [],
    this.shouldShowCustomerDialog = false,
    this.customerNotFoundAction,
    this.discountChanged = false,
    this.newDiscountType,
    this.newDiscountValue,
    this.paymentModeChanged = false,
    this.newPaymentMode,
    this.customerChanged = false,
    this.newCustomerId,
    this.newCustomerName,
  });
}

class ActionExecutor {
  final WidgetRef ref;
  final Map<int, Product> productsById;

  const ActionExecutor({required this.ref, required this.productsById});

  ActionExecutionResult execute(List<VoiceAction> actions) {
    final messages = <String>[];
    final warnings = <String>[];
    final errors = <String>[];
    bool shouldShowCustomerDialog = false;
    CustomerNotFoundAction? customerNotFoundAction;
    bool discountChanged = false;
    String? newDiscountType;
    double? newDiscountValue;
    bool paymentModeChanged = false;
    String? newPaymentMode;
    bool customerChanged = false;
    int? newCustomerId;
    String? newCustomerName;

    // Marks the cart as voice-touched if this batch does anything to its
    // contents — checked once up front rather than per-case so it covers
    // every cart-mutating action the same way, and only those (a discount
    // or payment-mode-only voice command doesn't touch line items, so it
    // doesn't mark the eventual invoice as voice-created on its own).
    final touchesCart = actions.any((a) =>
        a is SetQuantityAction ||
        a is IncreaseQuantityAction ||
        a is DecreaseQuantityAction ||
        a is RemoveItemAction ||
        a is ClearCartAction ||
        a is UpdatePriceAction);
    if (touchesCart) {
      ref.read(cartVoiceOriginProvider.notifier).state = true;
    }

    final cartNotifier = ref.read(cartProvider.notifier);

    for (final action in actions) {
      switch (action) {
        case SetQuantityAction():
          final product = productsById[action.productId];
          if (product == null) {
            errors.add('Product not found: ${action.productName}');
            break;
          }
          // Manual +/- tapping in the cart hard-clamps to available stock
          // (see billing_screen.dart's _increaseQty); this used to only set
          // a soft `inventoryWarning` flag and apply the parsed quantity
          // unclamped, so a misheard number ("do" heard as a higher count)
          // could check out with more units than the shop actually has —
          // clamping here at execution time (not just at parse time, where
          // the stock snapshot can be a moment stale) closes that gap.
          final requestedQty = action.quantity;
          final clampedQty =
              product.stockQuantity > 0 ? requestedQty.clamp(1, product.stockQuantity) : 0;
          if (clampedQty == 0) {
            errors.add('${action.productName} is out of stock');
            break;
          }
          final currentCart = ref.read(cartProvider);
          final inCart =
              currentCart.any((c) => c.product.id == action.productId);
          if (inCart) {
            cartNotifier.updateQuantity(action.productId, clampedQty);
          } else {
            cartNotifier.addProduct(product, qty: clampedQty);
          }
          messages.add('${action.productName} × $clampedQty');
          if (clampedQty < requestedQty) {
            warnings.add(
                '${action.productName}: only ${product.stockQuantity} in stock, set to $clampedQty');
          }

        case IncreaseQuantityAction():
          final product = productsById[action.productId];
          if (product == null) {
            errors.add('${action.productName} not found');
            break;
          }
          final cart = ref.read(cartProvider);
          final existing =
              cart.where((c) => c.product.id == action.productId).firstOrNull;
          final currentQty = existing?.quantity ?? 0;
          final requestedQty = currentQty + action.delta;
          // Same stock clamp as SetQuantityAction above — this path had no
          // inventory check at all before, soft or otherwise.
          final clampedQty =
              product.stockQuantity > 0 ? requestedQty.clamp(1, product.stockQuantity) : 0;
          if (clampedQty == 0) {
            errors.add('${action.productName} is out of stock');
            break;
          }
          if (existing == null) {
            cartNotifier.addProduct(product, qty: clampedQty);
            messages.add('${action.productName} × $clampedQty added');
          } else {
            cartNotifier.updateQuantity(action.productId, clampedQty);
            messages.add('${action.productName}: $currentQty → $clampedQty');
          }
          if (clampedQty < requestedQty) {
            warnings.add(
                '${action.productName}: capped at available stock (${product.stockQuantity})');
          }

        case DecreaseQuantityAction():
          final cart = ref.read(cartProvider);
          final existing =
              cart.where((c) => c.product.id == action.productId).firstOrNull;
          if (existing == null) {
            errors.add('${action.productName} is not in cart');
          } else {
            final newQty = existing.quantity - action.delta;
            cartNotifier.updateQuantity(action.productId, newQty);
            if (newQty <= 0) {
              messages.add('${action.productName} removed');
            } else {
              messages.add(
                  '${action.productName}: ${existing.quantity} → $newQty');
            }
          }

        case RemoveItemAction():
          cartNotifier.removeProduct(action.productId);
          messages.add('${action.productName} removed');

        case ClearCartAction():
          cartNotifier.clear();
          messages.add('Cart cleared');

        case UpdatePriceAction():
          final cart = ref.read(cartProvider);
          final inCart =
              cart.any((c) => c.product.id == action.productId);
          if (!inCart) {
            errors.add('${action.productName} is not in cart (add it first)');
          } else {
            cartNotifier.updatePrice(action.productId, action.price);
            messages.add(
                '${action.productName} price → ${AppFormatters.formatCurrency(action.price)}');
          }

        case DiscountAction():
          discountChanged = true;
          newDiscountType = action.discountType;
          newDiscountValue = action.value;
          final label = action.discountType == 'percent'
              ? '${action.value.toStringAsFixed(0)}%'
              : AppFormatters.formatCurrency(action.value);
          messages.add('Discount: $label');

        case PaymentModeAction():
          paymentModeChanged = true;
          newPaymentMode = action.mode;
          messages.add('Payment: ${action.mode.toUpperCase()}');

        case SelectCustomerAction():
          customerChanged = true;
          newCustomerId = action.customerId;
          newCustomerName = action.customerName;
          messages.add('Customer: ${action.customerName}');

        case CustomerNotFoundAction():
          shouldShowCustomerDialog = true;
          customerNotFoundAction = action;

        case UnknownProductAction():
          errors.add('Product not found: "${action.rawName}"');

        case UnknownAction():
          errors.add('Not understood: ${action.message}');
      }
    }

    return ActionExecutionResult(
      messages: messages,
      warnings: warnings,
      errors: errors,
      shouldShowCustomerDialog: shouldShowCustomerDialog,
      customerNotFoundAction: customerNotFoundAction,
      discountChanged: discountChanged,
      newDiscountType: newDiscountType,
      newDiscountValue: newDiscountValue,
      paymentModeChanged: paymentModeChanged,
      newPaymentMode: newPaymentMode,
      customerChanged: customerChanged,
      newCustomerId: newCustomerId,
      newCustomerName: newCustomerName,
    );
  }
}
