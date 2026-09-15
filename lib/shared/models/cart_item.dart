import 'product.dart';

class CartItem {
  final Product product;
  int quantity;
  double? overridePrice;

  CartItem({required this.product, this.quantity = 1, this.overridePrice});

  double get effectivePrice => overridePrice ?? product.sellingPrice;
  double get lineTotal => effectivePrice * quantity;
  double get gstAmount => lineTotal * product.gstRate / 100;
  double get lineTotalWithGst => lineTotal + gstAmount;

  CartItem copyWith({int? quantity, double? overridePrice, bool clearPrice = false}) =>
      CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        overridePrice: clearPrice ? null : (overridePrice ?? this.overridePrice),
      );
}
