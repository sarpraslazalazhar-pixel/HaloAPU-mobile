import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/router/app_router.dart';
import 'package:halo_apu_mobile/core/services/auth_service.dart';
import 'package:halo_apu_mobile/core/services/biometric_service.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

/// Mengunci aplikasi dengan biometrik / kunci perangkat saat fitur biometrik aktif
/// dan pengguna memiliki sesi login aktif (saat buka aplikasi maupun kembali dari background).
class AppLockGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? isBiometricEnabled;
  final Future<bool> Function()? canAuthenticate;
  final Future<bool> Function()? hasActiveSession;
  final Future<bool> Function()? authenticate;
  final Future<void> Function()? onLogout;
  final bool Function()? isAuthenticatingNow;

  const AppLockGate({
    super.key,
    required this.child,
    this.isBiometricEnabled,
    this.canAuthenticate,
    this.hasActiveSession,
    this.authenticate,
    this.onLogout,
    this.isAuthenticatingNow,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final BiometricService _biometricService = BiometricService();

  bool _isLocked = false;
  bool _isPrompting = false;
  bool _hideContentInBackground = false;
  bool _wentToBackground = false;
  bool _canLockCached = false;

  Future<bool> _checkEnabled() =>
      widget.isBiometricEnabled?.call() ?? _biometricService.isEnabled();

  Future<bool> _checkSupported() =>
      widget.canAuthenticate?.call() ?? _biometricService.canAuthenticate();

  Future<bool> _checkSession() async {
    if (widget.hasActiveSession != null) {
      return widget.hasActiveSession!();
    }
    final token = await SafeSecureStorage.read('auth_token');
    return token != null && token.isNotEmpty;
  }

  Future<bool> _runAuthenticate() {
    if (widget.authenticate != null) {
      return widget.authenticate!();
    }
    return _biometricService.authenticate(
      reason: 'Verifikasi identitas untuk membuka Halo APU',
    );
  }

  Future<void> _runLogout() async {
    if (widget.onLogout != null) {
      await widget.onLogout!();
      return;
    }
    await AuthService().logout();
    appRouter.go('/login');
  }

  bool _isExternalAuthActive() {
    if (widget.isAuthenticatingNow != null) {
      return widget.isAuthenticatingNow!();
    }
    return BiometricService.isAuthenticating || BiometricService.recentlyFinishedAuth;
  }

  Future<bool> _shouldLockNow() async {
    try {
      final results = await Future.wait<bool>([
        _checkEnabled(),
        _checkSupported(),
        _checkSession(),
      ]);
      final canLock = results[0] && results[1] && results[2];
      _canLockCached = canLock;
      return canLock;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLockCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initLockCheck() async {
    final shouldLock = await _shouldLockNow();
    if (!mounted) return;
    if (shouldLock && !_isLocked) {
      setState(() => _isLocked = true);
      await _promptUnlock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_isPrompting || _isExternalAuthActive()) {
        return;
      }
      _wentToBackground = true;
      if (_canLockCached && mounted && !_hideContentInBackground) {
        setState(() => _hideContentInBackground = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      _handleResumed();
    }
  }

  Future<void> _handleResumed() async {
    if (!_wentToBackground) {
      if (_hideContentInBackground && mounted) {
        setState(() => _hideContentInBackground = false);
      }
      await _shouldLockNow();
      return;
    }

    _wentToBackground = false;
    if (_isPrompting || _isExternalAuthActive()) {
      if (_hideContentInBackground && mounted) {
        setState(() => _hideContentInBackground = false);
      }
      return;
    }

    if (_isLocked) {
      if (_hideContentInBackground && mounted) {
        setState(() => _hideContentInBackground = false);
      }
      await _promptUnlock();
      return;
    }

    final shouldLock = await _shouldLockNow();
    if (!mounted) return;
    if (shouldLock) {
      setState(() {
        _isLocked = true;
        _hideContentInBackground = false;
      });
      await _promptUnlock();
    } else if (_hideContentInBackground) {
      setState(() => _hideContentInBackground = false);
    }
  }

  Future<void> _promptUnlock() async {
    if (_isPrompting || !_isLocked) return;
    setState(() => _isPrompting = true);

    final ok = await _runAuthenticate();
    if (!mounted) return;

    if (ok) {
      setState(() {
        _isLocked = false;
        _isPrompting = false;
        _hideContentInBackground = false;
      });
    } else {
      setState(() => _isPrompting = false);
    }
  }

  Future<void> _handleLogout() async {
    await _runLogout();
    if (!mounted) return;
    setState(() {
      _isLocked = false;
      _isPrompting = false;
      _hideContentInBackground = false;
      _canLockCached = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showPrivacyCover = _isLocked || _hideContentInBackground;

    return PopScope(
      canPop: !showPrivacyCover,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: showPrivacyCover,
            child: IgnorePointer(
              ignoring: showPrivacyCover,
              child: widget.child,
            ),
          ),
          if (showPrivacyCover)
            Positioned.fill(
              child: _AppLockOverlay(
                isLocked: _isLocked,
                isPrompting: _isPrompting,
                onUnlock: _promptUnlock,
                onLogout: _handleLogout,
              ),
            ),
        ],
      ),
    );
  }
}

class _AppLockOverlay extends StatelessWidget {
  final bool isLocked;
  final bool isPrompting;
  final VoidCallback onUnlock;
  final VoidCallback onLogout;

  const _AppLockOverlay({
    required this.isLocked,
    required this.isPrompting,
    required this.onUnlock,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.lightBg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brilliantBlue.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPrompting ? Icons.fingerprint_rounded : Icons.lock_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Halo APU Terkunci',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkBg,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verifikasi sidik jari, Face ID, atau kunci perangkat untuk melanjutkan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.slateGrey,
                    height: 1.45,
                  ),
                ),
                if (isLocked) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: isPrompting ? null : onUnlock,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: isPrompting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.fingerprint_rounded),
                        label: Text(
                          isPrompting ? 'Memverifikasi...' : 'Buka Kunci',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isPrompting ? null : onLogout,
                    child: const Text(
                      'Keluar ke Login',
                      style: TextStyle(
                        color: AppTheme.slateGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
