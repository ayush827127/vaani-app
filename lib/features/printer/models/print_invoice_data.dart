class PrintLineItem {
  final String name;
  final int quantity;
  final double price;
  final double total;

  const PrintLineItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });
}

class PrintInvoiceData {
  final String shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String? shopGstNumber;
  final String? customerName;
  final String? customerPhone;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final List<PrintLineItem> items;
  final double subtotal;
  final double gstAmount;
  final double discountAmount;
  final double grandTotal;
  final String paymentMode;
  final String? upiId;

  const PrintInvoiceData({
    required this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.shopGstNumber,
    this.customerName,
    this.customerPhone,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.items,
    required this.subtotal,
    required this.gstAmount,
    required this.discountAmount,
    required this.grandTotal,
    required this.paymentMode,
    this.upiId,
  });
}
