class AppConstants {
  static const String appName = 'Vaani';
  static const String dbName = 'vaani.db';
  static const int dbVersion = 20;

  // Resource-cap numbers (voice/manual invoice limits, staff limit) used to
  // live here as hardcoded constants keyed to "the Basic plan" by name.
  // They're now real, admin-configurable columns on the backend's Plan row
  // (see schema.prisma) surfaced per-shop via SubscriptionStatus's
  // voiceInvoiceLimit/staffLimit/manualInvoiceMonthlyLimit fields — read
  // those instead of a constant here, so a cap changed in the admin panel
  // takes effect without an app release.

  // SharedPreferences keys
  static const String keyIsLoggedIn = 'isLoggedIn';
  static const String keyIsSetupComplete = 'isSetupComplete';
  static const String keyThemeMode = 'theme_mode';
  static const String keyShopPhone = 'shop_phone';
  static const String keyShopId = 'shop_id';
  static const String keyShopBackendToken = 'shop_backend_token';
  // The new User-scoped token (dormant alongside the legacy shop token —
  // see MemberRepository.ensureUserSession) and the shop it auto-selected.
  static const String keyUserBackendToken = 'user_backend_token';
  static const String keyActiveShopId = 'active_shop_id';
  static const String keySubscriptionStatusJson = 'subscription_status_json';
  static const String keyLastFullSyncAt = 'last_full_sync_at';
  // Separate from keyLastFullSyncAt (the push cursor, phone-clock-based) —
  // this one is stamped from the backend's own serverTime, so pull's "since"
  // comparison is never thrown off by the phone's clock being wrong.
  static const String keyLastPullSyncAt = 'last_pull_sync_at';
  static const String keyPendingOtpToken = 'pending_otp_token';

  // GST rates
  static const List<double> gstRates = [0.0, 5.0, 12.0, 18.0, 28.0];

  // Invoice constants
  static const String invoicePrefix = 'INV';
  static const String defaultCustomerName = 'Walk-in Customer';

  // Pagination
  static const int pageSize = 20;

  // Reorder defaults
  static const int defaultReorderLevel = 10;

  // Notification types
  static const String notifLowStock = 'low_stock';
  static const String notifMilestone = 'milestone';
  static const String notifRecord = 'record';
  static const String notifUpdate = 'update';
  static const String notifDailySummary = 'daily_summary';

  // Payment modes
  static const List<String> paymentModes = ['cash', 'upi', 'card', 'credit'];

  // Discount types
  static const String discountNone = 'none';
  static const String discountPercent = 'percent';
  static const String discountFlat = 'flat';

  // Printer settings (SharedPrefs key — actual value stored as JSON)
  static const String keyPrinterSettings = 'printer_settings_v1';

  // Invoice status
  static const String statusPaid = 'paid';
  static const String statusPartialPaid = 'partial_paid';
  static const String statusPending = 'pending';
  static const String statusCancelled = 'cancelled';

  // Item categories
  static const List<String> categories = [
    'Soft Drinks',
    'Snacks',
    'Dairy',
    'Chocolates',
    'Biscuits',
    'Noodles',
    'Chips',
    'Personal Care',
    'Stationery',
    'Cleaning Items',
    'Grocery',
    'Others',
  ];

  // Inventory transaction types
  static const String txnSale = 'sale';
  static const String txnRestock = 'restock';
  static const String txnAdjustment = 'adjustment';
  static const String txnDamage = 'damage';
  static const String txnReturn = 'return';
  static const String txnVoid = 'void';

  // Reason labels offered by the Add/Remove Stock sheets — a short,
  // shopkeeper-facing "why", stored in inventory_transactions.reason
  // alongside the broader `type` bucket above (which drives the +/- sign
  // and the audit-trail grouping). Kept as plain strings rather than an
  // enum: this is display text a reason picker shows, not a code path any
  // logic branches on.
  static const List<String> stockInReasons = ['Purchase', 'Stock Correction', 'Return from Customer', 'Other'];
  static const List<String> stockOutReasons = ['Damaged', 'Stock Correction', 'Expired', 'Given as Sample', 'Other'];
}
