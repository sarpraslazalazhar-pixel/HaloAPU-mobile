import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:halo_apu_mobile/core/router/app_router.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/core/services/pending_ticket_service.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_error_view.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load saved API configuration
  await ApiConfig.loadSavedBaseUrl();

  // Initialize Hive for local storage safely
  try {
    await Hive.initFlutter();
    await Hive.openBox('ticket_drafts');
    await PendingTicketService.init();
  } catch (e) {
    debugPrint('Hive init error: $e');
  }

  // Initialize API response cache & cleanup
  try {
    await CacheService.init();
    await CacheService.cleanup();
  } catch (e) {
    debugPrint('CacheService init error: $e');
  }
  // Fallback build-error: kartu ringkas, tidak memblokir seluruh layar.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('Widget build error: ${details.exception}');

    return AppErrorView(error: details.exception, fullPage: false);
  };
  runApp(
    const ProviderScope(
      child: HaloApuApp(),
    ),
  );

  // Initialize Push Notifications in background without blocking initial frame
  PushNotificationService.init().catchError((e) {
    debugPrint('PushNotificationService background init error: $e');
  });
}

class HaloApuApp extends StatelessWidget {
  const HaloApuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: FlavorConfig.appTitle,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final gatedChild = AppLockGate(
          child: child ?? const SizedBox.shrink(),
        );
        if (FlavorConfig.isStaging) {
          return Banner(
            message: 'STAGING',
            location: BannerLocation.topEnd,
            color: AppTheme.warning,
            child: gatedChild,
          );
        }
        return gatedChild;
      },
    );
  }
}
