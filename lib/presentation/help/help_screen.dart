import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const Map<String, List<Map<String, String>>> _faqData = {
    'Tiket & Layanan': [
      {
        'question': 'Bagaimana cara membuat tiket baru?',
        'answer':
            'Tekan tombol (+) di navigasi tengah bawah. Pilih Unit Layanan & Sub Unit, isi form dinamis sesuai kebutuhan, lampirkan dokumen/foto jika ada, lalu tekan "Kirim Tiket".',
      },
      {
        'question': 'Apakah bisa melampirkan foto atau dokumen?',
        'answer':
            'Bisa. Anda dapat mengunggah hingga 3 berkas (format JPG, PNG, PDF, DOCX) dengan ukuran maksimal 3 MB per file.',
      },
      {
        'question': 'Apa fungsi fitur Coret & Tandai (Doodle) pada foto?',
        'answer':
            'Saat memilih foto lampiran, Anda dapat memilih "Coret & Tandai" untuk melingkari atau menandai area kendala pada gambar sebelum dikirim ke operator.',
      },
      {
        'question': 'Bagaimana cara melihat dan mengunduh berkas lampiran?',
        'answer':
            'Buka tab "Lampiran" atau pada percakapan chat. Tekan foto untuk pratinjau fullscreen (bisa di-zoom), atau tekan tombol unduh pada berkas dokumen/PDF untuk membukanya langsung di ponsel Anda.',
      },
      {
        'question': 'Kapan menggunakan "Terima Hasil" dan "Minta Revisi"?',
        'answer':
            'Setelah operator menyelesaikan pekerjaan, tekan "Terima Hasil" jika kendala tuntas, atau ajukan "Minta Revisi" (maksimal 5 kali) jika pekerjaan belum sesuai.',
      },
      {
        'question': 'Mengapa harus mengisi survei kepuasan (CSAT)?',
        'answer':
            'Setelah tiket selesai, penilaian bintang 1-5 dan ulasan singkat membantu manajemen mengevaluasi dan meningkatkan kualitas pelayanan operator Sarpras & IT.',
      },
    ],
    'Fitur & Offline': [
      {
        'question': 'Apakah riwayat tiket bisa dibuka saat offline (tanpa internet)?',
        'answer':
            'Bisa. Halo APU dilengkapi teknologi cache lokal otomatis. Riwayat tiket, detail, dan pesan chat yang pernah dibuka tetap dapat dibaca saat offline dengan indikator spanduk "Mode Offline".',
      },
      {
        'question': 'Apa itu fitur Live Monitor Aset?',
        'answer':
            'Fitur di dasbor utama untuk memantau ketersediaan ruangan rapat/dinas dan kendaraan operasional secara real-time.',
      },
      {
        'question': 'Bagaimana cara berdiskusi dengan teknisi/operator?',
        'answer':
            'Buka detail tiket Anda lalu pilih tab "Percakapan". Anda dapat berkirim pesan dan foto secara langsung seperti aplikasi chat.',
      },
      {
        'question': 'Apakah ada notifikasi jika tiket diperbarui?',
        'answer':
            'Ya. Anda akan menerima Push Notification dan notifikasi in-app saat ada perubahan status tiket, penugasan operator, atau balasan chat baru.',
      },
    ],
    'Akun & Keamanan': [
      {
        'question': 'Bagaimana cara mengaktifkan Login Biometrik (Sidik Jari / Face ID)?',
        'answer':
            'Buka menu Profil, aktifkan toggle "Login Biometrik", lalu masukkan konfirmasi kata sandi akun Anda. Setelah aktif, Anda dapat login instan tanpa mengetik password.',
      },
      {
        'question': 'Mengapa muncul peringatan Kunci Perangkat (Device ID)?',
        'answer':
            'Untuk keamanan data, 1 akun dibatasi pada 1 perangkat HP. Jika Anda berganti ponsel, silakan hubungi Administrator untuk membuka tautan perangkat lama.',
      },
      {
        'question': 'Bagaimana cara mengubah foto profil?',
        'answer':
            'Di menu Profil, sentuh ikon kamera pada foto profil Anda. Pilih dari kamera atau galeri, sesuaikan pemotongan foto bulat, lalu simpan.',
      },
      {
        'question': 'Bagaimana jika lupa kata sandi akun?',
        'answer':
            'Di halaman Login, tekan "Lupa Kata Sandi?". Masukkan email terdaftar Anda, dan tautan reset kata sandi akan otomatis dikirim ke email.',
      },
    ],
    'Kontak & Bantuan': [
      {
        'question': 'Bagaimana cara menghubungi Admin secara langsung?',
        'answer':
            'Buka menu "Hubungi Admin" untuk mengirim chat WhatsApp resmi Sarpras, mengirim email, atau mengirim pesan tiket langsung ke admin.',
      },
      {
        'question': 'Berapa jam operasional layanan Helpdesk?',
        'answer':
            'Layanan Helpdesk beroperasi pada hari kerja Senin - Jumat pukul 08:00 - 17:00 WIB. Tiket di luar jam kerja akan diproses pada hari kerja berikutnya sesuai prioritas SLA.',
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _faqData.keys.length,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Pusat Bantuan',
            style: TextStyle(color: AppTheme.oceanWater, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.oceanWater),
            onPressed: () => context.pop(),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.oceanWater,
            labelColor: AppTheme.oceanWater,
            unselectedLabelColor: Colors.grey.shade500,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: _faqData.keys.map((String category) => Tab(text: category)).toList(),
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
                right: -100,
                child: _buildBlob(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0x1EFEA520),
                      Color(0x1A00A2E8),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: kToolbarHeight + 48),
                    Expanded(
                      child: TabBarView(
                        children: _faqData.keys.map((String category) {
                          final faqs = _faqData[category]!;
                          return ListView.separated(
                            padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20),
                            itemCount: faqs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildFaqItem(
                                faqs[index]['question']!,
                                faqs[index]['answer']!,
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    _buildContactAdminBanner(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactAdminBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.oceanWater.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.oceanWater.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/contact-admin'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.oceanWater.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: AppTheme.oceanWater,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pertanyaan belum terjawab?',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Hubungi Admin',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.oceanWater,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.oceanWater,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => context.push('/contact-admin'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hubungi',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
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

  Widget _buildFaqItem(String question, String answer) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.oceanWater.withValues(alpha: 0.08),
            ),
          ),
          child: ExpansionTile(
            title: Text(
              question,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            iconColor: AppTheme.oceanWater,
            collapsedIconColor: Colors.grey,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                child: Text(
                  answer,
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700, height: 1.5),
                ),
              ),
            ],
          ),
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
