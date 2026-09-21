import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/constants.dart';
import '../../auth/repositories/shop_repository.dart';
import '../../inventory/repositories/product_repository.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../billing/repositories/invoice_repository.dart';
import '../../billing/repositories/payment_transaction_repository.dart';
import '../../inventory/repositories/category_repository.dart';
import '../../subscription/repositories/subscription_repository.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/models/payment_transaction.dart';
import '../../../shared/models/shop.dart';
import '../services/sync_api_client.dart';
import '../services/cloudinary_upload_service.dart';
import '../../subscription/services/subscription_api_client.dart' show UnauthorizedException;

class SyncResult {
  final bool success;
  // True when the failure was specifically the backend rejecting the shop's
  // token (expired/invalid) — distinct from a real network failure, since
  // "will retry automatically" is honest for the latter but never true for
  // this: the phone has no way to silently get a new token (re-auth needs a
  // fresh SMS OTP), so the caller should tell the user to log out and back
  // in rather than imply retrying will fix it.
  final bool sessionExpired;
  // The raw exception behind a failed sync — null on success. Kept around
  // (rather than swallowed) purely so callers can show it alongside the
  // friendly "couldn't reach the server" message: that message is a guess at
  // *why* it failed, and has been wrong before (see network_error.dart) —
  // having the actual exception on screen is what makes a wrong guess
  // diagnosable instead of a dead end.
  final Object? error;
  // Top stack frame of [error] — where the failure actually happened, e.g.
  // which model's fromJson threw a null-cast. Cheap enough to always keep;
  // only matters when error is non-null.
  final String? errorDetail;
  final int products;
  final int customers;
  final int invoices;
  final int inventoryTransactions;
  final int paymentTransactions;

  const SyncResult({
    required this.success,
    this.sessionExpired = false,
    this.error,
    this.errorDetail,
    this.products = 0,
    this.customers = 0,
    this.invoices = 0,
    this.inventoryTransactions = 0,
    this.paymentTransactions = 0,
  });

  int get totalRecords =>
      products + customers + invoices + inventoryTransactions + paymentTransactions;
}

/// Local ids touched by a pull-merge this cycle, per entity — used to
/// exclude them from the push gathered right after, so nothing pulled this
/// same cycle gets redundantly re-sent back up immediately.
class _PullTouched {
  final Set<int> products;
  final Set<int> customers;
  final Set<int> invoices;
  final Set<int> payments;

  const _PullTouched(this.products, this.customers, this.invoices, this.payments);
}

class DataSyncRepository {
  final SyncApiClient _api;
  final ShopRepository _shopRepo;
  final ProductRepository _productRepo;
  final CustomerRepository _customerRepo;
  final InvoiceRepository _invoiceRepo;
  final PaymentTransactionRepository _paymentRepo;
  final SubscriptionRepository _subscriptionRepo;
  final CategoryRepository _categoryRepo;
  final CloudinaryUploadService _cloudinary;

  // The hourly timer, app-resume check, and manual "Cloud Sync" button can
  // all call syncNow() independently with nothing stopping two calls from
  // overlapping — both would read the same push/pull cursors and race to
  // advance them, risking one call's cursor update clobbering progress the
  // other hadn't actually finished pushing/pulling yet. Guarding here (the
  // one choke point every caller goes through) instead of in each caller
  // means a second call while one is already running just awaits the same
  // in-flight result rather than starting a competing sync.
  Future<SyncResult>? _inFlight;

  DataSyncRepository(
    this._api,
    this._shopRepo,
    this._productRepo,
    this._customerRepo,
    this._invoiceRepo,
    this._paymentRepo,
    this._subscriptionRepo,
    this._categoryRepo,
    this._cloudinary,
  );

