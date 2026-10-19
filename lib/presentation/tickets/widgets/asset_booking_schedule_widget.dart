import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/monitor_asset_model.dart';
import 'package:halo_apu_mobile/domain/models/monitor_calendar_model.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';

class ParsedTimeRange {
  final int startMinutes;
  final int endMinutes;
  final String formatted;

  const ParsedTimeRange({
    required this.startMinutes,
    required this.endMinutes,
    required this.formatted,
  });

  bool overlaps(ParsedTimeRange other) {
    return startMinutes < other.endMinutes && endMinutes > other.startMinutes;
  }
}

class UserBookingTime {
  final int? startMinutes;
  final int? endMinutes;
  final String? rawStart;
  final String? rawEnd;

  const UserBookingTime({
    this.startMinutes,
    this.endMinutes,
    this.rawStart,
    this.rawEnd,
  });

  bool get isComplete => startMinutes != null && endMinutes != null;
  bool get isInvalidRange => isComplete && startMinutes! >= endMinutes!;
}

class ConflictResult {
  final bool hasConflict;
  final String? message;
  final MonitorCalendarItemModel? conflictingBooking;

  const ConflictResult({
    required this.hasConflict,
    this.message,
    this.conflictingBooking,
  });
}

class AssetBookingScheduleWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> subUnit;
  final Map<String, dynamic> formData;
  final List<Map<String, dynamic>> formFields;
  final void Function(bool hasConflict, String? conflictMessage)? onConflictChanged;

  const AssetBookingScheduleWidget({
    super.key,
    required this.subUnit,
    required this.formData,
    this.formFields = const [],
    this.onConflictChanged,
  });

  @override
  ConsumerState<AssetBookingScheduleWidget> createState() => _AssetBookingScheduleWidgetState();
}

