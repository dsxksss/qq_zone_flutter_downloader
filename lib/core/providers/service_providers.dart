import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/services/qzone_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/notification_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/download_record_service.dart';
import 'package:qq_zone_flutter_downloader/core/providers/download_manager_provider.dart';
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';

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

// 下载管理器提供者
final downloadManagerProvider = StateNotifierProvider<DownloadManager, DownloadManagerState>((ref) {
  return DownloadManager(
    ref.watch(downloadRecordServiceProvider),
    ref.watch(qZoneServiceProvider),
    ref.watch(notificationServiceProvider),
  );
});

// 活跃下载Provider
final activeDownloadsProvider = FutureProvider<List<DownloadRecord>>((ref) {
  return ref.watch(downloadRecordServiceProvider).getActiveDownloads();
});

// 所有下载记录Provider
final allDownloadsProvider = FutureProvider<List<DownloadRecord>>((ref) {
  return ref.watch(downloadRecordServiceProvider).getAllRecords();
}); 