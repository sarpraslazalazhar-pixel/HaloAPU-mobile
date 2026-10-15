import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/user_profile_model.dart';
import '../widgets/app_avatar.dart';
import 'providers/user_profile_provider.dart';
import 'widgets/circular_crop_screen.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final StateNotifierProvider<UserProfileNotifier, UserProfile>?
      profileProvider;

  const EditProfileScreen({
    super.key,
    this.profileProvider,
  });

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late String _avatarUrl;
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  @override
  void initState() {
    super.initState();
    final profile = ref.read(widget.profileProvider ?? userProfileProvider);
    _usernameController = TextEditingController(text: profile.username);
    _nameController = TextEditingController(text: profile.name);
    _emailController = TextEditingController(text: profile.email);
    _phoneController = TextEditingController(text: profile.phone);
    _avatarUrl = profile.avatarUrl;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _cropAndUploadAvatar(Uint8List rawBytes) async {
    final croppedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (ctx) => CircularCropScreen(imageBytes: rawBytes),
      ),
    );

    if (croppedBytes == null || !mounted) return;

    setState(() {
      _pickedImageBytes = croppedBytes;
      _isUploadingAvatar = true;
    });

    try {
      final activeNotifier = ref.read((widget.profileProvider ?? userProfileProvider).notifier);
      final result = await activeNotifier.uploadAvatar(croppedBytes);

      if (!mounted) return;

      if (result['success'] == true) {
        final newAvatarUrl = result['data']?['avatarUrl'] ??
            result['data']?['avatar_url'] ??
            result['data']?['avatar'] ??
            '';
        setState(() {
          _avatarUrl = newAvatarUrl.toString();
          _pickedImageBytes = null;
          _pickedImage = null;
        });

        ref.invalidate(userProfileProvider);
        ref.invalidate(adminProfileProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Foto profil berhasil diperbarui'),
            backgroundColor: AppTheme.oceanWater,
          ),
        );
      } else {
        final errorMsg = result['message']?.toString() ?? 'Gagal mengunggah foto profil';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Terjadi kesalahan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ganti Foto Profil',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.oceanWater.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library_rounded, color: AppTheme.oceanWater),
              ),
              title: const Text('Pilih dari Galeri'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 100,
                );
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  _cropAndUploadAvatar(bytes);
                }
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.oceanWater.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: AppTheme.oceanWater),
              ),
              title: const Text('Ambil Foto'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final XFile? image = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 100,
                );
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  _cropAndUploadAvatar(bytes);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final res = await ref.read((widget.profileProvider ?? userProfileProvider).notifier).updateProfile(
          username: _usernameController.text.trim(),
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          avatarUrl: _avatarUrl,
          avatarFile: _pickedImageBytes != null ? (_pickedImage ?? _pickedImageBytes) : null,
        );

    ref.invalidate(userProfileProvider);
    ref.invalidate(adminProfileProvider);
    if (!mounted) return;
    setState(() => _isSaving = false);

    final bool success = res['success'] == true;
    final String msg = res['message']?.toString() ?? (success ? 'Profil berhasil diperbarui' : 'Gagal memperbarui profil');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    
    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Edit Profil', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Center(
              child: InkWell(
                onTap: _isUploadingAvatar ? null : _pickAvatar,
                borderRadius: BorderRadius.circular(48),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AppAvatar(
                      name: _nameController.text.isNotEmpty ? _nameController.text : 'Pengguna',
                      imageUrl: _avatarUrl,
                      imageBytes: _pickedImageBytes,
                      radius: 44,
                      fontSize: 32,
                    ),
                    if (_isUploadingAvatar)
                      Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.brilliantBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _isUploadingAvatar ? 'Mengunggah foto profil...' : 'Ketuk untuk ganti foto',
                style: TextStyle(
                  fontSize: 12,
                  color: _isUploadingAvatar ? AppTheme.oceanWater : Colors.grey.shade500,
                  fontWeight: _isUploadingAvatar ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Username wajib diisi'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Email wajib diisi';
                }
                if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$').hasMatch(value.trim())) {
                  return 'Format email tidak valid';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nomor HP',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Nomor HP wajib diisi' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }
}
