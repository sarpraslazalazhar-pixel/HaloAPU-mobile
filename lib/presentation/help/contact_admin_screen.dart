import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/services/auth_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactAdminScreen extends StatefulWidget {
  const ContactAdminScreen({super.key});

  @override
  State<ContactAdminScreen> createState() => _ContactAdminScreenState();
}

class _ContactAdminScreenState extends State<ContactAdminScreen> {
  final _messageController = TextEditingController();
  final _subjectController = TextEditingController();
  final _emailController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token != null && token.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _subjectController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage() async {
    if (_isLoading) return;

    final message = _messageController.text.trim();
    if (message.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesan minimal 5 karakter.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final email = _emailController.text.trim();
    if (!_isLoggedIn && email.isNotEmpty) {
      final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
      if (!emailRegex.hasMatch(email)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Format email tidak valid.'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final subject = _subjectController.text.trim();
      final result = await _authService.contactAdmin(
        message: message,
        subject: subject.isNotEmpty ? subject : null,
        email: email.isNotEmpty ? email : null,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Pesan Anda telah berhasil dikirim ke Admin.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) {
          context.pop();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Gagal mengirim pesan ke Admin.'),
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

  Future<void> _launchWhatsApp() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(
      'https://wa.me/6281384186323?text=Halo%20Admin%20Halo%20APU%2C%20saya%20butuh%20bantuan',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka WhatsApp.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuka WhatsApp.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _launchEmail() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(
      'mailto:sarpras@alazharpeduli.or.id?subject=Bantuan%20Halo%20APU',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka aplikasi Email.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuka aplikasi Email.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Hubungi Admin',
          style: TextStyle(
            color: AppTheme.oceanWater,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.oceanWater, size: 19),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF0F9FF),
              Color(0xFFF8FAFC),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header / Hero Kompak
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanWater.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        size: 24,
                        color: AppTheme.oceanWater,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bantuan & Layanan Admin',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.oceanWater,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Hubungi tim admin Sarpras & IT melalui kanal berikut atau kirim pesan.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.black54,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Quick Channels (Row 2 Kolom Kompak)
                Row(
                  children: [
                    // WhatsApp Card
                    Expanded(
                      child: Material(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _launchWhatsApp,
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 16,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'WhatsApp',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF16A34A),
                                        ),
                                      ),
                                      Text(
                                        'Chat Langsung',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Email Card
                    Expanded(
                      child: Material(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _launchEmail,
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.email_rounded,
                                    size: 16,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Email Sarpras',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0284C7),
                                        ),
                                      ),
                                      Text(
                                        'Kirim Surat',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Divider Label Ringkas
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'atau tulis pesan tiket',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 4. Card Form Pesan Terpadu
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isLoggedIn) ...[
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_isLoading,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            hintText: 'Email Anda (opsional)',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18, color: Color(0xFF64748B)),
                            prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.oceanWater, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _subjectController,
                        enabled: !_isLoading,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          hintText: 'Subjek pesan (opsional)',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          prefixIcon: const Icon(Icons.short_text_rounded, size: 20, color: Color(0xFF64748B)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppTheme.oceanWater, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _messageController,
                        enabled: !_isLoading,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          hintText: 'Tuliskan kendala atau pertanyaan Anda...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          prefixIcon: const Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 10, left: 10, right: 8),
                                child: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppTheme.oceanWater, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleSendMessage,
                          icon: _isLoading
                              ? const SizedBox.shrink()
                              : const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                          label: _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Kirim Pesan',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.oceanWater,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: AppTheme.oceanWater.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Pesan otomatis tercatat di sistem tiket admin',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
