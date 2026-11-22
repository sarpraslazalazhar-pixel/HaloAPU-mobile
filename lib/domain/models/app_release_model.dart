/// Metadata rilis aplikasi mobile yang dikembalikan oleh endpoint `GET /api/app-version`.
class AppReleaseModel {
  final int id;
  final String platform;
  final String channel;
  final String versionName;
  final int buildNumber;
  final int minSupportedBuildNumber;
  final bool forceUpdate;
  final String? title;
  final String? releaseNotes;
  final String downloadUrl;
  final String? sha256;
  final int? fileSizeBytes;
  final DateTime? publishedAt;

  const AppReleaseModel({
    required this.id,
    required this.platform,
    required this.channel,
    required this.versionName,
    required this.buildNumber,
    this.minSupportedBuildNumber = 0,
    this.forceUpdate = false,
    this.title,
    this.releaseNotes,
    required this.downloadUrl,
    this.sha256,
    this.fileSizeBytes,
    this.publishedAt,
  });

  factory AppReleaseModel.fromJson(Map<String, dynamic> json) {
    return AppReleaseModel(
      id: _parseInt(json['id']) ?? 0,
      platform: (json['platform'] ?? 'android').toString(),
      channel: (json['channel'] ?? 'production').toString(),
      versionName: (json['version_name'] ?? json['versionName'] ?? '').toString(),
      buildNumber: _parseInt(json['build_number'] ?? json['buildNumber']) ?? 0,
      minSupportedBuildNumber: _parseInt(
            json['min_supported_build_number'] ?? json['minSupportedBuildNumber'],
          ) ??
          0,
      forceUpdate: _parseBool(json['force_update'] ?? json['forceUpdate']),
      title: json['title']?.toString(),
      releaseNotes: (json['release_notes'] ?? json['releaseNotes'])?.toString(),
      downloadUrl: (json['download_url'] ?? json['downloadUrl'] ?? '').toString(),
      sha256: json['sha256']?.toString(),
      fileSizeBytes: _parseInt(json['file_size_bytes'] ?? json['fileSizeBytes']),
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : (json['publishedAt'] != null
              ? DateTime.tryParse(json['publishedAt'].toString())
              : null),
    );
  }

  /// Format ukuran file yang ramah dibaca (mis. `28.4 MB`).
  String get formattedFileSize {
    final bytes = fileSizeBytes;
    if (bytes == null || bytes <= 0) return '';
    return formatBytes(bytes);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) {
      return '$bytes B';
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  static int? _parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  static bool _parseBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }
}
