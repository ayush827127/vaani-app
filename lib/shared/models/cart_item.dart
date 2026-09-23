import 'item.dart';

class CartItem {
  final Item item;
  int quantity;
  double? overridePrice;

  CartItem({required this.item, this.quantity = 1, this.overridePrice});

  double get effectivePrice => overridePrice ?? item.sellingPrice;
  double get lineTotal => effectivePrice * quantity;
  double get gstAmount => lineTotal * item.gstRate / 100;
  double get lineTotalWithGst => lineTotal + gstAmount;

  CartItem copyWith({int? quantity, double? overridePrice, bool clearPrice = false}) =>
      CartItem(
        item: item,
        quantity: quantity ?? this.quantity,
        overridePrice: clearPrice ? null : (overridePrice ?? this.overridePrice),
      );
}
