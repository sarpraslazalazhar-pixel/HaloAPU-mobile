import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_model.freezed.dart';
part 'notification_model.g.dart';

enum NotificationType {
  @JsonValue('ticket') ticket,
  @JsonValue('reply') reply,
  @JsonValue('solved') solved,
  @JsonValue('revision') revision,
  @JsonValue('rejected') rejected,
  @JsonValue('csat') csat,
  @JsonValue('sla') sla,
  @JsonValue('edited') edited,
  @JsonValue('app_update') appUpdate,
}

int? _parseOptionalInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString().trim());
}

String? _readNonEmptyString(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

@freezed
sealed class NotificationModel with _$NotificationModel {
  const factory NotificationModel({
    required String id,
    required String title,
    required String body,
    @JsonKey(unknownEnumValue: NotificationType.ticket)
    required NotificationType type,
    required DateTime createdAt,
    required bool isRead,
    String? ticketId,
    String? channel,
    @JsonKey(name: 'version_name') String? versionName,
    @JsonKey(name: 'build_number', fromJson: _parseOptionalInt) int? buildNumber,
  }) = _NotificationModel;

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      _$NotificationModelFromJson(json);

  factory NotificationModel.safeFromJson(Map<String, dynamic> json) {
    final nestedData = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : const <String, dynamic>{};
    final nestedMeta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : const <String, dynamic>{};

    final rawType = _readNonEmptyString(
      json['type'] ?? nestedData['type'] ?? nestedMeta['type'],
    );
    final resolvedType = switch (rawType) {
      'reply' => NotificationType.reply,
      'solved' => NotificationType.solved,
      'revision' => NotificationType.revision,
      'rejected' => NotificationType.rejected,
      'csat' => NotificationType.csat,
      'sla' => NotificationType.sla,
      'edited' => NotificationType.edited,
      'app_update' => NotificationType.appUpdate,
      _ => NotificationType.ticket,
    };

    final rawCreatedAt =
        _readNonEmptyString(json['createdAt'] ?? json['created_at']);
    final createdAt = (rawCreatedAt != null ? DateTime.tryParse(rawCreatedAt) : null) ??
        DateTime.now();

    final rawIsRead = json['isRead'] ?? json['is_read'];
    final isRead = rawIsRead is bool
        ? rawIsRead
        : rawIsRead?.toString().toLowerCase() == 'true' ||
            rawIsRead?.toString() == '1';

    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: _readNonEmptyString(json['title']) ?? 'Notifikasi',
      body: _readNonEmptyString(
            json['body'] ?? json['message'] ?? nestedData['body'] ?? nestedData['message'],
          ) ??
          '',
      type: resolvedType,
      createdAt: createdAt,
      isRead: isRead,
      ticketId: _readNonEmptyString(
        json['ticketId'] ??
            json['ticket_id'] ??
            nestedData['ticketId'] ??
            nestedData['ticket_id'],
      ),
      channel: _readNonEmptyString(
        json['channel'] ?? nestedData['channel'] ?? nestedMeta['channel'],
      ),
      versionName: _readNonEmptyString(
        json['version_name'] ??
            json['versionName'] ??
            nestedData['version_name'] ??
            nestedData['versionName'] ??
            nestedMeta['version_name'] ??
            nestedMeta['versionName'],
      ),
      buildNumber: _parseOptionalInt(
        json['build_number'] ??
            json['buildNumber'] ??
            nestedData['build_number'] ??
            nestedData['buildNumber'] ??
            nestedMeta['build_number'] ??
            nestedMeta['buildNumber'],
      ),
    );
  }
}
