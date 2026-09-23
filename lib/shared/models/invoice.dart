import 'item.dart';

class InvoiceItem {
  final int? id;
  final int invoiceId;
  final int itemId;
  final String itemName;
  // Snapshotted at sale time, same reasoning as costPrice below — a bill
  // stays historically accurate even if the item is later retyped (e.g.
  // product → service) or deleted. Defaults to product: every line ever
  // created before this field existed really was a physical product.
  final ItemType itemType;
  final int quantity;
  final double sellingPrice;
  final double gstRate;
  final double gstAmount;
  final double lineTotal;
  // How many of [quantity] have already been reversed via a return or void.
  final int returnedQuantity;
  // Item cost at the time of sale — snapshotted so profit reports and
  // later void/return reversals stay accurate even if the item's cost is
  // edited afterwards.
  final double costPrice;

  const InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.itemId,
    required this.itemName,
    this.itemType = ItemType.product,
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
        'item_id': itemId,
        'item_name': itemName,
        'item_type': itemType.dbValue,
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
        itemId: map['item_id'] as int,
        itemName: map['item_name'] as String,
        itemType: ItemType.fromDbValue(map['item_type'] as String?),
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
  // Whether this invoice was created via voice billing — see
  // InvoiceRepository.countVoiceInvoices() and the Basic plan's
  // 50-voice-invoice cap. Never set by any path other than checkout
  // actually originating from a voice-populated cart, so a manually built
  // invoice never accidentally counts against it.
  final bool isVoiceCreated;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<InvoiceItem> items;
  // Display-only, not a stored column — populated by
  // InvoiceRepository.getInvoicesByShopWithItemCounts() via a COUNT
  // subquery so list screens can show "N items" without loading full line
  // items (or an N+1 query) for every row. Null anywhere else, including
  // after toMap()/fromMap() round-trips through the normal invoices table.
  final int? itemCount;

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
    this.isVoiceCreated = false,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.itemCount,
  });

  // deleted_at is deliberately excluded — see the matching note on
  // Item.toMap(). It's written only by InvoiceRepository.upsertFromCloud().
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
        'is_voice_created': isVoiceCreated ? 1 : 0,
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
        isVoiceCreated: (map['is_voice_created'] as int? ?? 0) == 1,
        itemCount: map['item_count'] as int?,
        deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
        items: items,
      );
}
