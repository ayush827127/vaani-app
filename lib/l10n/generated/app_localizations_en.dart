// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Vaani';

  @override
  String get aiStoreManagerTagline => 'AI Store Manager';

  @override
  String get speakBillDone => 'Speak. Bill. Done.';

  @override
  String get home => 'Home';

  @override
  String get items => 'Items';

  @override
  String get billing => 'Billing';

  @override
  String get customers => 'Customers';

  @override
  String get reports => 'Reports';

  @override
  String get bills => 'Bills';

  @override
  String get aiManager => 'AI Manager';

  @override
  String get settings => 'Settings';

  @override
  String get profile => 'Profile';

  @override
  String get help => 'Help';

  @override
  String get logout => 'Logout';

  @override
  String get newBill => 'New Bill';

  @override
  String get notifications => 'Notifications';

  @override
  String get language => 'Language';

  @override
  String get theme => 'Theme';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get search => 'Search';

  @override
  String get today => 'Today';

  @override
  String get viewAll => 'View All';

  @override
  String get update => 'Update';

  @override
  String get edit => 'Edit';

  @override
  String get export => 'Export';

  @override
  String get import => 'Import';

  @override
  String get backup => 'Backup';

  @override
  String get restore => 'Restore';

  @override
  String get preferences => 'Preferences';

  @override
  String get tax => 'Tax';

  @override
  String get discount => 'Discount';

  @override
  String get total => 'Total';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get payment => 'Payment';

  @override
  String get cash => 'Cash';

  @override
  String get upi => 'UPI';

  @override
  String get card => 'Card';

  @override
  String get credit => 'Credit';

  @override
  String get mixed => 'Mixed';

  @override
  String get item => 'Item';

  @override
  String get quantity => 'Quantity';

  @override
  String get price => 'Price';

  @override
  String get category => 'Category';

  @override
  String get margin => 'Margin';

  @override
  String get invoice => 'Invoice';

  @override
  String get paid => 'Paid';

  @override
  String get pending => 'Pending';

  @override
  String get completed => 'Completed';

  @override
  String get draft => 'Draft';

  @override
  String get proceed => 'Proceed';

  @override
  String get walkInCustomer => 'Walk-in Customer';

  @override
  String get walkIn => 'Walk-in';

  @override
  String get customerLabel => 'Customer';

  @override
  String get revenue => 'Revenue';

  @override
  String get profit => 'Profit';

  @override
  String get inventory => 'Inventory';

  @override
  String get stock => 'Stock';

  @override
  String get todaysSales => 'Today\'s Sales';

  @override
  String get recentBills => 'Recent Bills';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get all => 'All';

  @override
  String get clear => 'Clear';

  @override
  String get change => 'Change';

  @override
  String get remove => 'Remove';

  @override
  String get apply => 'Apply';

  @override
  String get next => 'Next';

  @override
  String get skip => 'Skip';

  @override
  String get date => 'Date';

  @override
  String get phone => 'Phone';

  @override
  String get address => 'Address';

  @override
  String get or => 'or';

  @override
  String get download => 'Download';

  @override
  String get gst => 'GST';

  @override
  String get currency => 'Currency';

  @override
  String get required => 'Required';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get fromYesterday => 'from yesterday';

  @override
  String get newCustomers => 'New Customers';

  @override
  String get todaysProfit => 'Today\'s Profit';

  @override
  String get noBillsToday => 'No bills yet today';

  @override
  String get voiceBill => 'Voice Bill';

  @override
  String get addItem => 'Add Item';

  @override
  String get sevenDayRevenue => '7-Day Revenue';

  @override
  String get viewReports => 'View Reports';

  @override
  String lowStockBadge(String count) {
    return '$count low';
  }

  @override
  String get searchItemsHint => 'Search items, SKU, barcode...';

  @override
  String get sortNameAZ => 'Name A–Z';

  @override
  String get sortNameZA => 'Name Z–A';

  @override
  String get sortStockLowHigh => 'Stock Low–High';

  @override
  String get sortStockHighLow => 'Stock High–Low';

  @override
  String get sortRecentlyAdded => 'Recently Added';

  @override
  String itemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Items',
      one: '$count Item',
    );
    return '$_temp0';
  }

  @override
  String get filterByStock => 'Filter by Stock';

  @override
  String get allItems => 'All Items';

  @override
  String get lowStock => 'Low Stock';

  @override
  String get outOfStock => 'Out of Stock';

  @override
  String get deleteItem => 'Delete Item';

  @override
  String deleteItemConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String noItemsMatch(String query) {
    return 'No items match \"$query\"';
  }

  @override
  String get noItemsYet => 'No items yet';

  @override
  String get addFirstItemHint => 'Add your first item to get started';

  @override
  String get inStock => 'In Stock';

  @override
  String get lowLabel => 'Low';

  @override
  String get outLabel => 'Out';

  @override
  String marginPercent(String percent) {
    return '$percent% margin';
  }

  @override
  String get viewDetails => 'View Details';

  @override
  String get addStock => 'Add Stock';

  @override
  String currentStock(String count) {
    return 'Current stock: $count units';
  }

  @override
  String get unitsToAdd => 'Units to add';

  @override
  String get adjustStock => 'Adjust Stock';

  @override
  String get unitsToRemoveAdjust => 'Units to remove / adjust';

  @override
  String get confirmAdjustment => 'Confirm Adjustment';

  @override
  String removeItemConfirm(String name) {
    return 'Remove \"$name\" from inventory? This cannot be undone.';
  }

  @override
  String get itemNotFound => 'Item not found.';

  @override
  String get sellingPrice => 'Selling Price';

  @override
  String get costPrice => 'Cost Price';

  @override
  String get profitMargin => 'Profit Margin';

  @override
  String get gstRate => 'GST Rate';

  @override
  String get stockLevel => 'Stock Level';

  @override
  String get unitsLabel => 'units';

  @override
  String reorderAt(String count) {
    return 'Reorder at $count units';
  }

  @override
  String stockValue(String value) {
    return 'Stock value: $value';
  }

  @override
  String get itemDetails => 'Item Details';

  @override
  String get skuCode => 'SKU / Code';

  @override
  String get reorderLevel => 'Reorder Level';

  @override
  String get addedOn => 'Added On';

  @override
  String get lastUpdated => 'Last Updated';

  @override
  String get voiceAliases => 'Voice Aliases';

  @override
  String get adjust => 'Adjust';

  @override
  String get editItem => 'Edit Item';

  @override
  String get chooseFromGallery => 'Choose from Gallery';

  @override
  String get takeAPhoto => 'Take a Photo';

  @override
  String get removeImage => 'Remove Image';

  @override
  String get tapToChangeImage => 'Tap to change image';

  @override
  String get addItemImage => 'Add item image';

  @override
  String get itemName => 'Item Name *';

  @override
  String get skuPhoneCode => 'SKU / Phone Code';

  @override
  String get costPriceCurrency => 'Cost Price (₹)';

  @override
  String get sellingPriceCurrency => 'Selling Price (₹) *';

  @override
  String get mustBeGreaterThanZero => 'Must be > 0';

  @override
  String get stockQuantity => 'Stock Quantity';

  @override
  String get aliasesLabel => 'Aliases (comma-separated)';

  @override
  String get updateItem => 'Update Item';

  @override
  String get saveItem => 'Save Item';

  @override
  String get itemUpdated => 'Item updated';

  @override
  String get itemAdded => 'Item added';

  @override
  String get barcode => 'Barcode';

  @override
  String get scanBarcode => 'Scan Barcode';

  @override
  String get generateBarcode => 'Generate Barcode';

  @override
  String get removeBarcode => 'Remove Barcode';

  @override
  String get barcodePreview => 'Barcode Preview';

  @override
  String get printBarcode => 'Print Barcode';

  @override
  String get printing => 'Printing…';

  @override
  String get previewPrint => 'Preview & Print';

  @override
  String get noBarcodeAssigned => 'No barcode assigned.';

  @override
  String get barcodeNotRegistered => 'Barcode not registered.';

  @override
  String get duplicateBarcodeError =>
      'Barcode already in use. Please use a unique barcode.';

  @override
  String get searchItemsByNameHint => 'Search items by name, SKU or barcode...';

  @override
  String get gridView => 'Grid';

  @override
  String get listView => 'List';

  @override
  String get cartEmpty => 'Cart is empty';

  @override
  String get clearCart => 'Clear Cart';

  @override
  String get removeAllItemsConfirm => 'Remove all items from cart?';

  @override
  String get addDiscount => 'Add Discount';

  @override
  String taxLabel(String amount) {
    return 'Tax: $amount';
  }

  @override
  String youSave(String amount) {
    return 'You save $amount';
  }

  @override
  String payAmount(String amount) {
    return 'Pay $amount';
  }

  @override
  String get selectCustomer => 'Select Customer';

  @override
  String get percentageOption => 'Percentage (%)';

  @override
  String get flatAmountOption => 'Flat Amount (₹)';

  @override
  String get listeningTapToStop => 'Listening... tap to stop';

  @override
  String get tapMicSpeakAgain => 'Tap mic to speak again';

  @override
  String get tapMicToSpeak => 'Tap mic to speak';

  @override
  String get micUnavailable => 'Microphone unavailable';

  @override
  String addItemsToCart(String count) {
    return 'Add $count item(s) to Cart';
  }

  @override
  String get speakAgain => 'Speak again';

  @override
  String get recognizedText => 'Recognized Text';

  @override
  String itemsFoundCount(String count) {
    return 'Items Found ($count)';
  }

  @override
  String addedToCartCount(String count) {
    return '$count items added to cart';
  }

  @override
  String get notFoundSuffix => '(Not found)';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get voiceBillingTitle => 'Voice Billing';

  @override
  String get tapToSpeak => 'Tap to speak';

  @override
  String get walkInCustomerLabel => 'Walk-in Customer';

  @override
  String get addCustomer => 'Add Customer';

  @override
  String get editCustomer => 'Edit Customer';

  @override
  String get email => 'Email';

  @override
  String get addCustomerImage => 'Add customer photo';

  @override
  String get customerUpdated => 'Customer updated';

  @override
  String get customerFilterAll => 'All';

  @override
  String get customerFilterRegular => 'Regular';

  @override
  String get customerFilterNew => 'New';

  @override
  String get customerFilterInactive => 'Inactive';

  @override
  String get customersSubtitle => 'Manage your customer ledger';

  @override
  String get totalDueLabel => 'Total Due';

  @override
  String get totalAdvanceLabel => 'Total Advance';

  @override
  String customersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count customers',
      one: '1 customer',
    );
    return '$_temp0';
  }

  @override
  String get searchNameOrPhoneHint => 'Search by name or phone number...';

  @override
  String get ledgerFilterWithDue => 'With Due';

  @override
  String get ledgerFilterWithAdvance => 'With Advance';

  @override
  String get ledgerFilterSettled => 'Settled';

  @override
  String get sortRecent => 'Recent';

  @override
  String get sortOldest => 'Oldest';

  @override
  String get sortHighestDue => 'Highest Due';

  @override
  String get sortHighestAdvance => 'Highest Advance';

  @override
  String get sortLabel => 'Sort';

  @override
  String allCustomersHeading(int count) {
    return 'All Customers ($count)';
  }

  @override
  String get advanceLabel => 'Advance';

  @override
  String get addLabel => 'Add';

  @override
  String get noCustomersFound => 'No customers found';

  @override
  String get billsSubtitle => 'View and manage your bills';

  @override
  String get thisMonth => 'This Month';

  @override
  String get resetFilters => 'Reset filters';

  @override
  String get noPurchasesYet => 'No purchases yet';

  @override
  String get previousDue => 'Previous Due';

  @override
  String get previousDueInfo => 'Unpaid amount from previous bills';

  @override
  String get receiveAmount => 'Receive Amount';

  @override
  String get remainingDue => 'Remaining Due';

  @override
  String get advanceBalance => 'Advance Balance';

  @override
  String applyAdvance(String amount) {
    return 'Apply advance balance ($amount)';
  }

  @override
  String get advanceApplied => 'Advance Applied';

  @override
  String get netDue => 'Net Bill';

  @override
  String get oldDuesReduced => 'Previous Outstanding Reduced';

  @override
  String get addedToAdvance => 'Added to Advance';

  @override
  String get newAdvanceBalance => 'New Advance Balance';

  @override
  String get totalAmount => 'Total Amount';

  @override
  String get currentBill => 'Current Bill';

  @override
  String get received => 'Received';

  @override
  String get paymentMethod => 'Payment Method';

  @override
  String get partialPaymentRequiresCustomer =>
      'Partial payment requires a customer.';

  @override
  String get newOutstanding => 'New Outstanding';

  @override
  String get collectPayment => 'Collect Payment';

  @override
  String get outstanding => 'Outstanding';

  @override
  String get depositAsAdvance => 'Deposit as Advance';

  @override
  String get collectAgainstDues => 'Collect Against Dues';

  @override
  String get amount => 'Amount';

  @override
  String get paymentRecorded => 'Payment Recorded!';

  @override
  String confirmPayment(String amount) {
    return 'Confirm · $amount';
  }

  @override
  String get enterValidAmount => 'Please enter a valid amount';

  @override
  String get balanceSummary => 'Balance Summary';

  @override
  String get outstandingInvoices => 'Outstanding Invoices';

  @override
  String get due => 'Due';

  @override
  String get partialPaid => 'Partial';

  @override
  String get unpaid => 'Unpaid';

  @override
  String get billGenerated => 'Bill Generated!';

  @override
  String generateBill(String amount) {
    return 'Generate Bill · $amount';
  }

  @override
  String get searchCustomerHint => 'Search customer...';

  @override
  String get noCustomersFoundInSearch => 'No customers found';

  @override
  String dueAmount(String amount) {
    return 'Due $amount';
  }

  @override
  String get cartEmptySnack => 'Cart is empty';

  @override
  String failedToGenerateBill(String error) {
    return 'Failed to generate bill: $error';
  }

  @override
  String get enterPaymentSplitAmounts => 'Enter payment split amounts';

  @override
  String splitTotalMismatch(String amount) {
    return 'Split total mismatch by $amount';
  }

  @override
  String get invalidBillAmount => 'Invalid bill amount';

  @override
  String get receivedAmountNegative => 'Received amount cannot be negative';

  @override
  String get searchByCustomerHint => 'Search by customer or invoice #';

  @override
  String get noMatchingBills => 'No matching bills';

  @override
  String get noBillsYet => 'No bills yet';

  @override
  String billsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bills',
      one: '1 Bill',
    );
    return '$_temp0';
  }

  @override
  String get billDetail => 'Bill Detail';

  @override
  String get summary => 'Summary';

  @override
  String get billNotFound => 'Bill not found';

  @override
  String get invoicePreview => 'Invoice Preview';

  @override
  String get paidStatus => 'PAID';

  @override
  String get invoiceNumber => 'Invoice #';

  @override
  String get itemHeader => 'Item';

  @override
  String get qtyHeader => 'Qty';

  @override
  String get priceHeader => 'Price';

  @override
  String get totalHeader => 'Total';

  @override
  String get grandTotal => 'Grand Total';

  @override
  String get scanToPay => 'Scan to Pay';

  @override
  String get addUpiIdHint =>
      'Add your UPI ID in Shop Settings to show a QR code here.';

  @override
  String get thankYouShopping => 'Thank you for shopping! 🙏';

  @override
  String get generatedByVaani => 'Generated by Vaani — AI Store Manager';

  @override
  String get confirmSaveInvoice => 'Confirm & Save Invoice';

  @override
  String amountLabel(String amount) {
    return 'Amount: $amount';
  }

  @override
  String get periodToday => 'Today';

  @override
  String get periodThisWeek => 'This Week';

  @override
  String get periodThisMonth => 'This Month';

  @override
  String get periodThisYear => 'This Year';

  @override
  String get totalSales => 'Total Sales';

  @override
  String get totalProfit => 'Total Profit';

  @override
  String get totalBills => 'Total Bills';

  @override
  String get itemsSold => 'Items Sold';

  @override
  String get salesOverview => 'Sales Overview';

  @override
  String get topItems => 'Top Items';

  @override
  String get categoryNotFound => 'Category not found';

  @override
  String get createCategory => 'Create Category';

  @override
  String get categoryNameHint => 'Enter category name';

  @override
  String get categoryCreated => 'Category created';

  @override
  String get selectCategory => 'Select or create a category';

  @override
  String get noCategoriesYet => 'No categories yet';

  @override
  String get searchCustomersHint => 'Search customers...';

  @override
  String get nameRequired => 'Name *';

  @override
  String get noCustomersYet => 'No customers yet';

  @override
  String get totalPurchases => 'Total Purchases';

  @override
  String get totalBusiness => 'Total Sales';

  @override
  String get recentInvoices => 'Recent Invoices';

  @override
  String get allInvoices => 'All Invoices';

  @override
  String get customerNotFound => 'Customer not found';

  @override
  String lastVisit(String date) {
    return 'Last visit: $date';
  }

  @override
  String get overview => 'Overview';

  @override
  String get paymentHistory => 'Payment History';

  @override
  String get ledger => 'Ledger';

  @override
  String get noInvoicesYet => 'No invoices yet';

  @override
  String get noPaymentHistoryYet => 'No payment history';

  @override
  String get noLedgerEntriesYet => 'No ledger entries yet';

  @override
  String get billPayment => 'Bill Payment';

  @override
  String get advanceUsed => 'Advance Used';

  @override
  String get outstandingCollected => 'Outstanding Collected';

  @override
  String get advanceDeposit => 'Advance Deposit';

  @override
  String get billDue => 'Bill Due';

  @override
  String get billVoided => 'Bill Voided';

  @override
  String get creditGiven => 'Credit Given';

  @override
  String get giveCredit => 'Give Credit';

  @override
  String get giveCreditTo => 'Give credit to';

  @override
  String get reasonOptional => 'Reason (optional)';

  @override
  String get reasonHint => 'e.g. goods on credit, cash loan';

  @override
  String get creditRecorded => 'Credit Recorded!';

  @override
  String get youGave => 'You Gave';

  @override
  String get youGot => 'You Got';

  @override
  String get balance => 'Balance';

  @override
  String get poweredByVaani => 'Powered by Vaani';

  @override
  String get askAnythingHint => 'Ask anything about your store...';

  @override
  String aiGreeting(String name) {
    return '👋 Hello, $name! I\'m Vaani AI, your personal store manager.\n\nAsk me anything about your business — sales, profits, stock, customers.';
  }

  @override
  String get aiSuggestionTopSeller => 'What sold most today?';

  @override
  String get aiSuggestionRestock => 'What should I restock?';

  @override
  String get aiSuggestionProfit => 'What\'s my profit today?';

  @override
  String get aiSuggestionBillCount => 'How many bills today?';

  @override
  String get aiSuggestionBestCustomer => 'Best customer this month?';

  @override
  String get aiSuggestionWeekSales => 'This week sales?';

  @override
  String get account => 'Account';

  @override
  String get myProfile => 'My Profile';

  @override
  String get viewEditStoreDetails => 'View and edit your store details';

  @override
  String get changeMobileNumber => 'Change Mobile Number';

  @override
  String get updateLoginPhoneHint => 'Update your login phone number';

  @override
  String get business => 'Business';

  @override
  String get gstTaxes => 'GST & Taxes';

  @override
  String get configureTaxHint => 'Configure tax settings';

  @override
  String get shopDetails => 'Shop Details';

  @override
  String get updateShopHint => 'Update shop name and address';

  @override
  String get data => 'Data';

  @override
  String get backupRestore => 'Backup & Restore';

  @override
  String get exportImportHint => 'Export or import your data';

  @override
  String get exportData => 'Export Data';

  @override
  String get shareInvoicesCsv => 'Share invoices as CSV';

  @override
  String get chooseTheme => 'Choose Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System Default';

  @override
  String get chooseLanguage => 'Choose Language';

  @override
  String get accountActions => 'Account Actions';

  @override
  String get logoutConfirm => 'Are you sure you want to log out?';

  @override
  String get appFooter =>
      'Vaani AI Store Manager v1.0.0\n© 2024 Vaani Technologies';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get createBackup => 'Create Backup';

  @override
  String get backupHint => 'Save a copy of your database to device storage.';

  @override
  String get creating => 'Creating...';

  @override
  String get backupFiles => 'Backup Files';

  @override
  String get noBackupsFound => 'No backups found';

  @override
  String get restoreWarning =>
      '⚠️ Restoring will replace all current data. This cannot be undone.';

  @override
  String get selectBackupFile => 'Select Backup File';

  @override
  String get selectBackupFileSnack => 'Select a backup file to restore';

  @override
  String backupCreated(String fileName) {
    return 'Backup created: $fileName';
  }

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get noProfileFound => 'No profile found.';

  @override
  String get contact => 'Contact';

  @override
  String get mobile => 'Mobile';

  @override
  String get businessDetails => 'Business Details';

  @override
  String get shopName => 'Shop Name';

  @override
  String get ownerName => 'Owner Name';

  @override
  String get gstNumber => 'GST Number';

  @override
  String get taxSettings => 'Tax Settings';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountWarning =>
      'This will permanently delete your account and all store data. This action cannot be undone.';

  @override
  String get logoutConfirmLong =>
      'Are you sure you want to log out of your account?';

  @override
  String get shopInformation => 'Shop Information';

  @override
  String get legal => 'Legal';

  @override
  String get paymentQr => 'Payment & QR';

  @override
  String get gstNumberOptional => 'GST Number (optional)';

  @override
  String get upiIdOptional => 'UPI ID (optional)';

  @override
  String get upiIdHint =>
      'Your UPI ID will appear as a scannable QR on invoices when payment mode is UPI.';

  @override
  String get gstEnabled => 'GST Enabled';

  @override
  String get applyGstHint => 'Apply GST to invoices';

  @override
  String get defaultGstRate => 'Default GST Rate';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get profileUpdatedSuccess => 'Profile updated successfully';

  @override
  String failedToSave(String error) {
    return 'Failed to save: $error';
  }

  @override
  String get ownerNameHint => 'Enter owner name';

  @override
  String get shopNameHint => 'Enter shop name (min 2 chars)';

  @override
  String get addressOptionalLabel => 'Address (optional)';

  @override
  String couldNotPickImage(String error) {
    return 'Could not pick image: $error';
  }

  @override
  String get enterNewMobileNumber => 'Enter New Mobile Number';

  @override
  String get otpVerificationHint =>
      'We will send a verification code to confirm your new number.';

  @override
  String get newMobileNumber => 'New Mobile Number';

  @override
  String get enter10DigitNumber => 'Enter 10-digit number';

  @override
  String get sendOtp => 'Send OTP';

  @override
  String get verifyNewNumber => 'Verify Your New Number';

  @override
  String otpSentTo(String phone) {
    return 'Enter the 6-digit OTP sent to +91 $phone';
  }

  @override
  String get enterOtp => 'Enter OTP';

  @override
  String get changeNumber => 'Change Number';

  @override
  String resendIn(String seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get resendOtp => 'Resend OTP';

  @override
  String get verifyUpdate => 'Verify & Update';

  @override
  String get mobileUpdatedSuccess => 'Mobile number updated successfully';

  @override
  String get stepNewNumber => 'New Number';

  @override
  String get stepVerifyOtp => 'Verify OTP';

  @override
  String get enterMobileNumberValidator => 'Enter mobile number';

  @override
  String get enterValidIndianMobile => 'Enter a valid Indian mobile number';

  @override
  String get enter6DigitOtp => 'Enter the 6-digit OTP';

  @override
  String get incorrectOtp => 'Incorrect or expired OTP. Please try again.';

  @override
  String otpSentToNumber(String phone) {
    return 'OTP sent to +91 $phone';
  }

  @override
  String errorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get welcomeBack => 'Welcome Back';

  @override
  String get enterOtpSentHint => 'Enter the OTP sent to your number';

  @override
  String get signInHint => 'Sign in to manage your store';

  @override
  String get mobileNumber => 'Mobile Number';

  @override
  String get verifyLogin => 'Verify & Login';

  @override
  String get exploreDemoStore => 'Explore with Demo Store';

  @override
  String get termsPrivacyNotice =>
      'By continuing, you agree to our Terms of Service\nand Privacy Policy.';

  @override
  String get settingUpDemoStore =>
      'Setting up demo store...\nThis may take 30–60 seconds.';

  @override
  String demoSetupFailed(String error) {
    return 'Demo setup failed: $error';
  }

  @override
  String loginError(String error) {
    return 'Login error: $error';
  }

  @override
  String get onboardTitle1 => 'Voice Billing';

  @override
  String get onboardSubtitle1 =>
      'Just speak item names to add them to cart instantly. Bill 10x faster.';

  @override
  String get onboardTitle2 => 'Smart Inventory';

  @override
  String get onboardSubtitle2 =>
      'Stock auto-deducts on every sale. Get alerts before you run out.';

  @override
  String get onboardTitle3 => 'Business Reports';

  @override
  String get onboardSubtitle3 =>
      'Know your daily profit, top items, and best customers at a glance.';

  @override
  String get onboardTitle4 => 'Works Offline';

  @override
  String get onboardSubtitle4 =>
      'No internet? No problem. Vaani works completely offline, always.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get setupYourShop => 'Setup Your Shop';

  @override
  String get enterShopDetailsHint => 'Enter your shop details';

  @override
  String get shopNameRequired => 'Shop Name *';

  @override
  String get ownerNameRequired => 'Owner Name *';

  @override
  String get gstNumberOptionalCaps => 'GST Number (Optional)';

  @override
  String get addressOptionalCaps => 'Address (Optional)';

  @override
  String get saveContinue => 'Save & Continue';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get helpComingSoon => 'Help & Support — coming soon!';

  @override
  String get myShopFallback => 'My Shop';

  @override
  String get greetingMorning => 'Good Morning';

  @override
  String get greetingAfternoon => 'Good Afternoon';

  @override
  String get greetingEvening => 'Good Evening';

  @override
  String get greetingFallbackName => 'there';

  @override
  String get homeSubtitleFallback => 'Here\'s what\'s happening today.';

  @override
  String get categorySoftDrinks => 'Soft Drinks';

  @override
  String get categorySnacks => 'Snacks';

  @override
  String get categoryDairy => 'Dairy';

  @override
  String get categoryChocolates => 'Chocolates';

  @override
  String get categoryBiscuits => 'Biscuits';

  @override
  String get categoryNoodles => 'Noodles';

  @override
  String get categoryChips => 'Chips';

  @override
  String get categoryPersonalCare => 'Personal Care';

  @override
  String get categoryStationery => 'Stationery';

  @override
  String get categoryCleaningItems => 'Cleaning Items';

  @override
  String get categoryGrocery => 'Grocery';

  @override
  String get categoryOthers => 'Others';

  @override
  String qtyLabel(String count) {
    return '$count qty';
  }

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get itemDeleted => 'Item deleted';

  @override
  String itemCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get outOfStockBadge => 'Out of Stock';

  @override
  String inStockQty(String count) {
    return 'In Stock · $count';
  }

  @override
  String qtyColon(String count) {
    return 'Qty: $count';
  }

  @override
  String notFoundParen(String name) {
    return '$name (not found)';
  }

  @override
  String get clearCartTooltip => 'Clear cart';

  @override
  String pdfInvoiceLabel(String number) {
    return 'Invoice: $number';
  }

  @override
  String pdfCustomerLabel(String name) {
    return 'Customer: $name';
  }

  @override
  String pdfPaymentLabel(String mode) {
    return 'Payment: $mode';
  }

  @override
  String pdfGstinLabel(String number) {
    return 'GSTIN: $number';
  }

  @override
  String get rateHeader => 'Rate';

  @override
  String get paymentSplitLabel => 'Payment Split:';

  @override
  String get scanToPayUpi => 'Scan to Pay via UPI';

  @override
  String needMoreOrLess(String amount, String direction) {
    return 'Need $amount $direction';
  }

  @override
  String get more => 'more';

  @override
  String get less => 'less';

  @override
  String get shopFallback => 'Shop';

  @override
  String get listeningEllipsis => 'Listening...';

  @override
  String get addedLabel => 'Added';

  @override
  String yesterdayAt(String time) {
    return 'Yesterday · $time';
  }

  @override
  String get printShare => 'Print / Share';

  @override
  String gstColonLabel(String number) {
    return 'GST: $number';
  }

  @override
  String unitsSoldSummary(String qty, String revenue) {
    return '$qty units • $revenue';
  }

  @override
  String pcsCount(String count) {
    return '$count pcs';
  }

  @override
  String billsCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bills',
      one: '1 Bill',
    );
    return '$_temp0';
  }

  @override
  String gstEnabledPercent(String rate) {
    return 'Enabled ($rate%)';
  }

  @override
  String get tapToChangeLogo => 'Tap to change logo';

  @override
  String resendOtpIn(String seconds) {
    return 'Resend OTP in ${seconds}s';
  }
}
