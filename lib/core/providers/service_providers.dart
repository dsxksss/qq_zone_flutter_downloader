import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/services/qzone_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/notification_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/download_record_service.dart';

// QZone服务提供者
final qZoneServiceProvider = Provider<QZoneService>((ref) {
  return QZoneService();
});

// 通知服务提供者
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// 下载记录服务提供者
final downloadRecordServiceProvider = Provider<DownloadRecordService>((ref) {
  return DownloadRecordService();
}); 