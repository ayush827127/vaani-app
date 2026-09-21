class PaymentTransaction {
  final int? id;
  final int shopId;
  final int customerId;
  final int? invoiceId;

  // 'bill_payment'       — cash/UPI/card against a new invoice at checkout
  // 'advance_used'       — advance balance applied to an invoice
  // 'outstanding_collection' — payment collected later against a specific
  //                            invoice's remaining due (invoiceId set)
  // 'advance_deposit'    — customer pre-pays without a specific bill
  // 'refund'             — money already collected for an invoice is handed
  //                        back onto the customer's advance balance after a
  //                        void or return shrinks what's actually owed
  // 'manual_credit'      — khata-style "You Gave": goods/cash given to the
  //                        customer on credit with no formal invoice
  //                        (give_credit_sheet.dart)
  // 'invoice_due'        — the pending (unpaid) portion of a new invoice,
  //                        recorded at creation so the customer ledger's
  //                        running balance can be reconstructed from this
  //                        table alone, without re-reading every invoice
  // 'invoice_due_reversal' — write-off of an 'invoice_due' row when a void/
  //                        return shrinks or clears that due before payment
  final String type;

  final double amount;
  final String paymentMode;
  final String? notes;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PaymentTransaction({
    this.id,
    required this.shopId,
    required this.customerId,
    this.invoiceId,
    required this.type,
    required this.amount,
    required this.paymentMode,
    this.notes,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
  });

  // deleted_at is deliberately excluded — see the matching note on
  // Product.toMap(). It's written only by
  // PaymentTransactionRepository.upsertFromCloud().
  Map<String, dynamic> toMap() => {
        'id': id,
        'shop_id': shopId,
        'customer_id': customerId,
        'invoice_id': invoiceId,
        'type': type,
        'amount': amount,
        'payment_mode': paymentMode,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': (updatedAt ?? createdAt).toIso8601String(),
      };

  factory PaymentTransaction.fromMap(Map<String, dynamic> map) =>
      PaymentTransaction(
        id: map['id'] as int?,
        shopId: map['shop_id'] as int,
        customerId: map['customer_id'] as int,
        invoiceId: map['invoice_id'] as int?,
        type: map['type'] as String,
        amount: (map['amount'] as num).toDouble(),
        paymentMode: map['payment_mode'] as String? ?? 'cash',
        notes: map['notes'] as String?,
        deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'] as String)
            : null,
      );
}
