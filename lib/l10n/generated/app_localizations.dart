import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Vaani'**
  String get appName;

  /// No description provided for @aiStoreManagerTagline.
  ///
  /// In en, this message translates to:
  /// **'AI Store Manager'**
  String get aiStoreManagerTagline;

  /// No description provided for @speakBillDone.
  ///
  /// In en, this message translates to:
  /// **'Speak. Bill. Done.'**
  String get speakBillDone;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @billing.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @bills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get bills;

  /// No description provided for @aiManager.
  ///
  /// In en, this message translates to:
  /// **'AI Manager'**
  String get aiManager;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @newBill.
  ///
  /// In en, this message translates to:
  /// **'New Bill'**
  String get newBill;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @tax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tax;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @upi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get upi;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @mixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get mixed;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @margin.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get margin;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @proceed.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get proceed;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in Customer'**
  String get walkInCustomer;

  /// No description provided for @walkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get walkIn;

  /// No description provided for @customerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerLabel;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @profit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get profit;

  /// No description provided for @inventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

  /// No description provided for @todaysSales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Sales'**
  String get todaysSales;

  /// No description provided for @recentBills.
  ///
  /// In en, this message translates to:
  /// **'Recent Bills'**
  String get recentBills;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @gst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get gst;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @fromYesterday.
  ///
  /// In en, this message translates to:
  /// **'from yesterday'**
  String get fromYesterday;

  /// No description provided for @newCustomers.
  ///
  /// In en, this message translates to:
  /// **'New Customers'**
  String get newCustomers;

  /// No description provided for @todaysProfit.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Profit'**
  String get todaysProfit;

  /// No description provided for @noBillsToday.
  ///
  /// In en, this message translates to:
  /// **'No bills yet today'**
  String get noBillsToday;

  /// No description provided for @voiceBill.
  ///
  /// In en, this message translates to:
  /// **'Voice Bill'**
  String get voiceBill;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @sevenDayRevenue.
  ///
  /// In en, this message translates to:
  /// **'7-Day Revenue'**
  String get sevenDayRevenue;

  /// No description provided for @viewReports.
  ///
  /// In en, this message translates to:
  /// **'View Reports'**
  String get viewReports;

  /// No description provided for @lowStockBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} low'**
  String lowStockBadge(String count);

  /// No description provided for @searchProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Search products, SKU, barcode...'**
  String get searchProductsHint;

  /// No description provided for @sortNameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get sortNameAZ;

  /// No description provided for @sortNameZA.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get sortNameZA;

  /// No description provided for @sortStockLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Stock Low–High'**
  String get sortStockLowHigh;

  /// No description provided for @sortStockHighLow.
  ///
  /// In en, this message translates to:
  /// **'Stock High–Low'**
  String get sortStockHighLow;

  /// No description provided for @sortRecentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get sortRecentlyAdded;

  /// No description provided for @productsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} Product} other{{count} Products}}'**
  String productsCount(int count);

  /// No description provided for @filterByStock.
  ///
  /// In en, this message translates to:
  /// **'Filter by Stock'**
  String get filterByStock;

  /// No description provided for @allProducts.
  ///
  /// In en, this message translates to:
  /// **'All Products'**
  String get allProducts;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get lowStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStock;

  /// No description provided for @deleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Delete Product'**
  String get deleteProduct;

  /// No description provided for @deleteProductConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteProductConfirm(String name);

  /// No description provided for @noProductsMatch.
  ///
  /// In en, this message translates to:
  /// **'No products match \"{query}\"'**
  String noProductsMatch(String query);

  /// No description provided for @noProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get noProductsYet;

  /// No description provided for @addFirstProductHint.
  ///
  /// In en, this message translates to:
  /// **'Add your first product to get started'**
  String get addFirstProductHint;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inStock;

  /// No description provided for @lowLabel.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get lowLabel;

  /// No description provided for @outLabel.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get outLabel;

  /// No description provided for @marginPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% margin'**
  String marginPercent(String percent);

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @addStock.
  ///
  /// In en, this message translates to:
  /// **'Add Stock'**
  String get addStock;

  /// No description provided for @currentStock.
  ///
  /// In en, this message translates to:
  /// **'Current stock: {count} units'**
  String currentStock(String count);

  /// No description provided for @unitsToAdd.
  ///
  /// In en, this message translates to:
  /// **'Units to add'**
  String get unitsToAdd;

  /// No description provided for @adjustStock.
  ///
  /// In en, this message translates to:
  /// **'Adjust Stock'**
  String get adjustStock;

  /// No description provided for @unitsToRemoveAdjust.
  ///
  /// In en, this message translates to:
  /// **'Units to remove / adjust'**
  String get unitsToRemoveAdjust;

  /// No description provided for @confirmAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Confirm Adjustment'**
  String get confirmAdjustment;

  /// No description provided for @removeProductConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from inventory? This cannot be undone.'**
  String removeProductConfirm(String name);

  /// No description provided for @productNotFound.
  ///
  /// In en, this message translates to:
  /// **'Product not found.'**
  String get productNotFound;

  /// No description provided for @sellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get sellingPrice;

  /// No description provided for @costPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost Price'**
  String get costPrice;

  /// No description provided for @profitMargin.
  ///
  /// In en, this message translates to:
  /// **'Profit Margin'**
  String get profitMargin;

  /// No description provided for @gstRate.
  ///
  /// In en, this message translates to:
  /// **'GST Rate'**
  String get gstRate;

  /// No description provided for @stockLevel.
  ///
  /// In en, this message translates to:
  /// **'Stock Level'**
  String get stockLevel;

  /// No description provided for @unitsLabel.
  ///
  /// In en, this message translates to:
  /// **'units'**
  String get unitsLabel;

  /// No description provided for @reorderAt.
  ///
  /// In en, this message translates to:
  /// **'Reorder at {count} units'**
  String reorderAt(String count);

  /// No description provided for @stockValue.
  ///
  /// In en, this message translates to:
  /// **'Stock value: {value}'**
  String stockValue(String value);

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetails;

  /// No description provided for @skuCode.
  ///
  /// In en, this message translates to:
  /// **'SKU / Code'**
  String get skuCode;

  /// No description provided for @reorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder Level'**
  String get reorderLevel;

  /// No description provided for @addedOn.
  ///
  /// In en, this message translates to:
  /// **'Added On'**
  String get addedOn;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last Updated'**
  String get lastUpdated;

  /// No description provided for @voiceAliases.
  ///
  /// In en, this message translates to:
  /// **'Voice Aliases'**
  String get voiceAliases;

  /// No description provided for @adjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get adjust;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit Product'**
  String get editProduct;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @takeAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a Photo'**
  String get takeAPhoto;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove Image'**
  String get removeImage;

  /// No description provided for @tapToChangeImage.
  ///
  /// In en, this message translates to:
  /// **'Tap to change image'**
  String get tapToChangeImage;

  /// No description provided for @addProductImage.
  ///
  /// In en, this message translates to:
  /// **'Add product image'**
  String get addProductImage;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product Name *'**
  String get productName;

  /// No description provided for @skuPhoneCode.
  ///
  /// In en, this message translates to:
  /// **'SKU / Phone Code'**
  String get skuPhoneCode;

  /// No description provided for @costPriceCurrency.
  ///
  /// In en, this message translates to:
  /// **'Cost Price (₹)'**
  String get costPriceCurrency;

  /// No description provided for @sellingPriceCurrency.
  ///
  /// In en, this message translates to:
  /// **'Selling Price (₹) *'**
  String get sellingPriceCurrency;

  /// No description provided for @mustBeGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Must be > 0'**
  String get mustBeGreaterThanZero;

  /// No description provided for @stockQuantity.
  ///
  /// In en, this message translates to:
  /// **'Stock Quantity'**
  String get stockQuantity;

  /// No description provided for @aliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases (comma-separated)'**
  String get aliasesLabel;

  /// No description provided for @updateProduct.
  ///
  /// In en, this message translates to:
  /// **'Update Product'**
  String get updateProduct;

  /// No description provided for @saveProduct.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get saveProduct;

  /// No description provided for @productUpdated.
  ///
  /// In en, this message translates to:
  /// **'Product updated'**
  String get productUpdated;

  /// No description provided for @productAdded.
  ///
  /// In en, this message translates to:
  /// **'Product added'**
  String get productAdded;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcode;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan Barcode'**
  String get scanBarcode;

  /// No description provided for @generateBarcode.
  ///
  /// In en, this message translates to:
  /// **'Generate Barcode'**
  String get generateBarcode;

  /// No description provided for @removeBarcode.
  ///
  /// In en, this message translates to:
  /// **'Remove Barcode'**
  String get removeBarcode;

  /// No description provided for @barcodePreview.
  ///
  /// In en, this message translates to:
  /// **'Barcode Preview'**
  String get barcodePreview;

  /// No description provided for @printBarcode.
  ///
  /// In en, this message translates to:
  /// **'Print Barcode'**
  String get printBarcode;

  /// No description provided for @printing.
  ///
  /// In en, this message translates to:
  /// **'Printing…'**
  String get printing;

  /// No description provided for @previewPrint.
  ///
  /// In en, this message translates to:
  /// **'Preview & Print'**
  String get previewPrint;

  /// No description provided for @noBarcodeAssigned.
  ///
  /// In en, this message translates to:
  /// **'No barcode assigned.'**
  String get noBarcodeAssigned;

  /// No description provided for @barcodeNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Barcode not registered.'**
  String get barcodeNotRegistered;

  /// No description provided for @duplicateBarcodeError.
  ///
  /// In en, this message translates to:
  /// **'Barcode already in use. Please use a unique barcode.'**
  String get duplicateBarcodeError;

  /// No description provided for @searchProductsByNameHint.
  ///
  /// In en, this message translates to:
  /// **'Search products by name, SKU or barcode...'**
  String get searchProductsByNameHint;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get listView;

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get cartEmpty;

  /// No description provided for @clearCart.
  ///
  /// In en, this message translates to:
  /// **'Clear Cart'**
  String get clearCart;

  /// No description provided for @removeAllItemsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all items from cart?'**
  String get removeAllItemsConfirm;

  /// No description provided for @addDiscount.
  ///
  /// In en, this message translates to:
  /// **'Add Discount'**
  String get addDiscount;

  /// No description provided for @taxLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax: {amount}'**
  String taxLabel(String amount);

  /// No description provided for @youSave.
  ///
  /// In en, this message translates to:
  /// **'You save {amount}'**
  String youSave(String amount);

  /// No description provided for @payAmount.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String payAmount(String amount);

  /// No description provided for @selectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select Customer'**
  String get selectCustomer;

  /// No description provided for @percentageOption.
  ///
  /// In en, this message translates to:
  /// **'Percentage (%)'**
  String get percentageOption;

  /// No description provided for @flatAmountOption.
  ///
  /// In en, this message translates to:
  /// **'Flat Amount (₹)'**
  String get flatAmountOption;

  /// No description provided for @listeningTapToStop.
  ///
  /// In en, this message translates to:
  /// **'Listening... tap to stop'**
  String get listeningTapToStop;

  /// No description provided for @tapMicSpeakAgain.
  ///
  /// In en, this message translates to:
  /// **'Tap mic to speak again'**
  String get tapMicSpeakAgain;

  /// No description provided for @tapMicToSpeak.
  ///
  /// In en, this message translates to:
  /// **'Tap mic to speak'**
  String get tapMicToSpeak;

  /// No description provided for @micUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone unavailable'**
  String get micUnavailable;

  /// No description provided for @addItemsToCart.
  ///
  /// In en, this message translates to:
  /// **'Add {count} item(s) to Cart'**
  String addItemsToCart(String count);

  /// No description provided for @speakAgain.
  ///
  /// In en, this message translates to:
  /// **'Speak again'**
  String get speakAgain;

  /// No description provided for @recognizedText.
  ///
  /// In en, this message translates to:
  /// **'Recognized Text'**
  String get recognizedText;

  /// No description provided for @productsFoundCount.
  ///
  /// In en, this message translates to:
  /// **'Products Found ({count})'**
  String productsFoundCount(String count);

  /// No description provided for @addedToCartCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products added to cart'**
  String addedToCartCount(String count);

  /// No description provided for @notFoundSuffix.
  ///
  /// In en, this message translates to:
  /// **'(Not found)'**
  String get notFoundSuffix;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @voiceBillingTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice Billing'**
  String get voiceBillingTitle;

  /// No description provided for @tapToSpeak.
  ///
  /// In en, this message translates to:
  /// **'Tap to speak'**
  String get tapToSpeak;

  /// No description provided for @walkInCustomerLabel.
  ///
  /// In en, this message translates to:
  /// **'Walk-in Customer'**
  String get walkInCustomerLabel;

  /// No description provided for @addCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add Customer'**
  String get addCustomer;

  /// No description provided for @editCustomer.
  ///
  /// In en, this message translates to:
  /// **'Edit Customer'**
  String get editCustomer;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @addCustomerImage.
  ///
  /// In en, this message translates to:
  /// **'Add customer photo'**
  String get addCustomerImage;

  /// No description provided for @customerUpdated.
  ///
  /// In en, this message translates to:
  /// **'Customer updated'**
  String get customerUpdated;

  /// No description provided for @customerFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get customerFilterAll;

  /// No description provided for @customerFilterRegular.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get customerFilterRegular;

  /// No description provided for @customerFilterNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get customerFilterNew;

  /// No description provided for @customerFilterInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get customerFilterInactive;

  /// No description provided for @customersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your customer ledger'**
  String get customersSubtitle;

  /// No description provided for @totalDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Due'**
  String get totalDueLabel;

  /// No description provided for @totalAdvanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Advance'**
  String get totalAdvanceLabel;

  /// No description provided for @customersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 customer} other{{count} customers}}'**
  String customersCount(int count);

  /// No description provided for @searchNameOrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone number...'**
  String get searchNameOrPhoneHint;

  /// No description provided for @ledgerFilterWithDue.
  ///
  /// In en, this message translates to:
  /// **'With Due'**
  String get ledgerFilterWithDue;

  /// No description provided for @ledgerFilterWithAdvance.
  ///
  /// In en, this message translates to:
  /// **'With Advance'**
  String get ledgerFilterWithAdvance;

  /// No description provided for @ledgerFilterSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get ledgerFilterSettled;

  /// No description provided for @sortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sortRecent;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get sortOldest;

  /// No description provided for @sortHighestDue.
  ///
  /// In en, this message translates to:
  /// **'Highest Due'**
  String get sortHighestDue;

  /// No description provided for @sortHighestAdvance.
  ///
  /// In en, this message translates to:
  /// **'Highest Advance'**
  String get sortHighestAdvance;

  /// No description provided for @sortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortLabel;

  /// No description provided for @allCustomersHeading.
  ///
  /// In en, this message translates to:
  /// **'All Customers ({count})'**
  String allCustomersHeading(int count);

  /// No description provided for @advanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get advanceLabel;

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addLabel;

  /// No description provided for @noCustomersFound.
  ///
  /// In en, this message translates to:
  /// **'No customers found'**
  String get noCustomersFound;

  /// No description provided for @billsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage your bills'**
  String get billsSubtitle;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @resetFilters.
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get resetFilters;

  /// No description provided for @noPurchasesYet.
  ///
  /// In en, this message translates to:
  /// **'No purchases yet'**
  String get noPurchasesYet;

  /// No description provided for @previousDue.
  ///
  /// In en, this message translates to:
  /// **'Previous Due'**
  String get previousDue;

  /// No description provided for @previousDueInfo.
  ///
  /// In en, this message translates to:
  /// **'Unpaid amount from previous bills'**
  String get previousDueInfo;

  /// No description provided for @receiveAmount.
  ///
  /// In en, this message translates to:
  /// **'Receive Amount'**
  String get receiveAmount;

  /// No description provided for @remainingDue.
  ///
  /// In en, this message translates to:
  /// **'Remaining Due'**
  String get remainingDue;

  /// No description provided for @advanceBalance.
  ///
  /// In en, this message translates to:
  /// **'Advance Balance'**
  String get advanceBalance;

  /// No description provided for @applyAdvance.
  ///
  /// In en, this message translates to:
  /// **'Apply advance balance ({amount})'**
  String applyAdvance(String amount);

  /// No description provided for @advanceApplied.
  ///
  /// In en, this message translates to:
  /// **'Advance Applied'**
  String get advanceApplied;

  /// No description provided for @netDue.
  ///
  /// In en, this message translates to:
  /// **'Net Bill'**
  String get netDue;

  /// No description provided for @oldDuesReduced.
  ///
  /// In en, this message translates to:
  /// **'Previous Outstanding Reduced'**
  String get oldDuesReduced;

  /// No description provided for @addedToAdvance.
  ///
  /// In en, this message translates to:
  /// **'Added to Advance'**
  String get addedToAdvance;

  /// No description provided for @newAdvanceBalance.
  ///
  /// In en, this message translates to:
  /// **'New Advance Balance'**
  String get newAdvanceBalance;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmount;

  /// No description provided for @currentBill.
  ///
  /// In en, this message translates to:
  /// **'Current Bill'**
  String get currentBill;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethod;

  /// No description provided for @partialPaymentRequiresCustomer.
  ///
  /// In en, this message translates to:
  /// **'Partial payment requires a customer.'**
  String get partialPaymentRequiresCustomer;

  /// No description provided for @newOutstanding.
  ///
  /// In en, this message translates to:
  /// **'New Outstanding'**
  String get newOutstanding;

  /// No description provided for @collectPayment.
  ///
  /// In en, this message translates to:
  /// **'Collect Payment'**
  String get collectPayment;

  /// No description provided for @outstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get outstanding;

  /// No description provided for @depositAsAdvance.
  ///
  /// In en, this message translates to:
  /// **'Deposit as Advance'**
  String get depositAsAdvance;

  /// No description provided for @collectAgainstDues.
  ///
  /// In en, this message translates to:
  /// **'Collect Against Dues'**
  String get collectAgainstDues;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @paymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment Recorded!'**
  String get paymentRecorded;

  /// No description provided for @confirmPayment.
  ///
  /// In en, this message translates to:
  /// **'Confirm · {amount}'**
  String confirmPayment(String amount);

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @balanceSummary.
  ///
  /// In en, this message translates to:
  /// **'Balance Summary'**
  String get balanceSummary;

  /// No description provided for @outstandingInvoices.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Invoices'**
  String get outstandingInvoices;

  /// No description provided for @due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get due;

  /// No description provided for @partialPaid.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get partialPaid;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @billGenerated.
  ///
  /// In en, this message translates to:
  /// **'Bill Generated!'**
  String get billGenerated;

  /// No description provided for @generateBill.
  ///
  /// In en, this message translates to:
  /// **'Generate Bill · {amount}'**
  String generateBill(String amount);

  /// No description provided for @searchCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Search customer...'**
  String get searchCustomerHint;

  /// No description provided for @dueAmount.
  ///
  /// In en, this message translates to:
  /// **'Due {amount}'**
  String dueAmount(String amount);

  /// No description provided for @cartEmptySnack.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get cartEmptySnack;

  /// No description provided for @failedToGenerateBill.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate bill: {error}'**
  String failedToGenerateBill(String error);

  /// No description provided for @enterPaymentSplitAmounts.
  ///
  /// In en, this message translates to:
  /// **'Enter payment split amounts'**
  String get enterPaymentSplitAmounts;

  /// No description provided for @splitTotalMismatch.
  ///
  /// In en, this message translates to:
  /// **'Split total mismatch by {amount}'**
  String splitTotalMismatch(String amount);

  /// No description provided for @invalidBillAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid bill amount'**
  String get invalidBillAmount;

  /// No description provided for @receivedAmountNegative.
  ///
  /// In en, this message translates to:
  /// **'Received amount cannot be negative'**
  String get receivedAmountNegative;

  /// No description provided for @searchByCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Search by customer or invoice #'**
  String get searchByCustomerHint;

  /// No description provided for @noMatchingBills.
  ///
  /// In en, this message translates to:
  /// **'No matching bills'**
  String get noMatchingBills;

  /// No description provided for @noBillsYet.
  ///
  /// In en, this message translates to:
  /// **'No bills yet'**
  String get noBillsYet;

  /// No description provided for @billsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Bill} other{{count} Bills}}'**
  String billsCount(int count);

  /// No description provided for @billDetail.
  ///
  /// In en, this message translates to:
  /// **'Bill Detail'**
  String get billDetail;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @noItemDetails.
  ///
  /// In en, this message translates to:
  /// **'No item details'**
  String get noItemDetails;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @billNotFound.
  ///
  /// In en, this message translates to:
  /// **'Bill not found'**
  String get billNotFound;

  /// No description provided for @invoicePreview.
  ///
  /// In en, this message translates to:
  /// **'Invoice Preview'**
  String get invoicePreview;

  /// No description provided for @paidStatus.
  ///
  /// In en, this message translates to:
  /// **'PAID'**
  String get paidStatus;

  /// No description provided for @invoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice #'**
  String get invoiceNumber;

  /// No description provided for @itemHeader.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get itemHeader;

  /// No description provided for @qtyHeader.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qtyHeader;

  /// No description provided for @priceHeader.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceHeader;

  /// No description provided for @totalHeader.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalHeader;

  /// No description provided for @grandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get grandTotal;

  /// No description provided for @scanToPay.
  ///
  /// In en, this message translates to:
  /// **'Scan to Pay'**
  String get scanToPay;

  /// No description provided for @addUpiIdHint.
  ///
  /// In en, this message translates to:
  /// **'Add your UPI ID in Shop Settings to show a QR code here.'**
  String get addUpiIdHint;

  /// No description provided for @thankYouShopping.
  ///
  /// In en, this message translates to:
  /// **'Thank you for shopping! 🙏'**
  String get thankYouShopping;

  /// No description provided for @generatedByVaani.
  ///
  /// In en, this message translates to:
  /// **'Generated by Vaani — AI Store Manager'**
  String get generatedByVaani;

  /// No description provided for @confirmSaveInvoice.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Save Invoice'**
  String get confirmSaveInvoice;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount: {amount}'**
  String amountLabel(String amount);

  /// No description provided for @periodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get periodToday;

  /// No description provided for @periodThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get periodThisWeek;

  /// No description provided for @periodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get periodThisMonth;

  /// No description provided for @periodThisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get periodThisYear;

  /// No description provided for @totalSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get totalSales;

  /// No description provided for @totalProfit.
  ///
  /// In en, this message translates to:
  /// **'Total Profit'**
  String get totalProfit;

  /// No description provided for @totalBills.
  ///
  /// In en, this message translates to:
  /// **'Total Bills'**
  String get totalBills;

  /// No description provided for @itemsSold.
  ///
  /// In en, this message translates to:
  /// **'Items Sold'**
  String get itemsSold;

  /// No description provided for @salesOverview.
  ///
  /// In en, this message translates to:
  /// **'Sales Overview'**
  String get salesOverview;

  /// No description provided for @topProducts.
  ///
  /// In en, this message translates to:
  /// **'Top Products'**
  String get topProducts;

  /// No description provided for @categoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Category not found'**
  String get categoryNotFound;

  /// No description provided for @createCategory.
  ///
  /// In en, this message translates to:
  /// **'Create Category'**
  String get createCategory;

  /// No description provided for @categoryNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter category name'**
  String get categoryNameHint;

  /// No description provided for @categoryCreated.
  ///
  /// In en, this message translates to:
  /// **'Category created'**
  String get categoryCreated;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select or create a category'**
  String get selectCategory;

  /// No description provided for @noCategoriesYet.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get noCategoriesYet;

  /// No description provided for @searchCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Search customers...'**
  String get searchCustomersHint;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get nameRequired;

  /// No description provided for @noCustomersYet.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get noCustomersYet;

  /// No description provided for @totalPurchases.
  ///
  /// In en, this message translates to:
  /// **'Total Purchases'**
  String get totalPurchases;

  /// No description provided for @totalBusiness.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get totalBusiness;

  /// No description provided for @recentInvoices.
  ///
  /// In en, this message translates to:
  /// **'Recent Invoices'**
  String get recentInvoices;

  /// No description provided for @allInvoices.
  ///
  /// In en, this message translates to:
  /// **'All Invoices'**
  String get allInvoices;

  /// No description provided for @customerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Customer not found'**
  String get customerNotFound;

  /// No description provided for @lastVisit.
  ///
  /// In en, this message translates to:
  /// **'Last visit: {date}'**
  String lastVisit(String date);

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @paymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get paymentHistory;

  /// No description provided for @ledger.
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get ledger;

  /// No description provided for @noInvoicesYet.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet'**
  String get noInvoicesYet;

  /// No description provided for @noPaymentHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No payment history'**
  String get noPaymentHistoryYet;

  /// No description provided for @noLedgerEntriesYet.
  ///
  /// In en, this message translates to:
  /// **'No ledger entries yet'**
  String get noLedgerEntriesYet;

  /// No description provided for @billPayment.
  ///
  /// In en, this message translates to:
  /// **'Bill Payment'**
  String get billPayment;

  /// No description provided for @advanceUsed.
  ///
  /// In en, this message translates to:
  /// **'Advance Used'**
  String get advanceUsed;

  /// No description provided for @outstandingCollected.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Collected'**
  String get outstandingCollected;

  /// No description provided for @advanceDeposit.
  ///
  /// In en, this message translates to:
  /// **'Advance Deposit'**
  String get advanceDeposit;

  /// No description provided for @billDue.
  ///
  /// In en, this message translates to:
  /// **'Bill Due'**
  String get billDue;

  /// No description provided for @billVoided.
  ///
  /// In en, this message translates to:
  /// **'Bill Voided'**
  String get billVoided;

  /// No description provided for @creditGiven.
  ///
  /// In en, this message translates to:
  /// **'Credit Given'**
  String get creditGiven;

  /// No description provided for @giveCredit.
  ///
  /// In en, this message translates to:
  /// **'Give Credit'**
  String get giveCredit;

  /// No description provided for @giveCreditTo.
  ///
  /// In en, this message translates to:
  /// **'Give credit to'**
  String get giveCreditTo;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// No description provided for @reasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. goods on credit, cash loan'**
  String get reasonHint;

  /// No description provided for @creditRecorded.
  ///
  /// In en, this message translates to:
  /// **'Credit Recorded!'**
  String get creditRecorded;

  /// No description provided for @youGave.
  ///
  /// In en, this message translates to:
  /// **'You Gave'**
  String get youGave;

  /// No description provided for @youGot.
  ///
  /// In en, this message translates to:
  /// **'You Got'**
  String get youGot;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @poweredByVaani.
  ///
  /// In en, this message translates to:
  /// **'Powered by Vaani'**
  String get poweredByVaani;

  /// No description provided for @askAnythingHint.
  ///
  /// In en, this message translates to:
  /// **'Ask anything about your store...'**
  String get askAnythingHint;

  /// No description provided for @aiGreeting.
  ///
  /// In en, this message translates to:
  /// **'👋 Hello, {name}! I\'m Vaani AI, your personal store manager.\n\nAsk me anything about your business — sales, profits, stock, customers.'**
  String aiGreeting(String name);

  /// No description provided for @aiSuggestionTopSeller.
  ///
  /// In en, this message translates to:
  /// **'What sold most today?'**
  String get aiSuggestionTopSeller;

  /// No description provided for @aiSuggestionRestock.
  ///
  /// In en, this message translates to:
  /// **'What should I restock?'**
  String get aiSuggestionRestock;

  /// No description provided for @aiSuggestionProfit.
  ///
  /// In en, this message translates to:
  /// **'What\'s my profit today?'**
  String get aiSuggestionProfit;

  /// No description provided for @aiSuggestionBillCount.
  ///
  /// In en, this message translates to:
  /// **'How many bills today?'**
  String get aiSuggestionBillCount;

  /// No description provided for @aiSuggestionBestCustomer.
  ///
  /// In en, this message translates to:
  /// **'Best customer this month?'**
  String get aiSuggestionBestCustomer;

  /// No description provided for @aiSuggestionWeekSales.
  ///
  /// In en, this message translates to:
  /// **'This week sales?'**
  String get aiSuggestionWeekSales;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @viewEditStoreDetails.
  ///
  /// In en, this message translates to:
  /// **'View and edit your store details'**
  String get viewEditStoreDetails;

  /// No description provided for @changeMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Change Mobile Number'**
  String get changeMobileNumber;

  /// No description provided for @updateLoginPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Update your login phone number'**
  String get updateLoginPhoneHint;

  /// No description provided for @business.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get business;

  /// No description provided for @gstTaxes.
  ///
  /// In en, this message translates to:
  /// **'GST & Taxes'**
  String get gstTaxes;

  /// No description provided for @configureTaxHint.
  ///
  /// In en, this message translates to:
  /// **'Configure tax settings'**
  String get configureTaxHint;

  /// No description provided for @shopDetails.
  ///
  /// In en, this message translates to:
  /// **'Shop Details'**
  String get shopDetails;

  /// No description provided for @updateShopHint.
  ///
  /// In en, this message translates to:
  /// **'Update shop name and address'**
  String get updateShopHint;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupRestore;

  /// No description provided for @exportImportHint.
  ///
  /// In en, this message translates to:
  /// **'Export or import your data'**
  String get exportImportHint;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @shareInvoicesCsv.
  ///
  /// In en, this message translates to:
  /// **'Share invoices as CSV'**
  String get shareInvoicesCsv;

  /// No description provided for @chooseTheme.
  ///
  /// In en, this message translates to:
  /// **'Choose Theme'**
  String get chooseTheme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get chooseLanguage;

  /// No description provided for @accountActions.
  ///
  /// In en, this message translates to:
  /// **'Account Actions'**
  String get accountActions;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirm;

  /// No description provided for @appFooter.
  ///
  /// In en, this message translates to:
  /// **'Vaani AI Store Manager v1.0.0\n© 2024 Vaani Technologies'**
  String get appFooter;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create Backup'**
  String get createBackup;

  /// No description provided for @backupHint.
  ///
  /// In en, this message translates to:
  /// **'Save a copy of your database to device storage.'**
  String get backupHint;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get creating;

  /// No description provided for @backupFiles.
  ///
  /// In en, this message translates to:
  /// **'Backup Files'**
  String get backupFiles;

  /// No description provided for @noBackupsFound.
  ///
  /// In en, this message translates to:
  /// **'No backups found'**
  String get noBackupsFound;

  /// No description provided for @restoreWarning.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Restoring will replace all current data. This cannot be undone.'**
  String get restoreWarning;

  /// No description provided for @selectBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Select Backup File'**
  String get selectBackupFile;

  /// No description provided for @selectBackupFileSnack.
  ///
  /// In en, this message translates to:
  /// **'Select a backup file to restore'**
  String get selectBackupFileSnack;

  /// No description provided for @backupCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created: {fileName}'**
  String backupCreated(String fileName);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @noProfileFound.
  ///
  /// In en, this message translates to:
  /// **'No profile found.'**
  String get noProfileFound;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @mobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get mobile;

  /// No description provided for @businessDetails.
  ///
  /// In en, this message translates to:
  /// **'Business Details'**
  String get businessDetails;

  /// No description provided for @shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop Name'**
  String get shopName;

  /// No description provided for @ownerName.
  ///
  /// In en, this message translates to:
  /// **'Owner Name'**
  String get ownerName;

  /// No description provided for @gstNumber.
  ///
  /// In en, this message translates to:
  /// **'GST Number'**
  String get gstNumber;

  /// No description provided for @taxSettings.
  ///
  /// In en, this message translates to:
  /// **'Tax Settings'**
  String get taxSettings;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and all store data. This action cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @logoutConfirmLong.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out of your account?'**
  String get logoutConfirmLong;

  /// No description provided for @shopInformation.
  ///
  /// In en, this message translates to:
  /// **'Shop Information'**
  String get shopInformation;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @paymentQr.
  ///
  /// In en, this message translates to:
  /// **'Payment & QR'**
  String get paymentQr;

  /// No description provided for @gstNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'GST Number (optional)'**
  String get gstNumberOptional;

  /// No description provided for @upiIdOptional.
  ///
  /// In en, this message translates to:
  /// **'UPI ID (optional)'**
  String get upiIdOptional;

  /// No description provided for @upiIdHint.
  ///
  /// In en, this message translates to:
  /// **'Your UPI ID will appear as a scannable QR on invoices when payment mode is UPI.'**
  String get upiIdHint;

  /// No description provided for @gstEnabled.
  ///
  /// In en, this message translates to:
  /// **'GST Enabled'**
  String get gstEnabled;

  /// No description provided for @applyGstHint.
  ///
  /// In en, this message translates to:
  /// **'Apply GST to invoices'**
  String get applyGstHint;

  /// No description provided for @defaultGstRate.
  ///
  /// In en, this message translates to:
  /// **'Default GST Rate'**
  String get defaultGstRate;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccess;

  /// No description provided for @failedToSave.
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {error}'**
  String failedToSave(String error);

  /// No description provided for @ownerNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter owner name'**
  String get ownerNameHint;

  /// No description provided for @shopNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter shop name (min 2 chars)'**
  String get shopNameHint;

  /// No description provided for @addressOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get addressOptionalLabel;

  /// No description provided for @couldNotPickImage.
  ///
  /// In en, this message translates to:
  /// **'Could not pick image: {error}'**
  String couldNotPickImage(String error);

  /// No description provided for @enterNewMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter New Mobile Number'**
  String get enterNewMobileNumber;

  /// No description provided for @otpVerificationHint.
  ///
  /// In en, this message translates to:
  /// **'We will send a verification code to confirm your new number.'**
  String get otpVerificationHint;

  /// No description provided for @newMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'New Mobile Number'**
  String get newMobileNumber;

  /// No description provided for @enter10DigitNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter 10-digit number'**
  String get enter10DigitNumber;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @verifyNewNumber.
  ///
  /// In en, this message translates to:
  /// **'Verify Your New Number'**
  String get verifyNewNumber;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit OTP sent to +91 {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get enterOtp;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change Number'**
  String get changeNumber;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendIn(String seconds);

  /// No description provided for @resendOtp.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get resendOtp;

  /// No description provided for @verifyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Verify & Update'**
  String get verifyUpdate;

  /// No description provided for @mobileUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Mobile number updated successfully'**
  String get mobileUpdatedSuccess;

  /// No description provided for @stepNewNumber.
  ///
  /// In en, this message translates to:
  /// **'New Number'**
  String get stepNewNumber;

  /// No description provided for @stepVerifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get stepVerifyOtp;

  /// No description provided for @enterMobileNumberValidator.
  ///
  /// In en, this message translates to:
  /// **'Enter mobile number'**
  String get enterMobileNumberValidator;

  /// No description provided for @enterValidIndianMobile.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Indian mobile number'**
  String get enterValidIndianMobile;

  /// No description provided for @enter6DigitOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit OTP'**
  String get enter6DigitOtp;

  /// No description provided for @incorrectOtp.
  ///
  /// In en, this message translates to:
  /// **'Incorrect or expired OTP. Please try again.'**
  String get incorrectOtp;

  /// No description provided for @otpSentToNumber.
  ///
  /// In en, this message translates to:
  /// **'OTP sent to +91 {phone}'**
  String otpSentToNumber(String phone);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorGeneric(String error);

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @enterOtpSentHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the OTP sent to your number'**
  String get enterOtpSentHint;

  /// No description provided for @signInHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage your store'**
  String get signInHint;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileNumber;

  /// No description provided for @verifyLogin.
  ///
  /// In en, this message translates to:
  /// **'Verify & Login'**
  String get verifyLogin;

  /// No description provided for @exploreDemoStore.
  ///
  /// In en, this message translates to:
  /// **'Explore with Demo Store'**
  String get exploreDemoStore;

  /// No description provided for @termsPrivacyNotice.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our Terms of Service\nand Privacy Policy.'**
  String get termsPrivacyNotice;

  /// No description provided for @settingUpDemoStore.
  ///
  /// In en, this message translates to:
  /// **'Setting up demo store...\nThis may take 30–60 seconds.'**
  String get settingUpDemoStore;

  /// No description provided for @demoSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Demo setup failed: {error}'**
  String demoSetupFailed(String error);

  /// No description provided for @loginError.
  ///
  /// In en, this message translates to:
  /// **'Login error: {error}'**
  String loginError(String error);

  /// No description provided for @onboardTitle1.
  ///
  /// In en, this message translates to:
  /// **'Voice Billing'**
  String get onboardTitle1;

  /// No description provided for @onboardSubtitle1.
  ///
  /// In en, this message translates to:
  /// **'Just speak product names to add them to cart instantly. Bill 10x faster.'**
  String get onboardSubtitle1;

  /// No description provided for @onboardTitle2.
  ///
  /// In en, this message translates to:
  /// **'Smart Inventory'**
  String get onboardTitle2;

  /// No description provided for @onboardSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'Stock auto-deducts on every sale. Get alerts before you run out.'**
  String get onboardSubtitle2;

  /// No description provided for @onboardTitle3.
  ///
  /// In en, this message translates to:
  /// **'Business Reports'**
  String get onboardTitle3;

  /// No description provided for @onboardSubtitle3.
  ///
  /// In en, this message translates to:
  /// **'Know your daily profit, top products, and best customers at a glance.'**
  String get onboardSubtitle3;

  /// No description provided for @onboardTitle4.
  ///
  /// In en, this message translates to:
  /// **'Works Offline'**
  String get onboardTitle4;

  /// No description provided for @onboardSubtitle4.
  ///
  /// In en, this message translates to:
  /// **'No internet? No problem. Vaani works completely offline, always.'**
  String get onboardSubtitle4;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @setupYourShop.
  ///
  /// In en, this message translates to:
  /// **'Setup Your Shop'**
  String get setupYourShop;

  /// No description provided for @enterShopDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your shop details'**
  String get enterShopDetailsHint;

  /// No description provided for @shopNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Shop Name *'**
  String get shopNameRequired;

  /// No description provided for @ownerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Owner Name *'**
  String get ownerNameRequired;

  /// No description provided for @gstNumberOptionalCaps.
  ///
  /// In en, this message translates to:
  /// **'GST Number (Optional)'**
  String get gstNumberOptionalCaps;

  /// No description provided for @addressOptionalCaps.
  ///
  /// In en, this message translates to:
  /// **'Address (Optional)'**
  String get addressOptionalCaps;

  /// No description provided for @saveContinue.
  ///
  /// In en, this message translates to:
  /// **'Save & Continue'**
  String get saveContinue;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @helpComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Help & Support — coming soon!'**
  String get helpComingSoon;

  /// No description provided for @myShopFallback.
  ///
  /// In en, this message translates to:
  /// **'My Shop'**
  String get myShopFallback;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening'**
  String get greetingEvening;

  /// No description provided for @greetingFallbackName.
  ///
  /// In en, this message translates to:
  /// **'there'**
  String get greetingFallbackName;

  /// No description provided for @homeSubtitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what\'s happening today.'**
  String get homeSubtitleFallback;

  /// No description provided for @categorySoftDrinks.
  ///
  /// In en, this message translates to:
  /// **'Soft Drinks'**
  String get categorySoftDrinks;

  /// No description provided for @categorySnacks.
  ///
  /// In en, this message translates to:
  /// **'Snacks'**
  String get categorySnacks;

  /// No description provided for @categoryDairy.
  ///
  /// In en, this message translates to:
  /// **'Dairy'**
  String get categoryDairy;

  /// No description provided for @categoryChocolates.
  ///
  /// In en, this message translates to:
  /// **'Chocolates'**
  String get categoryChocolates;

  /// No description provided for @categoryBiscuits.
  ///
  /// In en, this message translates to:
  /// **'Biscuits'**
  String get categoryBiscuits;

  /// No description provided for @categoryNoodles.
  ///
  /// In en, this message translates to:
  /// **'Noodles'**
  String get categoryNoodles;

  /// No description provided for @categoryChips.
  ///
  /// In en, this message translates to:
  /// **'Chips'**
  String get categoryChips;

  /// No description provided for @categoryPersonalCare.
  ///
  /// In en, this message translates to:
  /// **'Personal Care'**
  String get categoryPersonalCare;

  /// No description provided for @categoryStationery.
  ///
  /// In en, this message translates to:
  /// **'Stationery'**
  String get categoryStationery;

  /// No description provided for @categoryCleaningProducts.
  ///
  /// In en, this message translates to:
  /// **'Cleaning Products'**
  String get categoryCleaningProducts;

  /// No description provided for @categoryGrocery.
  ///
  /// In en, this message translates to:
  /// **'Grocery'**
  String get categoryGrocery;

  /// No description provided for @categoryOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get categoryOthers;

  /// No description provided for @qtyLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} qty'**
  String qtyLabel(String count);

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @productDeleted.
  ///
  /// In en, this message translates to:
  /// **'Product deleted'**
  String get productDeleted;

  /// No description provided for @itemCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} item} other{{count} items}}'**
  String itemCountLabel(int count);

  /// No description provided for @outOfStockBadge.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStockBadge;

  /// No description provided for @inStockQty.
  ///
  /// In en, this message translates to:
  /// **'In Stock · {count}'**
  String inStockQty(String count);

  /// No description provided for @qtyColon.
  ///
  /// In en, this message translates to:
  /// **'Qty: {count}'**
  String qtyColon(String count);

  /// No description provided for @notFoundParen.
  ///
  /// In en, this message translates to:
  /// **'{name} (not found)'**
  String notFoundParen(String name);

  /// No description provided for @clearCartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear cart'**
  String get clearCartTooltip;

  /// No description provided for @pdfInvoiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice: {number}'**
  String pdfInvoiceLabel(String number);

  /// No description provided for @pdfCustomerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer: {name}'**
  String pdfCustomerLabel(String name);

  /// No description provided for @pdfPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment: {mode}'**
  String pdfPaymentLabel(String mode);

  /// No description provided for @pdfGstinLabel.
  ///
  /// In en, this message translates to:
  /// **'GSTIN: {number}'**
  String pdfGstinLabel(String number);

  /// No description provided for @rateHeader.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rateHeader;

  /// No description provided for @paymentSplitLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Split:'**
  String get paymentSplitLabel;

  /// No description provided for @scanToPayUpi.
  ///
  /// In en, this message translates to:
  /// **'Scan to Pay via UPI'**
  String get scanToPayUpi;

  /// No description provided for @needMoreOrLess.
  ///
  /// In en, this message translates to:
  /// **'Need {amount} {direction}'**
  String needMoreOrLess(String amount, String direction);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get more;

  /// No description provided for @less.
  ///
  /// In en, this message translates to:
  /// **'less'**
  String get less;

  /// No description provided for @shopFallback.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopFallback;

  /// No description provided for @listeningEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get listeningEllipsis;

  /// No description provided for @addedLabel.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get addedLabel;

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday · {time}'**
  String yesterdayAt(String time);

  /// No description provided for @printShare.
  ///
  /// In en, this message translates to:
  /// **'Print / Share'**
  String get printShare;

  /// No description provided for @gstColonLabel.
  ///
  /// In en, this message translates to:
  /// **'GST: {number}'**
  String gstColonLabel(String number);

  /// No description provided for @unitsSoldSummary.
  ///
  /// In en, this message translates to:
  /// **'{qty} units • {revenue}'**
  String unitsSoldSummary(String qty, String revenue);

  /// No description provided for @pcsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pcs'**
  String pcsCount(String count);

  /// No description provided for @billsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Bill} other{{count} Bills}}'**
  String billsCountLabel(int count);

  /// No description provided for @gstEnabledPercent.
  ///
  /// In en, this message translates to:
  /// **'Enabled ({rate}%)'**
  String gstEnabledPercent(String rate);

  /// No description provided for @tapToChangeLogo.
  ///
  /// In en, this message translates to:
  /// **'Tap to change logo'**
  String get tapToChangeLogo;

  /// No description provided for @resendOtpIn.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP in {seconds}s'**
  String resendOtpIn(String seconds);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
