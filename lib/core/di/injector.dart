import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import '../../features/auth/repositories/shop_repository.dart';
import '../../features/inventory/repositories/item_repository.dart';
import '../../features/inventory/repositories/category_repository.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/billing/repositories/invoice_repository.dart';
import '../../features/billing/repositories/payment_transaction_repository.dart';
import '../../features/reports/repositories/report_repository.dart';
import '../../features/printer/repositories/printer_repository.dart';
import '../../features/subscription/services/subscription_api_client.dart';
import '../../features/subscription/repositories/subscription_repository.dart';
import '../../features/sync/services/sync_api_client.dart';
import '../../features/sync/services/cloudinary_upload_service.dart';
import '../../features/sync/repositories/data_sync_repository.dart';

final GetIt getIt = GetIt.instance;

void setupDI() {
  getIt.registerLazySingleton<ShopRepository>(() => ShopRepository());
  getIt.registerLazySingleton<ItemRepository>(() => ItemRepository());
  getIt.registerLazySingleton<CategoryRepository>(() => CategoryRepository());
  getIt.registerLazySingleton<CustomerRepository>(() => CustomerRepository());
  getIt.registerLazySingleton<InvoiceRepository>(() => InvoiceRepository());
  getIt.registerLazySingleton<PaymentTransactionRepository>(
      () => PaymentTransactionRepository());
  getIt.registerLazySingleton<ReportRepository>(() => ReportRepository());
  getIt.registerLazySingleton<PrinterRepository>(() => PrinterRepository());
  getIt.registerLazySingleton<SubscriptionApiClient>(
      () => SubscriptionApiClient(dotenv.env['BACKEND_API_BASE_URL'] ?? ''));
  getIt.registerLazySingleton<SubscriptionRepository>(
      () => SubscriptionRepository(getIt<SubscriptionApiClient>(), getIt<ShopRepository>()));
  getIt.registerLazySingleton<SyncApiClient>(
      () => SyncApiClient(dotenv.env['BACKEND_API_BASE_URL'] ?? ''));
  getIt.registerLazySingleton<CloudinaryUploadService>(() => CloudinaryUploadService(
        dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '',
        dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '',
      ));
  getIt.registerLazySingleton<DataSyncRepository>(() => DataSyncRepository(
        getIt<SyncApiClient>(),
        getIt<ShopRepository>(),
        getIt<ItemRepository>(),
        getIt<CustomerRepository>(),
        getIt<InvoiceRepository>(),
        getIt<PaymentTransactionRepository>(),
        getIt<SubscriptionRepository>(),
        getIt<CategoryRepository>(),
        getIt<CloudinaryUploadService>(),
      ));
}
