import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/di/injector.dart';
import 'core/network/ipv4_http_overrides.dart';
import 'core/router/app_router.dart';
import 'core/services/backend_warmup.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/locale_provider.dart';
import 'features/settings/providers/theme_provider.dart';
import 'features/sync/services/data_sync_scheduler.dart';
import 'l10n/generated/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = Ipv4HttpOverrides();
  await dotenv.load(fileName: '.env');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  setupDI();
  warmUpBackend();

  runApp(const ProviderScope(child: VaaniApp()));
}

class VaaniApp extends ConsumerStatefulWidget {
  const VaaniApp({super.key});

  @override
  ConsumerState<VaaniApp> createState() => _VaaniAppState();
}

class _VaaniAppState extends ConsumerState<VaaniApp> with WidgetsBindingObserver {
  late final _router = createRouter();
  final _syncScheduler = DataSyncScheduler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncScheduler.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncScheduler.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncScheduler.checkOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Vaani — AI Store Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: _router,
    );
  }
}
