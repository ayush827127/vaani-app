class InvoiceItem {
  final int? id;
  final int invoiceId;
  final int productId;
  final String productName;
  final int quantity;
  final double sellingPrice;
  final double gstRate;
  final double gstAmount;
  final double lineTotal;
  // How many of [quantity] have already been reversed via a return or void.
  final int returnedQuantity;
  // Product cost at the time of sale — snapshotted so profit reports and
  // later void/return reversals stay accurate even if the product's cost is
  // edited afterwards.
  final double costPrice;

  const InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.sellingPrice,
    this.gstRate = 0,
    this.gstAmount = 0,
    required this.lineTotal,
    this.returnedQuantity = 0,
    this.costPrice = 0,
  });

  int get remainingQuantity => quantity - returnedQuantity;

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_id': invoiceId,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'selling_price': sellingPrice,
        'gst_rate': gstRate,
        'gst_amount': gstAmount,
        'line_total': lineTotal,
        'returned_quantity': returnedQuantity,
        'cost_price': costPrice,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        id: map['id'] as int?,
        invoiceId: map['invoice_id'] as int,
        productId: map['product_id'] as int,
        productName: map['product_name'] as String,
        quantity: map['quantity'] as int,
        sellingPrice: (map['selling_price'] as num).toDouble(),
        gstRate: (map['gst_rate'] as num?)?.toDouble() ?? 0,
        gstAmount: (map['gst_amount'] as num?)?.toDouble() ?? 0,
        lineTotal: (map['line_total'] as num).toDouble(),
        returnedQuantity: map['returned_quantity'] as int? ?? 0,
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      );
}

class Invoice {
  final int? id;
  final String invoiceNumber;
  final int shopId;
  final int? customerId;
  final String customerName;
  final double subtotal;
  final String discountType;
  final double discountValue;
  final double discountAmount;
  final double gstAmount;
  final double grandTotal;
  final double receivedAmount;
  final double pendingAmount;
  final String paymentMode;
  final String status;
  final String? notes;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<InvoiceItem> items;

  const Invoice({
    this.id,
    required this.invoiceNumber,
    required this.shopId,
    this.customerId,
    this.customerName = 'Walk-in Customer',
    required this.subtotal,
    this.discountType = 'none',
    this.discountValue = 0,
    this.discountAmount = 0,
    this.gstAmount = 0,
    required this.grandTotal,
    this.receivedAmount = 0,
    this.pendingAmount = 0,
    this.paymentMode = 'cash',
    this.status = 'paid',
    this.notes,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  // deleted_at is deliberately excluded — see the matching note on
  // Product.toMap(). It's written only by InvoiceRepository.upsertFromCloud().
  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'shop_id': shopId,
        'customer_id': customerId,
        'customer_name': customerName,
        'subtotal': subtotal,
        'discount_type': discountType,
        'discount_value': discountValue,
        'discount_amount': discountAmount,
        'gst_amount': gstAmount,
        'grand_total': grandTotal,
        'received_amount': receivedAmount,
        'pending_amount': pendingAmount,
        'payment_mode': paymentMode,
        'status': status,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': (updatedAt ?? createdAt).toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> map, {List<InvoiceItem> items = const []}) => Invoice(
        id: map['id'] as int?,
        invoiceNumber: map['invoice_number'] as String,
        shopId: map['shop_id'] as int,
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String? ?? 'Walk-in Customer',
        subtotal: (map['subtotal'] as num).toDouble(),
        discountType: map['discount_type'] as String? ?? 'none',
        discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
        discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
        gstAmount: (map['gst_amount'] as num?)?.toDouble() ?? 0,
        grandTotal: (map['grand_total'] as num).toDouble(),
        receivedAmount: (map['received_amount'] as num?)?.toDouble() ?? 0,
        pendingAmount: (map['pending_amount'] as num?)?.toDouble() ?? 0,
        paymentMode: map['payment_mode'] as String? ?? 'cash',
        status: map['status'] as String? ?? 'paid',
        notes: map['notes'] as String?,
        deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
        items: items,
      );
}
