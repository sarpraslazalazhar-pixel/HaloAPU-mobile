import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/core/services/auth_service.dart';
import 'package:halo_apu_mobile/core/services/biometric_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/presentation/profile/providers/user_profile_provider.dart';
import 'package:halo_apu_mobile/presentation/notifications/providers/notification_provider.dart';
import 'package:halo_apu_mobile/data/repositories/dashboard_repository.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/admin_ticket_provider.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/user_ticket_provider.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/csat_provider.dart';
import 'package:halo_apu_mobile/presentation/ratings/providers/rating_provider.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final BiometricService _biometricService = BiometricService();
  bool _obscurePassword = true;
  bool _isLoadingUser = false;
  bool _isLoadingAdmin = false;
  bool _isLoadingBiometric = false;

  bool get _isLoading => _isLoadingUser || _isLoadingAdmin || _isLoadingBiometric;
  bool get _isRateLimited => _retryAfterSeconds > 0;
  bool get _isButtonDisabled => _isLoading || _isRateLimited;

  bool _biometricVisible = false;
  Map<String, String>? _savedBiometricUser;
  int _biometricFailures = 0;

  String? _sessionBannerMessage;
  String? _errorBannerMessage;
  int _retryAfterSeconds = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _sessionBannerMessage = SessionManager.instance.consumeSessionMessage();
    _initBiometric();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startRateLimitCountdown(int seconds) {
    _retryTimer?.cancel();
    final initial = seconds < 1 ? 1 : seconds;
    setState(() {
      _retryAfterSeconds = initial;
    });
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryAfterSeconds <= 1) {
        timer.cancel();
        setState(() {
          _retryAfterSeconds = 0;
        });
      } else {
        setState(() {
          _retryAfterSeconds--;
        });
      }
    });
  }

  Future<void> _onLoginSucceeded(bool isAdmin) async {
    _retryTimer?.cancel();
    setState(() {
      _retryAfterSeconds = 0;
      _errorBannerMessage = null;
      _sessionBannerMessage = null;
    });

    await CacheService.clear();
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

    // Sync FCM Token with backend
    PushNotificationService.syncFcmTokenWithBackend();
    if (!mounted) return;

    if (isAdmin) {
      context.go('/dashboard/admin');
    } else {
      context.go('/dashboard/user');
    }
  }

  Future<void> _handleLoginError(
    Map<String, dynamic> result, {
    bool fromBiometric = false,
  }) async {
    final statusCode = result['statusCode'] as int?;
    final errorCode = result['error_code']?.toString();
    String message = result['message']?.toString() ??
        (fromBiometric
            ? 'Login biometrik gagal. Silakan masukkan password.'
            : 'Login gagal. Periksa kembali ID dan kata sandi Anda.');

    if (fromBiometric && (statusCode == 401 || statusCode == 403)) {
      await _biometricService.clearBiometricSession();
      if (!mounted) return;
      setState(() {
        _biometricVisible = false;
        _savedBiometricUser = null;
      });
      if (statusCode == 401) {
        message =
            'Kredensial biometrik sudah tidak valid atau kata sandi telah diubah. Silakan login manual dengan password.';
      }
    }

    if (statusCode == 429 || errorCode == 'RATE_LIMITED') {
      final retryAfter = (result['retry_after'] as num?)?.toInt() ?? 60;
      _startRateLimitCountdown(retryAfter);
    }

    if (!mounted) return;
    setState(() {
      _errorBannerMessage = message;
    });
  }

  Future<void> _initBiometric() async {
    final enabled = await _biometricService.isEnabled();
    final supported = await _biometricService.canAuthenticate();
    final savedUser = await _biometricService.getSavedBiometricUser();

    if (mounted && enabled && supported && savedUser != null) {
      setState(() {
        _savedBiometricUser = savedUser;
        _biometricVisible = true;
      });
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_isButtonDisabled) return;
    final ok = await _biometricService.authenticate();
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _biometricFailures++;
        if (_biometricFailures >= 3) {
          _biometricVisible = false;
          _errorBannerMessage = 'Gagal 3 kali. Silakan login dengan password.';
        } else {
          _errorBannerMessage = 'Verifikasi biometrik gagal.';
        }
      });
      return;
    }

    setState(() {
      _isLoadingBiometric = true;
      _errorBannerMessage = null;
    });

    final creds = await _biometricService.getBiometricCredentials();
    if (!mounted) return;

    if (creds == null) {
      setState(() {
        _isLoadingBiometric = false;
        _biometricVisible = false;
        _savedBiometricUser = null;
        _errorBannerMessage = 'Kredensial biometrik tidak ditemukan. Silakan login dengan password.';
      });
      return;
    }

    final isAdmin = creds['role'] == 'admin';
    final result = await _authService.login(creds['email']!, creds['password']!, isAdmin);

    if (!mounted) return;
    setState(() => _isLoadingBiometric = false);

    if (result['success'] == true) {
      await _onLoginSucceeded(isAdmin);
    } else {
      await _handleLoginError(result, fromBiometric: true);
    }
  }

  Future<void> _handleLoginUser() async {
    await _performLogin(false);
  }

  Future<void> _handleLoginAdmin() async {
    await _performLogin(true);
  }

  Future<void> _performLogin(bool isAdmin) async {
    if (_isButtonDisabled) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorBannerMessage = 'Email/Username dan Password tidak boleh kosong';
      });
      return;
    }

    setState(() {
      _errorBannerMessage = null;
      if (isAdmin) {
        _isLoadingAdmin = true;
      } else {
        _isLoadingUser = true;
      }
    });

    final result = await _authService.login(email, password, isAdmin);

    if (!mounted) return;
    setState(() {
      _isLoadingUser = false;
      _isLoadingAdmin = false;
    });

    if (result['success'] == true) {
      await _onLoginSucceeded(isAdmin);
    } else {
      await _handleLoginError(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE0F4FE),
              Color(0xFFF6FAFF),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Floating Blobs
            Positioned(
              top: -100,
              left: -100,
              child: _buildBlob(
                gradient: const RadialGradient(
                  colors: [
                    Color(0x4000A2E8),
                    Color(0x0000A2E8),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              right: -100,
              child: _buildBlob(
                gradient: const RadialGradient(
                  colors: [
                    Color(0x30FEA520),
                    Color(0x00FEA520),
                  ],
                ),
              ),
            ),
            
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 70,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.support_agent, size: 70, color: AppTheme.oceanWater);
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Session Expired / Re-login Info Banner
                      if (_sessionBannerMessage != null) ...[
                        _buildSessionInfoBanner(_sessionBannerMessage!),
                        const SizedBox(height: 16),
                      ],

                      // Inline Error & Rate-limit Countdown Banner
                      if (_errorBannerMessage != null || _isRateLimited) ...[
                        _buildErrorBanner(),
                        const SizedBox(height: 16),
                      ],

                      // Quick Biometric Login Card
                      if (_biometricVisible && _savedBiometricUser != null) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppTheme.oceanWater.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.oceanWater.withValues(alpha: 0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.oceanWater.withValues(alpha: 0.2),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.fingerprint,
                                      color: AppTheme.brilliantBlue,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Login Cepat Biometrik',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.slateGrey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _savedBiometricUser!['name'] ?? 'Pengguna',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _isButtonDisabled ? null : _handleBiometricLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brilliantBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 4,
                                  shadowColor: AppTheme.brilliantBlue.withValues(alpha: 0.35),
                                ),
                                icon: const Icon(Icons.touch_app, size: 20),
                                label: Text(
                                  _isLoadingBiometric ? 'Memverifikasi...' : 'Masuk dengan Sidik Jari',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'ATAU MASUK DENGAN PASSWORD',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.blueGrey.shade400,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Glass Card Form
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppTheme.oceanWater.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.oceanWater.withValues(alpha: 0.1),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Username
                                const Text(
                                  'Email atau Username',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    hintText: 'Masukkan ID Anda',
                                    hintStyle: TextStyle(color: Colors.grey.shade400),
                                    prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Password
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Kata Sandi',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        final isLikelyAdmin = _emailController.text.trim().toLowerCase().contains('admin');
                                        context.push(isLikelyAdmin ? '/forgot-password?role=admin' : '/forgot-password');
                                      },
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Lupa Password?',
                                        style: TextStyle(fontSize: 11, color: AppTheme.oceanWater),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(color: Colors.grey.shade400),
                                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Login Button
                                ElevatedButton(
                                  onPressed: _isButtonDisabled ? null : _handleLoginUser,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.oceanWater,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 8,
                                    shadowColor: AppTheme.oceanWater.withValues(alpha: 0.5),
                                  ),
                                  child: _isLoadingUser
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _isRateLimited
                                                  ? 'Coba lagi dalam ${_retryAfterSeconds}d'
                                                  : 'Login sebagai User',
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                            ),
                                            if (!_isRateLimited) ...[
                                              const SizedBox(width: 8),
                                              const Icon(Icons.arrow_forward),
                                            ],
                                          ],
                                        ),
                                ),
                                
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Text('ATAU', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
                                    ),
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                OutlinedButton(
                                  onPressed: _isButtonDisabled ? null : _handleLoginAdmin,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.oceanWater,
                                    side: BorderSide(color: AppTheme.oceanWater.withValues(alpha: 0.2), width: 2),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoadingAdmin
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.oceanWater, strokeWidth: 2))
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _isRateLimited
                                                  ? 'Coba lagi dalam ${_retryAfterSeconds}d'
                                                  : 'Login sebagai Admin',
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                            ),
                                            if (!_isRateLimited) ...[
                                              const SizedBox(width: 8),
                                              const Icon(Icons.support_agent),
                                            ],
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),

                      const SizedBox(height: 40),
                      
                      // Footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFooterIcon(Icons.help_outline_rounded, 'Bantuan & FAQ', () => context.push('/help')),
                          const SizedBox(width: 32),
                          _buildFooterIcon(Icons.contact_support_outlined, 'Hubungi Admin', () => context.push('/contact-admin')),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'VERSI ${FlavorConfig.appVersion} • © 2026 Al Azhar peduli',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          color: Colors.blueGrey.withValues(alpha: 0.4),
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionInfoBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _sessionBannerMessage = null),
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB45309)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Tutup',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    final text = _errorBannerMessage ??
        'Terlalu banyak percobaan login. Silakan coba lagi dalam $_retryAfterSeconds detik.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              _isRateLimited ? Icons.timer_outlined : Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF991B1B),
                    height: 1.4,
                  ),
                ),
                if (_isRateLimited) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tombol login aktif kembali dalam $_retryAfterSeconds detik.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isRateLimited)
            IconButton(
              onPressed: () => setState(() => _errorBannerMessage = null),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Tutup',
            ),
        ],
      ),
    );
  }

  Widget _buildBlob({required Gradient gradient}) {
    return Container(
      width: 400,
      height: 400,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
      ),
    );
  }

  Widget _buildFooterIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: AppTheme.oceanWater, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

