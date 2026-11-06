import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/core/services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final bool initialIsAdmin;
  const ForgotPasswordScreen({super.key, this.initialIsAdmin = false});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  late bool _isAdmin;

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.initialIsAdmin;
  }
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_isLoading) return;

    final identifier = _emailController.text.trim();
    if (identifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAdmin
              ? 'Silakan masukkan email atau username akun admin Anda.'
              : 'Silakan masukkan email atau username akun Anda.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (identifier.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email atau username minimal 3 karakter.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.forgotPassword(identifier, isAdmin: _isAdmin);

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Tautan reset password telah dikirim ke email Anda.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          context.pop();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal mengirim permintaan reset password.'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.oceanWater),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        height: double.infinity,
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
            Positioned(
              top: -100,
              left: -100,
              child: _buildBlob(
                gradient: const LinearGradient(
                  colors: [
                    Color(0x2600A2E8),
                    Color(0x1AFEA520),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_reset, size: 80, color: AppTheme.oceanWater),
                      const SizedBox(height: 16),
                      const Text(
                        'Lupa Password',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.oceanWater,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isAdmin
                            ? 'Masukkan email atau username admin yang terdaftar untuk mengatur ulang kata sandi.'
                            : 'Masukkan email atau username yang terdaftar untuk mengatur ulang kata sandi Anda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                      const SizedBox(height: 40),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
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
                                // Role Toggle: User vs Admin
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: _isLoading ? null : () => setState(() => _isAdmin = false),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            decoration: BoxDecoration(
                                              color: !_isAdmin ? Colors.white : Colors.transparent,
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: !_isAdmin
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.06),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 1),
                                                      )
                                                    ]
                                                  : null,
                                            ),
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.person_outline_rounded,
                                                  size: 15,
                                                  color: !_isAdmin ? AppTheme.oceanWater : Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 5),
                                                Flexible(
                                                  child: Text(
                                                    'User',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: !_isAdmin ? FontWeight.bold : FontWeight.w600,
                                                      color: !_isAdmin ? AppTheme.oceanWater : Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: _isLoading ? null : () => setState(() => _isAdmin = true),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            decoration: BoxDecoration(
                                              color: _isAdmin ? Colors.white : Colors.transparent,
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: _isAdmin
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.06),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 1),
                                                      )
                                                    ]
                                                  : null,
                                            ),
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.support_agent_rounded,
                                                  size: 15,
                                                  color: _isAdmin ? AppTheme.oceanWater : Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 5),
                                                Flexible(
                                                  child: Text(
                                                    'Admin',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: _isAdmin ? FontWeight.bold : FontWeight.w600,
                                                      color: _isAdmin ? AppTheme.oceanWater : Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _isAdmin ? 'Email atau Username Admin' : 'Email atau Username User',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.text,
                                  enabled: !_isLoading,
                                  decoration: InputDecoration(
                                    hintText: _isAdmin ? 'cth: superadmin atau email' : 'cth: username atau email',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    prefixIcon: Icon(
                                      _isAdmin ? Icons.badge_outlined : Icons.account_circle_outlined,
                                      color: Colors.grey,
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
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _handleResetPassword,
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
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Text('Kirim Tautan Reset', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildBlob({required Gradient gradient}) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
        ),
      ),
    );
  }
}