  Future<DateTime?> getLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keyLastFullSyncAt);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  /// Pushes everything changed since the last successful sync to the
  /// backend. Demo shops are never synced. Never throws — failures (offline,
  /// not yet linked to the backend, backend unreachable) return
  /// `SyncResult(success: false)` so callers can always call this safely.
  /// An expired/rejected shop token instead returns
  /// `SyncResult(success: false, sessionExpired: true)` — see
  /// [SyncResult.sessionExpired] for why callers should treat that
  /// differently.
  Future<SyncResult> syncNow() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final result = _syncNow();
    _inFlight = result;
    result.whenComplete(() => _inFlight = null);
    return result;
  }

  Future<SyncResult> _syncNow() async {
    final prefs = await SharedPreferences.getInstance();
    final isDemoMode = prefs.getBool(AppConstants.keyIsDemoMode) ?? false;
    if (isDemoMode) return const SyncResult(success: false);

    final token = prefs.getString(AppConstants.keyShopBackendToken);
    if (token == null) return const SyncResult(success: false);

    try {
      final shop = await _shopRepo.getShop();
      if (shop?.id == null) return const SyncResult(success: false);
      final shopId = shop!.id!;

      // Pull cloud-side changes (admin panel edits/deletes) down first. A
      // failed pull throws and aborts the whole cycle here — same as a
      // failed push already did before this existed — so a partial pull
      // never gets built on top of by a push. Whatever this touches is
      // excluded from the push gathered below, so nothing pulled this cycle
      // gets redundantly re-sent back up in the same call.
      final touched = await _pullFromCloud(token, shopId, prefs);

      // Re-read the shop — shopProfile may have just been overwritten by
      // the pull merge above, and the push must send the fresh state, not
      // what was in memory before the pull (which would just immediately
      // stomp the cloud's newer values right back).
      final refreshedShop = await _shopRepo.getShop() ?? shop;

      final sinceRaw = prefs.getString(AppConstants.keyLastFullSyncAt);
      final since = sinceRaw != null ? DateTime.tryParse(sinceRaw) : null;
      // Captured before querying so a write that lands mid-sync is simply
      // picked up by the next sync, rather than silently skipped.
      final syncStartedAt = DateTime.now();

      final products = (await _productRepo.getProductsUpdatedSince(shopId, since))
          .where((p) => !touched.products.contains(p.id))
          .toList();
      final customers = (await _customerRepo.getCustomersUpdatedSince(shopId, since))
          .where((c) => !touched.customers.contains(c.id))
          .toList();
      final invoices = (await _invoiceRepo.getInvoicesUpdatedSince(shopId, since))
          .where((inv) => !touched.invoices.contains(inv.id))
          .toList();
      final inventoryTx = await _productRepo.getInventoryTransactionsSince(shopId, since);
      final paymentTx = (await _paymentRepo.getPaymentTransactionsUpdatedSince(shopId, since))
          .where((p) => !touched.payments.contains(p.id))
          .toList();

      final categories = await _categoryRepo.getCategories(shopId);

      // Best-effort — a Cloudinary hiccup should never fail the rest of the
      // sync. Only uploads images that haven't been uploaded yet (imageUrl
      // null); already-uploaded ones are skipped.
      final productsWithImages = await _withUploadedProductImages(products);
      final logoUrl = await _withUploadedShopLogo(refreshedShop);

      final payload = {
        'shopProfile': {
          'name': refreshedShop.name,
          'ownerName': refreshedShop.ownerName,
          'address': refreshedShop.address,
          'gstNumber': refreshedShop.gstNumber,
          'currency': refreshedShop.currency,
          'gstEnabled': refreshedShop.gstEnabled,
          'defaultGstRate': refreshedShop.defaultGstRate,
          'upiId': refreshedShop.upiId,
          'categories': categories,
          // Omitted (not sent as null) when we have nothing to say about it
          // locally — e.g. right after a fresh login, before a pull has
          // restored the cached logoUrl and there's no local logoPath file
          // to upload either. The backend treats an absent key as "leave it
          // alone" but an explicit null as "clear it" (shop-sync.service.js:
          // `shopProfile.logoUrl !== undefined`), so sending null here was
          // wiping an already-uploaded logo on the very next sync after
          // logging back in — this was a real, confirmed data-loss bug.
          if (logoUrl != null) 'logoUrl': logoUrl,
        },
        'products': productsWithImages.map(_productJson).toList(),
        'customers': customers.map(_customerJson).toList(),
        'invoices': invoices.map(_invoiceJson).toList(),
        'inventoryTransactions': inventoryTx.map(_inventoryTransactionJson).toList(),
        'paymentTransactions': paymentTx.map(_paymentTransactionJson).toList(),
      };

      final result = await _api.sync(token, payload);
      await prefs.setString(AppConstants.keyLastFullSyncAt, syncStartedAt.toIso8601String());

      // Keep the subscription/module cache (plan, status, feature gating)
      // consistent across devices as part of the same cloud sync action,
      // rather than requiring a separate manual refresh.
      await _subscriptionRepo.refreshStatus();

      final received = result['received'] as Map<String, dynamic>? ?? {};
      return SyncResult(
        success: true,
        products: received['products'] as int? ?? 0,
        customers: received['customers'] as int? ?? 0,
        invoices: received['invoices'] as int? ?? 0,
        inventoryTransactions: received['inventoryTransactions'] as int? ?? 0,
        paymentTransactions: received['paymentTransactions'] as int? ?? 0,
      );
    } on UnauthorizedException {
      // Dead token — clear it so the app stops silently retrying something
      // that can never succeed without a fresh login. There's no refresh-
      // token flow, so this can only be resolved by the user logging out
      // and back in (which requires an SMS OTP) — never by retrying.
      await prefs.remove(AppConstants.keyShopBackendToken);
      return const SyncResult(success: false, sessionExpired: true);
    } catch (e, st) {
      // Full stack goes to the device log; only the top frame (where the
      // cast/error actually happened) rides along in SyncResult.errorDetail
      // so it's visible on screen without needing `flutter logs`/logcat access.
      debugPrint('[Sync] syncNow failed: ${e.runtimeType}: $e\n$st');
      final topFrame = st.toString().split('\n').take(2).join(' | ');
      return SyncResult(success: false, error: e, errorDetail: topFrame);
    }
  }

  /// Uploads any product image that hasn't made it to Cloudinary yet
  /// (imageUrl still null locally) and persists the result, so future syncs
  /// skip it. Products whose upload fails (offline, misconfigured) are sent
  /// as-is — image sync is best-effort and never blocks the rest of the sync.
  Future<List<Product>> _withUploadedProductImages(List<Product> products) async {
    if (!_cloudinary.isConfigured) return products;
    final result = <Product>[];
    for (final p in products) {
      if (p.imageUrl == null &&
          p.imagePath != null &&
          p.imagePath!.isNotEmpty &&
          p.id != null &&
          await File(p.imagePath!).exists()) {
        final url = await _cloudinary.uploadImage(p.imagePath!);
        if (url != null) {
          await _productRepo.setImageUrl(p.id!, url);
          result.add(p.copyWith(imageUrl: url));
          continue;
        }
      }
      result.add(p);
    }
    return result;
  }

  Future<String?> _withUploadedShopLogo(Shop shop) async {
    if (shop.logoUrl != null) return shop.logoUrl;
    if (!_cloudinary.isConfigured || shop.id == null) return null;
    if (shop.logoPath == null || shop.logoPath!.isEmpty) return null;
    if (!await File(shop.logoPath!).exists()) return null;

    final url = await _cloudinary.uploadImage(shop.logoPath!);
    if (url != null) {
      await _shopRepo.setLogoUrl(shop.id!, url);
    }
    return url;
  }

  // ── Pull (cloud → phone) ──────────────────────────────────────────────
  //
  // Conflict rule: most-recent-edit-wins by comparing timestamps — EXCEPT a
  // tombstone (deletedAt set, or a product's isActive going false) always
  // wins unconditionally, regardless of timestamps. That's deliberate, not
  // a shortcut: the phone has no local delete/deactivate action for any of
  // these entities, so a delete never competes with a legitimate local
  // delete — only with unrelated field bumps on the same row (a sale bumps
  // a customer's updated_at, a stock adjustment bumps a product's). Under
  // literal timestamp comparison, a product still selling or a customer
  // still buying would permanently out-race and silently swallow an
  // admin's delete, forever. See the two-way-sync plan for the full
  // reasoning.

  bool _shouldApplyCloudRecord({
    required DateTime? existingUpdatedAt,
    required bool isTombstone,
    required DateTime cloudUpdatedAt,
  }) {
    if (existingUpdatedAt == null) return true; // no local record yet
    if (isTombstone) return true; // deletes always win
    return cloudUpdatedAt.isAfter(existingUpdatedAt);
  }

  Future<Set<int>> _mergeProducts(List<dynamic> items, int shopId) async {
    final touched = <int>{};
    for (final raw in items) {
      final json = raw as Map<String, dynamic>;
      final localId = json['localId'] as int;
      final isDeleted = json['deletedAt'] != null;
      // Falls back to createdAt rather than crashing if updatedAt is ever
      // missing — same defense added for payments after a null updatedAt
      // there took down the whole sync cycle (pull is one try block with
      // push in DataSyncRepository.syncNow).
      final cloudUpdatedAt =
          DateTime.parse((json['updatedAt'] ?? json['createdAt']) as String);
      final existing = await _productRepo.getProductById(localId);
      if (!_shouldApplyCloudRecord(
          existingUpdatedAt: existing?.updatedAt,
          isTombstone: isDeleted,
          cloudUpdatedAt: cloudUpdatedAt)) {
        continue;
      }
      await _productRepo.upsertFromCloud(_productFromCloudJson(json, shopId, isDeleted: isDeleted));
      touched.add(localId);
    }
    return touched;
  }

  Future<Set<int>> _mergeCustomers(List<dynamic> items, int shopId) async {
    final touched = <int>{};
    for (final raw in items) {
      final json = raw as Map<String, dynamic>;
      final localId = json['localId'] as int;
      final isDeleted = json['deletedAt'] != null;
      // See the matching comment in _mergeProducts.
      final cloudUpdatedAt =
          DateTime.parse((json['updatedAt'] ?? json['createdAt']) as String);
      final existing = await _customerRepo.getCustomerById(localId);
      if (!_shouldApplyCloudRecord(
          existingUpdatedAt: existing?.updatedAt,
          isTombstone: isDeleted,
          cloudUpdatedAt: cloudUpdatedAt)) {
        continue;
      }
      await _customerRepo.upsertFromCloud(_customerFromCloudJson(json, shopId));
      touched.add(localId);
    }
    return touched;
  }

  Future<Set<int>> _mergeInvoices(List<dynamic> items, int shopId) async {
    final touched = <int>{};
    for (final raw in items) {
      final json = raw as Map<String, dynamic>;
      final localId = json['localId'] as int;
      final isDeleted = json['deletedAt'] != null;
      // See the matching comment in _mergeProducts.
      final cloudUpdatedAt =
          DateTime.parse((json['updatedAt'] ?? json['createdAt']) as String);
      final existing = await _invoiceRepo.getInvoiceById(localId);
      if (!_shouldApplyCloudRecord(
          existingUpdatedAt: existing?.updatedAt ?? existing?.createdAt,
          isTombstone: isDeleted,
          cloudUpdatedAt: cloudUpdatedAt)) {
        continue;
      }
      await _invoiceRepo.upsertFromCloud(_invoiceFromCloudJson(json, shopId));
      touched.add(localId);
    }
    return touched;
  }

  Future<Set<int>> _mergePayments(List<dynamic> items, int shopId) async {
    final touched = <int>{};
    for (final raw in items) {
      final json = raw as Map<String, dynamic>;
      final localId = json['localId'] as int;
      final isDeleted = json['deletedAt'] != null;
      // updatedAt was only backend-populated going forward (see
      // shop-sync.service.js) — rows synced before that fix still come back
      // with it null, so this falls back to createdAt rather than crashing.
      final cloudUpdatedAt =
          DateTime.parse((json['updatedAt'] ?? json['createdAt']) as String);
      final existing = await _paymentRepo.getById(localId);
      if (!_shouldApplyCloudRecord(
          existingUpdatedAt: existing?.updatedAt ?? existing?.createdAt,
          isTombstone: isDeleted,
          cloudUpdatedAt: cloudUpdatedAt)) {
        continue;
      }
      await _paymentRepo.upsertFromCloud(_paymentFromCloudJson(json, shopId));
      touched.add(localId);
    }
    return touched;
  }

  /// Pulls everything changed on the cloud side since the last successful
  /// pull, merges it in, and advances the pull cursor on success. Uses its
  /// own cursor (keyLastPullSyncAt, stamped from the backend's serverTime)
  /// deliberately separate from the push cursor (keyLastFullSyncAt, phone-
  /// clock-based) — conflating the two would mean a wrong device clock
  /// throws off which cloud changes get fetched.
  Future<_PullTouched> _pullFromCloud(
      String token, int shopId, SharedPreferences prefs) async {
    final sinceRaw = prefs.getString(AppConstants.keyLastPullSyncAt);
    final since = sinceRaw != null ? DateTime.tryParse(sinceRaw) : null;

    final response = await _api.pull(token, since);

    final products = await _mergeProducts(response['products'] as List? ?? const [], shopId);
    final customers = await _mergeCustomers(response['customers'] as List? ?? const [], shopId);
    final invoices = await _mergeInvoices(response['invoices'] as List? ?? const [], shopId);
    final payments = await _mergePayments(response['payments'] as List? ?? const [], shopId);

    final shopProfile = response['shopProfile'] as Map<String, dynamic>?;
    if (shopProfile != null) {
      // The backend bumps Shop.updatedAt via Prisma's @updatedAt on *every*
      // successful sync (it also touches lastDataSyncAt on the same row),
      // not just ones that actually change the profile — so shopProfile
      // shows up in most pull responses regardless. Without this comparison
      // that would unconditionally stomp a local edit that hasn't been
      // pushed up yet, since pull always runs before push in the same
      // cycle. Same "only apply if cloud is strictly newer" rule as every
      // other entity — shop has no tombstone concept, so isTombstone is
      // always false here.
      final localShop = await _shopRepo.getShop();
      final cloudUpdatedAt = DateTime.parse(shopProfile['updatedAt'] as String);
      if (_shouldApplyCloudRecord(
          existingUpdatedAt: localShop?.updatedAt,
          isTombstone: false,
          cloudUpdatedAt: cloudUpdatedAt)) {
        await _shopRepo.mergeFromCloud(
          shopId: shopId,
          name: shopProfile['name'] as String,
          ownerName: shopProfile['ownerName'] as String,
          address: shopProfile['address'] as String?,
          gstNumber: shopProfile['gstNumber'] as String?,
          currency: shopProfile['currency'] as String? ?? 'INR',
          gstEnabled: shopProfile['gstEnabled'] as bool? ?? true,
          defaultGstRate: (shopProfile['defaultGstRate'] as num?)?.toDouble() ?? 5.0,
          upiId: shopProfile['upiId'] as String?,
          logoUrl: shopProfile['logoUrl'] as String?,
          updatedAt: cloudUpdatedAt,
        );
        final categories = (shopProfile['categories'] as List?)?.cast<String>();
        if (categories != null) {
          await _categoryRepo.replaceCategories(shopId, categories);
        }
      }
    }

    final serverTime = response['serverTime'] as String?;
    if (serverTime != null) {
      await prefs.setString(AppConstants.keyLastPullSyncAt, serverTime);
    }

    return _PullTouched(products, customers, invoices, payments);
  }

  Product _productFromCloudJson(Map<String, dynamic> json, int shopId, {required bool isDeleted}) {
    return Product(
      id: json['localId'] as int,
      shopId: shopId,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      category: json['category'] as String?,
      costPrice: (json['costPrice'] as num).toDouble(),
      sellingPrice: (json['sellingPrice'] as num).toDouble(),
      gstRate: (json['gstRate'] as num).toDouble(),
      stockQuantity: json['stockQuantity'] as int,
      reorderLevel: json['reorderLevel'] as int,
      imageUrl: json['imageUrl'] as String?,
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const [],
      // A tombstone always forces inactive, regardless of the isActive value
      // the cloud row happened to carry (deleting a product shouldn't
      // depend on its unrelated status field ever having been toggled).
      isActive: isDeleted ? false : (json['isActive'] as bool? ?? true),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Customer _customerFromCloudJson(Map<String, dynamic> json, int shopId) {
    return Customer(
      id: json['localId'] as int,
      shopId: shopId,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      totalPurchases: (json['totalPurchases'] as num).toDouble(),
      totalBills: json['totalBills'] as int,
      totalOutstanding: (json['totalOutstanding'] as num).toDouble(),
      advanceBalance: (json['advanceBalance'] as num).toDouble(),
      lastVisit: json['lastVisit'] != null ? DateTime.parse(json['lastVisit'] as String) : null,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Invoice _invoiceFromCloudJson(Map<String, dynamic> json, int shopId) {
    final localId = json['localId'] as int;
    final itemsJson = (json['items'] as List?) ?? const [];
    final items = itemsJson.map((raw) {
      final item = raw as Map<String, dynamic>;
      return InvoiceItem(
        invoiceId: localId,
        productId: item['productId'] as int,
        productName: item['productName'] as String,
        quantity: item['quantity'] as int,
        sellingPrice: (item['sellingPrice'] as num).toDouble(),
        gstRate: (item['gstRate'] as num?)?.toDouble() ?? 0,
        gstAmount: (item['gstAmount'] as num?)?.toDouble() ?? 0,
        lineTotal: (item['lineTotal'] as num).toDouble(),
      );
    }).toList();

    return Invoice(
      id: localId,
      invoiceNumber: json['invoiceNumber'] as String,
      shopId: shopId,
      customerId: json['customerId'] as int?,
      customerName: json['customerName'] as String? ?? 'Walk-in Customer',
      subtotal: (json['subtotal'] as num).toDouble(),
      discountType: json['discountType'] as String? ?? 'none',
      discountValue: (json['discountValue'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
      gstAmount: (json['gstAmount'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grandTotal'] as num).toDouble(),
      receivedAmount: (json['receivedAmount'] as num?)?.toDouble() ?? 0,
      pendingAmount: (json['pendingAmount'] as num?)?.toDouble() ?? 0,
      paymentMode: json['paymentMode'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'paid',
      notes: json['notes'] as String?,
      isVoiceCreated: json['isVoiceCreated'] as bool? ?? false,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      items: items,
    );
  }

  PaymentTransaction _paymentFromCloudJson(Map<String, dynamic> json, int shopId) {
    return PaymentTransaction(
      id: json['localId'] as int,
      shopId: shopId,
      customerId: json['customerId'] as int,
      invoiceId: json['invoiceId'] as int?,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentMode: json['paymentMode'] as String,
      notes: json['notes'] as String?,
      deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> _productJson(Product p) => {
        'localId': p.id,
        'name': p.name,
        'sku': p.sku,
        'barcode': p.barcode,
        'category': p.category,
        'costPrice': p.costPrice,
        'sellingPrice': p.sellingPrice,
        'gstRate': p.gstRate,
        'stockQuantity': p.stockQuantity,
        'reorderLevel': p.reorderLevel,
        'imagePath': p.imagePath,
        'imageUrl': p.imageUrl,
        'aliases': p.aliases,
        'isActive': p.isActive,
        'createdAt': p.createdAt.toIso8601String(),
        'updatedAt': p.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _customerJson(Customer c) => {
        'localId': c.id,
        'name': c.name,
        'phone': c.phone,
        'email': c.email,
        'address': c.address,
        'totalPurchases': c.totalPurchases,
        'totalBills': c.totalBills,
        'totalOutstanding': c.totalOutstanding,
        'advanceBalance': c.advanceBalance,
        'lastVisit': c.lastVisit?.toIso8601String(),
        'createdAt': c.createdAt.toIso8601String(),
        'updatedAt': c.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _invoiceJson(Invoice inv) => {
        'localId': inv.id,
        'invoiceNumber': inv.invoiceNumber,
        'customerId': inv.customerId,
        'customerName': inv.customerName,
        'subtotal': inv.subtotal,
        'discountType': inv.discountType,
        'discountValue': inv.discountValue,
        'discountAmount': inv.discountAmount,
        'gstAmount': inv.gstAmount,
        'grandTotal': inv.grandTotal,
        'receivedAmount': inv.receivedAmount,
        'pendingAmount': inv.pendingAmount,
        'paymentMode': inv.paymentMode,
        'status': inv.status,
        'notes': inv.notes,
        'isVoiceCreated': inv.isVoiceCreated,
        'createdAt': inv.createdAt.toIso8601String(),
        'updatedAt': (inv.updatedAt ?? inv.createdAt).toIso8601String(),
        'items': inv.items
            .map((item) => {
                  'localId': item.id,
                  'productId': item.productId,
                  'productName': item.productName,
                  'quantity': item.quantity,
                  'sellingPrice': item.sellingPrice,
                  'gstRate': item.gstRate,
                  'gstAmount': item.gstAmount,
                  'lineTotal': item.lineTotal,
                })
            .toList(),
      };

  Map<String, dynamic> _inventoryTransactionJson(Map<String, Object?> row) => {
        'localId': row['id'],
        'productId': row['product_id'],
        'invoiceId': row['invoice_id'],
        'type': row['type'],
        'quantityChange': row['quantity_change'],
        'stockBefore': row['stock_before'],
        'stockAfter': row['stock_after'],
        'notes': row['notes'],
        'createdAt': row['created_at'],
      };

  Map<String, dynamic> _paymentTransactionJson(PaymentTransaction p) => {
        'localId': p.id,
        'customerId': p.customerId,
        'invoiceId': p.invoiceId,
        'type': p.type,
        'amount': p.amount,
        'paymentMode': p.paymentMode,
        'notes': p.notes,
        'createdAt': p.createdAt.toIso8601String(),
        'updatedAt': (p.updatedAt ?? p.createdAt).toIso8601String(),
      };
}
