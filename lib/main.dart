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
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/data/repositories/dashboard_repository.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/csat_provider.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';
import 'package:halo_apu_mobile/presentation/notifications/providers/notification_provider.dart';
import 'package:halo_apu_mobile/presentation/profile/providers/user_profile_provider.dart';
import 'package:halo_apu_mobile/presentation/ratings/providers/rating_provider.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/admin_ticket_provider.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/user_ticket_provider.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_error_view.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_lock_gate.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_update_dialog.dart';

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

class HaloApuApp extends ConsumerStatefulWidget {
  const HaloApuApp({super.key});

  @override
  ConsumerState<HaloApuApp> createState() => _HaloApuAppState();
}

class _HaloApuAppState extends ConsumerState<HaloApuApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionManager.instance.onInvalidateProviders = _invalidateAllProviders;
    AppUpdateService.notificationUpdateTrigger.addListener(_handleUpdateNotificationTrigger);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppUpdateService.notificationUpdateTrigger.removeListener(_handleUpdateNotificationTrigger);
    if (SessionManager.instance.onInvalidateProviders == _invalidateAllProviders) {
      SessionManager.instance.onInvalidateProviders = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      PushNotificationService.onAppPaused();
    }
  }

  void _handleUpdateNotificationTrigger() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        AppUpdateDialog.checkAndShow(navContext, manual: true);
      }
    });
  }

  void _invalidateAllProviders() {
    if (!mounted) return;
    ref.invalidate(adminTicketProvider);
    ref.invalidate(userTicketProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(adminProfileProvider);
    ref.invalidate(notificationProvider);
    ref.invalidate(dashboardRepositoryProvider);
    ref.invalidate(monitorProvider);
    ref.invalidate(csatProvider);
    ref.invalidate(ratingProvider);
    ref.invalidate(adminRatingProvider);
  }

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