class _AssetBookingScheduleWidgetState extends ConsumerState<AssetBookingScheduleWidget> {
  bool? _lastReportedConflict;
  String? _lastReportedMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluateConflict();
    });
  }

  @override
  void didUpdateWidget(covariant AssetBookingScheduleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluateConflict();
    });
  }

  // ============ HELPERS & PARSING ============

  String? _getAssetName() {
    final assetFieldId = widget.subUnit['monitor_asset_field_id']?.toString();
    if (assetFieldId != null && widget.formData[assetFieldId] != null) {
      final val = widget.formData[assetFieldId].toString().trim();
      if (val.isNotEmpty) return val;
    }

    // Fallback: search in form fields
    for (final field in widget.formFields) {
      final label = (field['label'] ?? '').toString().toLowerCase();
      final type = (field['type'] ?? '').toString().toLowerCase();
      if (type == 'dropdown' || type == 'radio' || type == 'text' || type == 'teks_pendek') {
        if (label.contains('aset') ||
            label.contains('ruangan') ||
            label.contains('ruang') ||
            label.contains('mobil') ||
            label.contains('kendaraan')) {
          final val = widget.formData[field['id']?.toString()]?.toString().trim();
          if (val != null && val.isNotEmpty) return val;
        }
      }
    }
    return null;
  }

  String _getSelectedDateString() {
    final dateFieldId = widget.subUnit['monitor_date_field_id']?.toString();
    if (dateFieldId != null && widget.formData[dateFieldId] != null) {
      final val = widget.formData[dateFieldId].toString().trim();
      if (val.isNotEmpty) {
        return _extractDateString(val) ?? _todayDateString();
      }
    }

    // Fallback: search date field in form
    for (final field in widget.formFields) {
      final type = (field['type'] ?? '').toString().toLowerCase();
      if (type == 'tanggal' || type == 'datetime') {
        final val = widget.formData[field['id']?.toString()]?.toString().trim();
        if (val != null && val.isNotEmpty) {
          final extracted = _extractDateString(val);
          if (extracted != null) return extracted;
        }
      }
    }

    return _todayDateString();
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String? _extractDateString(String raw) {
    final trimmed = raw.trim().split(' ').first;
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  UserBookingTime _getUserBookingTime() {
    final startFieldId = widget.subUnit['monitor_start_field_id']?.toString();
    final endFieldId = widget.subUnit['monitor_end_field_id']?.toString();

    String? rawStart;
    String? rawEnd;

    if (startFieldId != null && widget.formData[startFieldId] != null) {
      rawStart = widget.formData[startFieldId]?.toString().trim();
    }
    if (endFieldId != null && widget.formData[endFieldId] != null) {
      rawEnd = widget.formData[endFieldId]?.toString().trim();
    }

    // Fallback: search in form fields
    if (rawStart == null) {
      for (final field in widget.formFields) {
        final label = (field['label'] ?? '').toString().toLowerCase();
        final type = (field['type'] ?? '').toString().toLowerCase();
        if (type == 'waktu' || type == 'datetime') {
          if (label.contains('mulai') || label.contains('start') || label.contains('dari')) {
            rawStart = widget.formData[field['id']?.toString()]?.toString().trim();
            break;
          }
        }
      }
    }

    if (rawEnd == null) {
      for (final field in widget.formFields) {
        final label = (field['label'] ?? '').toString().toLowerCase();
        final type = (field['type'] ?? '').toString().toLowerCase();
        if (type == 'waktu' || type == 'datetime') {
          if (label.contains('selesai') || label.contains('akhir') || label.contains('sampai') || label.contains('end')) {
            rawEnd = widget.formData[field['id']?.toString()]?.toString().trim();
            break;
          }
        }
      }
    }

    // If start contains a range (e.g. "08:00 - 10:00")
    if (rawStart != null && (rawStart.contains('-') || rawStart.contains('–') || rawStart.contains('to'))) {
      final range = _parseTimeRange(rawStart);
      if (range != null) {
        return UserBookingTime(
          startMinutes: range.startMinutes,
          endMinutes: range.endMinutes,
          rawStart: range.formatted.split(' - ').first,
          rawEnd: range.formatted.split(' - ').last,
        );
      }
    }

    final startMinutes = _parseSingleTimeToMinutes(rawStart);
    final endMinutes = _parseSingleTimeToMinutes(rawEnd);

    return UserBookingTime(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      rawStart: rawStart,
      rawEnd: rawEnd,
    );
  }

  ParsedTimeRange? _parseTimeRange(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final regex = RegExp(
      r'(\d{1,2})[:.](\d{2})(?::\d{2})?\s*(?:-|–|—|to|s/d)\s*(\d{1,2})[:.](\d{2})(?::\d{2})?',
      caseSensitive: false,
    );
    final match = regex.firstMatch(raw);
    if (match != null) {
      final sh = int.tryParse(match.group(1)!) ?? 0;
      final sm = int.tryParse(match.group(2)!) ?? 0;
      final eh = int.tryParse(match.group(3)!) ?? 0;
      final em = int.tryParse(match.group(4)!) ?? 0;
      return ParsedTimeRange(
        startMinutes: sh * 60 + sm,
        endMinutes: eh * 60 + em,
        formatted: '${sh.toString().padLeft(2, '0')}:${sm.toString().padLeft(2, '0')} - ${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}',
      );
    }
    return null;
  }

  int? _parseSingleTimeToMinutes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(' ');
    final timeStr = parts.length > 1 ? parts.last : parts.first;
    final regex = RegExp(r'(\d{1,2})[:.](\d{2})');
    final match = regex.firstMatch(timeStr);
    if (match != null) {
      final h = int.tryParse(match.group(1)!) ?? 0;
      final m = int.tryParse(match.group(2)!) ?? 0;
      return h * 60 + m;
    }
    return null;
  }

  bool _isSameDate(String dateA, String dateB) {
    final normA = _extractDateString(dateA);
    final normB = _extractDateString(dateB);
    if (normA != null && normB != null) {
      return normA == normB;
    }
    return dateA.trim() == dateB.trim();
  }

  bool _isMatchingAssetName(String name1, String name2) {
    final n1 = name1.trim().toLowerCase();
    final n2 = name2.trim().toLowerCase();
    if (n1 == n2) return true;
    if ((n1.contains(n2) || n2.contains(n1)) && (n1.length >= 3 && n2.length >= 3)) {
      return true;
    }
    return false;
  }

  MonitorAssetModel? _findMatchingAsset(List<MonitorAssetModel> assets, String assetName) {
    final clean = assetName.trim().toLowerCase();
    // 1. Exact match
    for (final a in assets) {
      if (a.namaAset.trim().toLowerCase() == clean) {
        return a;
      }
    }
    // 2. Partial match
    for (final a in assets) {
      if (_isMatchingAssetName(a.namaAset, assetName)) {
        return a;
      }
    }
    return null;
  }

  List<MonitorCalendarItemModel> _getBookingsForDateAndAsset(
    List<MonitorCalendarModel> calendarData,
    String selectedDate,
    String assetName,
  ) {
    final List<MonitorCalendarItemModel> result = [];
    for (final day in calendarData) {
      if (_isSameDate(day.date, selectedDate)) {
        for (final booking in day.bookings) {
          final status = booking.status.trim().toLowerCase();
          if (status == 'batal' || status == 'cancelled' || status == 'rejected') {
            continue;
          }
          if (_isMatchingAssetName(booking.namaAset, assetName)) {
            result.add(booking);
          }
        }
      }
    }
    return result;
  }

  ConflictResult _calculateConflict({
    required String? assetName,
    required UserBookingTime userTime,
    required List<MonitorCalendarItemModel> existingBookings,
  }) {
    if (assetName == null || assetName.isEmpty) {
      return const ConflictResult(hasConflict: false);
    }

    if (!userTime.isComplete) {
      return const ConflictResult(hasConflict: false);
    }

    if (userTime.isInvalidRange) {
      return const ConflictResult(
        hasConflict: true,
        message: 'Jam selesai harus lebih besar dari jam mulai.',
      );
    }

    final userRange = ParsedTimeRange(
      startMinutes: userTime.startMinutes!,
      endMinutes: userTime.endMinutes!,
      formatted: '${userTime.rawStart} - ${userTime.rawEnd}',
    );

    for (final b in existingBookings) {
      final bRange = _parseTimeRange(b.waktu);
      if (bRange != null && userRange.overlaps(bRange)) {
        return ConflictResult(
          hasConflict: true,
          message: 'Jadwal Bentrok: Aset ini sudah dipesan pada jam ${b.waktu} oleh ${b.user}.',
          conflictingBooking: b,
        );
      }
    }

    return const ConflictResult(hasConflict: false);
  }

  void _evaluateConflict() {
    if (!mounted) return;
    final assetName = _getAssetName();
    final selectedDate = _getSelectedDateString();
    final userTime = _getUserBookingTime();

    final monitorState = ref.read(monitorProvider);
    final calendarList = monitorState.calendar.value ?? [];

    final existingBookings = assetName != null
        ? _getBookingsForDateAndAsset(calendarList, selectedDate, assetName)
        : <MonitorCalendarItemModel>[];

    final conflictResult = _calculateConflict(
      assetName: assetName,
      userTime: userTime,
      existingBookings: existingBookings,
    );

    if (_lastReportedConflict != conflictResult.hasConflict ||
        _lastReportedMessage != conflictResult.message) {
      _lastReportedConflict = conflictResult.hasConflict;
      _lastReportedMessage = conflictResult.message;
      widget.onConflictChanged?.call(conflictResult.hasConflict, conflictResult.message);
    }
  }

  String _formatDisplayDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr.split(' ').first);
      final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
      final dayName = days[dt.weekday - 1];
      final monthName = months[dt.month - 1];
      return '$dayName, ${dt.day} $monthName ${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  // ============ BUILD METHODS ============

  @override
  Widget build(BuildContext context) {
    final monitorState = ref.watch(monitorProvider);
    final assetName = _getAssetName();
    final selectedDate = _getSelectedDateString();
    final userTime = _getUserBookingTime();
    final kategori = widget.subUnit['monitor_kategori']?.toString() ?? 'Aset';

    final assetList = monitorState.assets.value ?? [];
    final calendarList = monitorState.calendar.value ?? [];

    final matchedAsset = assetName != null ? _findMatchingAsset(assetList, assetName) : null;
    final existingBookings = assetName != null
        ? _getBookingsForDateAndAsset(calendarList, selectedDate, assetName)
        : <MonitorCalendarItemModel>[];

    final conflictResult = _calculateConflict(
      assetName: assetName,
      userTime: userTime,
      existingBookings: existingBookings,
    );

    final isKendaraan = kategori.toLowerCase().contains('kendaraan') ||
        kategori.toLowerCase().contains('mobil') ||
        (matchedAsset != null &&
            (matchedAsset.tipe.toLowerCase().contains('kendaraan') ||
                matchedAsset.tipe.toLowerCase().contains('mobil')));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.oceanWater.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isKendaraan ? Icons.directions_car : Icons.meeting_room,
                    color: AppTheme.oceanWater,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE MONITOR • $kategori'.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: AppTheme.slateGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        assetName ?? 'Status Ketersediaan Aset',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.slateGrey),
                  tooltip: 'Perbarui Jadwal',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref.read(monitorProvider.notifier).refresh();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 1. Banner Status Terkini
            if (assetName == null || assetName.isEmpty)
              _buildNoAssetSelectedBanner(kategori)
            else
              _buildRealtimeStatusBanner(matchedAsset, assetName),

            // 2. Mini Bar Jadwal Ketersediaan (Slot Jam)
            if (assetName != null && assetName.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildScheduleMiniBar(
                selectedDate: selectedDate,
                existingBookings: existingBookings,
                userTime: userTime,
              ),
            ],

            // 3. Peringatan Bentrok Real-Time
            if (conflictResult.hasConflict) ...[
              const SizedBox(height: 14),
              _buildConflictAlert(conflictResult),
            ],
          ],
        ),
      ),
    );
  }

  // ============ SECTION 1: BANNER STATUS TERKINI ============

  Widget _buildNoAssetSelectedBanner(String kategori) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.oceanWater.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.touch_app_outlined, color: AppTheme.oceanWater, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pilih $kategori pada formulir di bawah untuk memantau status ketersediaan & jadwal terkini.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeStatusBanner(MonitorAssetModel? asset, String assetName) {
    final status = asset?.status ?? 'Tersedia';
    final Color primaryColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;
    final String title;
    final String description;
    final String? note;

    if (status == 'Sedang Dipakai') {
      primaryColor = AppTheme.danger;
      bgColor = const Color(0xFFFEF2F2);
      borderColor = AppTheme.danger.withValues(alpha: 0.3);
      icon = Icons.do_not_disturb_on_rounded;
      title = 'Sedang Digunakan';
      description = 'Sedang Digunakan oleh ${asset?.user ?? 'Pengguna'}${asset?.waktu != null && asset!.waktu!.isNotEmpty ? ' sampai pukul ${asset.waktu}' : ''}';
      note = 'Catatan: Anda tetap bisa memesan untuk jam setelahnya atau hari lain.';
    } else if (status == 'Dipesan' || status == 'Menunggu Persetujuan') {
      primaryColor = AppTheme.warning;
      bgColor = const Color(0xFFFFFBEB);
      borderColor = AppTheme.warning.withValues(alpha: 0.3);
      icon = Icons.schedule_rounded;
      title = 'Dipesan';
      description = 'Dipesan pukul ${asset?.waktu ?? '-'}${asset?.user != null ? ' oleh ${asset!.user}' : ''}';
      note = 'Pastikan jam pengajuan Anda tidak bentrok dengan jadwal yang telah terisi.';
    } else {
      primaryColor = AppTheme.success;
      bgColor = const Color(0xFFECFDF5);
      borderColor = AppTheme.success.withValues(alpha: 0.3);
      icon = Icons.check_circle_rounded;
      title = 'Tersedia';
      description = 'Tersedia saat ini - Tidak ada kegiatan berlangsung';
      note = null;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        assetName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
                ),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: primaryColor == AppTheme.danger ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ SECTION 2: MINI BAR JADWAL KETERSEDIAAN ============

  Widget _buildScheduleMiniBar({
    required String selectedDate,
    required List<MonitorCalendarItemModel> existingBookings,
    required UserBookingTime userTime,
  }) {
    const hours = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17]; // 08:00 - 18:00

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header with date
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.oceanWater),
                const SizedBox(width: 6),
                Text(
                  _formatDisplayDate(selectedDate),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ],
            ),
            const Text(
              '08:00 - 18:00 WIB',
              style: TextStyle(fontSize: 11, color: AppTheme.slateGrey, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Visual Mini Bar (10 slots)
        Row(
          children: hours.map((h) {
            final slotStart = h * 60;
            final slotEnd = (h + 1) * 60;

            // Check if slot overlaps with any booking
            MonitorCalendarItemModel? bookedBy;
            for (final b in existingBookings) {
              final range = _parseTimeRange(b.waktu);
              if (range != null && slotStart < range.endMinutes && slotEnd > range.startMinutes) {
                bookedBy = b;
                break;
              }
            }

            final isBooked = bookedBy != null;

            // Check if slot overlaps with user selection
            final isUserSelected = userTime.isComplete &&
                !userTime.isInvalidRange &&
                slotStart < userTime.endMinutes! &&
                slotEnd > userTime.startMinutes!;

            final isConflict = isBooked && isUserSelected;

            final Color bgColor;
            final Color borderColor;
            final Color textColor;
            final Widget subIndicator;
            final String tooltip;

            final hourStr = '${h.toString().padLeft(2, '0')}:00 - ${(h + 1).toString().padLeft(2, '0')}:00';

            if (isConflict) {
              bgColor = AppTheme.danger;
              borderColor = AppTheme.danger;
              textColor = Colors.white;
              subIndicator = const Icon(Icons.close_rounded, size: 10, color: Colors.white);
              tooltip = '$hourStr\nBENTROK dengan ${bookedBy.user} (${bookedBy.waktu})';
            } else if (isBooked) {
              bgColor = const Color(0xFFFEE2E2);
              borderColor = AppTheme.danger.withValues(alpha: 0.5);
              textColor = AppTheme.danger;
              subIndicator = const Icon(Icons.lock_rounded, size: 10, color: AppTheme.danger);
              tooltip = '$hourStr\nDipesan oleh ${bookedBy.user} (${bookedBy.waktu})';
            } else if (isUserSelected) {
              bgColor = AppTheme.brilliantBlue;
              borderColor = AppTheme.oceanWater;
              textColor = Colors.white;
              subIndicator = const Icon(Icons.check_rounded, size: 10, color: Colors.white);
              tooltip = '$hourStr\nPilihan Anda';
            } else {
              bgColor = const Color(0xFFF1F5F9);
              borderColor = Colors.grey.shade300;
              textColor = const Color(0xFF475569);
              subIndicator = Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                ),
              );
              tooltip = '$hourStr\nTersedia';
            }

            return Expanded(
              child: Tooltip(
                message: tooltip,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: isConflict ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        h.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      subIndicator,
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),

        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem(color: AppTheme.success, label: 'Tersedia'),
            const SizedBox(width: 14),
            _buildLegendItem(color: AppTheme.danger, label: 'Terisi'),
            const SizedBox(width: 14),
            _buildLegendItem(color: AppTheme.brilliantBlue, label: 'Pilihan Anda'),
          ],
        ),

        // User Selection Detail if provided
        if (userTime.rawStart != null || userTime.rawEnd != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.brilliantBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Jam diajukan: ${userTime.rawStart ?? '--:--'} s/d ${userTime.rawEnd ?? '--:--'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brilliantBlue,
                ),
              ),
            ),
          ),
        ],

        // Existing Bookings Breakdown for this date
        if (existingBookings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Daftar Reservasi (${_formatDisplayDate(selectedDate)}):',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 6),
          ...existingBookings.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppTheme.slateGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b.user,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.access_time, size: 14, color: AppTheme.slateGrey),
                    const SizedBox(width: 4),
                    Text(
                      b.waktu,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                    ),
                  ],
                ),
              )),
        ] else ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Belum ada reservasi lain pada tanggal ini.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ============ SECTION 3: PERINGATAN BENTROK REAL-TIME ============

  Widget _buildConflictAlert(ConflictResult conflict) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.danger, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jadwal Bentrok!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.danger),
                ),
                const SizedBox(height: 3),
                Text(
                  conflict.message ?? 'Jadwal yang Anda pilih bentrok dengan reservasi yang sudah ada.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), height: 1.3),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Silakan ubah jam atau tanggal pemesanan untuk melanjutkan.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
