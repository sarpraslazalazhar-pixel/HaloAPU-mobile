import 'package:flutter/widgets.dart';
import 'package:halo_apu_mobile/core/router/app_router.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';
import 'package:halo_apu_mobile/core/services/pending_ticket_service.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:hive/hive.dart';

/// Mengelola siklus hidup sesi autentikasi, penanganan 401 single-flight,
/// pembersihan state lokal, serta koordinasi navigasi dan AppLockGate.
class SessionManager extends ChangeNotifier {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  static const String defaultExpiredMessage =
      'Sesi Anda telah berakhir. Silakan login kembali.';

  bool _isAuthenticated = false;
  bool _isHandlingExpiry = false;
  Future<void>? _activeTransitionFuture;
  String? _pendingSessionMessage;

  VoidCallback? onInvalidateProviders;
  VoidCallback? onResetAppLock;
  VoidCallback? onNavigateToLogin;

  bool get isAuthenticated => _isAuthenticated;
  bool get isHandlingExpiry => _isHandlingExpiry;
  String? get pendingSessionMessage => _pendingSessionMessage;

  @visibleForTesting
  void resetForTest() {
    _isAuthenticated = false;
    _isHandlingExpiry = false;
    _activeTransitionFuture = null;
    _pendingSessionMessage = null;
    onInvalidateProviders = null;
    onResetAppLock = null;
    onNavigateToLogin = null;
  }

  /// Mengembalikan `true` jika [path] adalah endpoint autentikasi publik
  /// agar HTTP 401 (mis. salah password) tidak dianggap sesi kedaluwarsa.
  static bool isAuthEndpoint(String path) {
    final parsedPath = (Uri.tryParse(path)?.path ?? path).trim().toLowerCase();
    if (parsedPath.isEmpty) return false;

    const authEndpoints = ['/login', '/forgot-password', '/contact-admin'];
    for (final endpoint in authEndpoints) {
      if (parsedPath == endpoint ||
          parsedPath == endpoint.substring(1) ||
          parsedPath.endsWith(endpoint)) {
        return true;
      }
    }
    return false;
  }

  /// Mengekstrak bearer token dari header `Authorization`.
  static String extractBearerToken(Object? authorizationHeader) {
    final header = authorizationHeader?.toString() ?? '';
    if (header.length >= 7 &&
        header.substring(0, 7).toLowerCase() == 'bearer ') {
      return header.substring(7).trim();
    }
    return '';
  }

  /// Mengekstrak pesan 401 ramah pengguna, mempertahankan pesan khusus `ACCOUNT_INACTIVE`.
  static String extractUnauthorizedMessage(dynamic responseData) {
    if (responseData is Map &&
        responseData['error_code'] == 'ACCOUNT_INACTIVE' &&
        responseData['message'] != null &&
        responseData['message'].toString().trim().isNotEmpty) {
      return responseData['message'].toString().trim();
    }
    return defaultExpiredMessage;
  }

  /// Menangani respons HTTP 401 dari interceptor/client mana pun secara seragam.
  /// Mengembalikan `true` jika token request cocok dengan sesi aktif dan expiry dipicu.
  static Future<bool> handleHttpUnauthorized({
    required String path,
    Object? authorizationHeader,
    dynamic responseData,
  }) async {
    if (isAuthEndpoint(path)) return false;

    final failedToken = extractBearerToken(authorizationHeader);
    if (failedToken.isEmpty) return false;

    final currentToken = await SafeSecureStorage.read('auth_token');
    if (currentToken != null && currentToken == failedToken) {
      await instance.handleSessionExpired(
        reason: extractUnauthorizedMessage(responseData),
      );
      return true;
    }
    return false;
  }

  /// Menandai login sukses dan membersihkan pesan sesi kedaluwarsa sebelumnya.
  void notifyLoginSuccess() {
    _isAuthenticated = true;
    _pendingSessionMessage = null;
    _isHandlingExpiry = false;
    notifyListeners();
  }

  /// Mengambil pesan sesi tertunda sekali pakai lalu mengosongkannya.
  String? consumeSessionMessage() {
    final message = _pendingSessionMessage;
    _pendingSessionMessage = null;
    return message;
  }

  /// Menangani sesi berakhir (single-flight) dengan urutan aman agar layar
  /// terproteksi tidak pernah tampil sebelum navigasi ke login selesai.
  Future<void> handleSessionExpired({
    String? reason,
    bool navigate = true,
  }) {
    if (_isHandlingExpiry) {
      return _activeTransitionFuture ?? Future<void>.value();
    }
    _isHandlingExpiry = true;

    final future = _runSessionTransition(
      message: (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : defaultExpiredMessage,
      navigate: navigate,
    );
    _activeTransitionFuture = future;
    return future;
  }

  /// Memaksa pembersihan sesi dan mengarahkan ulang ke halaman login.
  /// Jika transisi expiry sedang berjalan, menunggu transisi tersebut selesai
  /// tanpa memicu clear/navigasi ganda.
  Future<void> forceReLogin({String? reason}) {
    if (_isHandlingExpiry) {
      return _activeTransitionFuture ?? Future<void>.value();
    }
    _isHandlingExpiry = true;

    final nextMessage = (reason != null && reason.trim().isNotEmpty)
        ? reason.trim()
        : _pendingSessionMessage;
    final future = _runSessionTransition(
      message: nextMessage,
      navigate: true,
    );
    _activeTransitionFuture = future;
    return future;
  }

  Future<void> _runSessionTransition({
    required String? message,
    required bool navigate,
  }) async {
    try {
      _pendingSessionMessage = message;
      _isAuthenticated = false;

      await _clearLocalSessionData();
      onInvalidateProviders?.call();
      notifyListeners();

      if (navigate) {
        _navigateToLogin();
      }
      // Wajib dijadwalkan setelah sesi dibersihkan & navigasi ke /login dipicu.
      _scheduleResetAppLock();
    } finally {
      _isHandlingExpiry = false;
      _activeTransitionFuture = null;
    }
  }

  /// Menandai logout normal tanpa pesan error sesi.
  Future<void> markLoggedOut() async {
    _pendingSessionMessage = null;
    _isAuthenticated = false;
    _isHandlingExpiry = false;
    _activeTransitionFuture = null;

    await _clearLocalSessionData();
    onInvalidateProviders?.call();
    notifyListeners();
    _scheduleResetAppLock();
  }

  Future<void> _clearLocalSessionData() async {
    PushNotificationService.stopRealtimePoller();
    await SafeSecureStorage.clearSession();
    AttachmentService.clearTokenCache();
    await AttachmentService.clearDownloadedTempFiles();
    await CacheService.clear();
    await _clearHiveBoxSafely('ticket_drafts');
    await _clearHiveBoxSafely(PendingTicketService.boxName);
  }

  Future<void> _clearHiveBoxSafely(String boxName) async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).clear();
      }
    } catch (e) {
      debugPrint('SessionManager clear box "$boxName" error: $e');
    }
  }

  void _navigateToLogin() {
    if (onNavigateToLogin != null) {
      onNavigateToLogin!();
    } else {
      appRouter.go('/login');
    }
  }

  void _scheduleResetAppLock() {
    final callback = onResetAppLock;
    if (callback == null) return;
    try {
      final binding = WidgetsBinding.instance;
      if (binding.rootElement != null) {
        binding.addPostFrameCallback((_) {
          onResetAppLock?.call();
        });
        binding.ensureVisualUpdate();
        return;
      }
    } catch (_) {
      // Binding belum aktif di pure Dart unit test.
    }
    callback();
  }
}
