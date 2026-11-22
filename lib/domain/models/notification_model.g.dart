// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NotificationModel _$NotificationModelFromJson(Map<String, dynamic> json) =>
    _NotificationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: $enumDecode(
        _$NotificationTypeEnumMap,
        json['type'],
        unknownValue: NotificationType.ticket,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool,
      ticketId: json['ticketId'] as String?,
      channel: json['channel'] as String?,
      versionName: json['version_name'] as String?,
      buildNumber: _parseOptionalInt(json['build_number']),
    );

Map<String, dynamic> _$NotificationModelToJson(_NotificationModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'type': _$NotificationTypeEnumMap[instance.type]!,
      'createdAt': instance.createdAt.toIso8601String(),
      'isRead': instance.isRead,
      'ticketId': instance.ticketId,
      'channel': instance.channel,
      'version_name': instance.versionName,
      'build_number': instance.buildNumber,
    };

const _$NotificationTypeEnumMap = {
  NotificationType.ticket: 'ticket',
  NotificationType.reply: 'reply',
  NotificationType.solved: 'solved',
  NotificationType.revision: 'revision',
  NotificationType.rejected: 'rejected',
  NotificationType.csat: 'csat',
  NotificationType.sla: 'sla',
  NotificationType.edited: 'edited',
  NotificationType.appUpdate: 'app_update',
};
