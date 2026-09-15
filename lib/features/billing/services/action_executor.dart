import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/product.dart';
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

    final cartNotifier = ref.read(cartProvider.notifier);

    for (final action in actions) {
      switch (action) {
        case SetQuantityAction():
          final currentCart = ref.read(cartProvider);
          final inCart =
              currentCart.any((c) => c.product.id == action.productId);
          if (inCart) {
            cartNotifier.updateQuantity(action.productId, action.quantity);
          } else {
            final product = productsById[action.productId];
            if (product != null) {
              cartNotifier.addProduct(product, qty: action.quantity);
            } else {
              errors.add('Product not found: ${action.productName}');
              break;
            }
          }
          messages.add('${action.productName} × ${action.quantity}');
          if (action.inventoryWarning) {
            warnings.add('Low stock: ${action.productName}');
          }

        case IncreaseQuantityAction():
          final cart = ref.read(cartProvider);
          final existing =
              cart.where((c) => c.product.id == action.productId).firstOrNull;
          if (existing == null) {
            // Not in cart — add via addProduct
            final product = productsById[action.productId];
            if (product != null) {
              cartNotifier.addProduct(product, qty: action.delta);
              messages.add('${action.productName} × ${action.delta} added');
            } else {
              errors.add('${action.productName} not found');
            }
          } else {
            final newQty = existing.quantity + action.delta;
            cartNotifier.updateQuantity(action.productId, newQty);
            messages.add(
                '${action.productName}: ${existing.quantity} → $newQty');
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
                '${action.productName} price → ₹${action.price.toStringAsFixed(0)}');
          }

        case DiscountAction():
          discountChanged = true;
          newDiscountType = action.discountType;
          newDiscountValue = action.value;
          final label = action.discountType == 'percent'
              ? '${action.value.toStringAsFixed(0)}%'
              : '₹${action.value.toStringAsFixed(0)}';
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
