import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/models/album.dart';
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';
import 'package:qq_zone_flutter_downloader/core/services/download_record_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/notification_service.dart';
import 'package:qq_zone_flutter_downloader/core/services/qzone_service.dart';
import 'package:flutter/foundation.dart';

// 自定义异常：相册已经下载过
class AlbumAlreadyDownloadedException implements Exception {
  final DownloadRecord existingRecord;

  AlbumAlreadyDownloadedException(this.existingRecord);

  @override
  String toString() {
    return '相册 "${existingRecord.albumName}" 已经下载过';
  }
}

// 下载管理器状态
class DownloadManagerState {
  final Map<String, DownloadRecord> activeDownloads; // 当前活跃的下载 (id -> record)

  DownloadManagerState({Map<String, DownloadRecord>? activeDownloads})
      : activeDownloads = activeDownloads ?? {};

  DownloadManagerState copyWith({
    Map<String, DownloadRecord>? activeDownloads,
  }) {
    return DownloadManagerState(
      activeDownloads: activeDownloads ?? this.activeDownloads,
    );
  }
}

// 下载管理器
class DownloadManager extends StateNotifier<DownloadManagerState> {
  final DownloadRecordService _recordService;
  final QZoneService _qzoneService;
  final NotificationService _notificationService;

  DownloadManager(
      this._recordService, this._qzoneService, this._notificationService)
      : super(DownloadManagerState());

  // 检查相册是否已经下载过
  Future<DownloadRecord?> checkAlbumDownloaded(String albumId) async {
    return await _recordService.hasAlbumBeenDownloaded(albumId);
  }

  // 开始下载相册
  Future<void> downloadAlbum({
    required Album album,
    required String savePath,
    String? targetUin,
    bool skipExisting = true,
    bool forceDownload = false, // 新增参数，是否强制下载（即使已经下载过）
  }) async {
    // 检查是否正在下载
    if (state.activeDownloads.containsKey(album.id)) {
      if (kDebugMode) {
        print("[DownloadManager] 相册已在下载队列中: ${album.name}");
      }
      return;
    }

    // 如果不是强制下载，检查是否已经下载过
    if (!forceDownload) {
      final existingRecord = await _recordService.hasAlbumBeenDownloaded(album.id);
      if (existingRecord != null) {
        if (kDebugMode) {
          print("[DownloadManager] 相册已经下载过: ${album.name}");
        }
        // 返回已存在的记录，由调用方决定是否继续下载
        throw AlbumAlreadyDownloadedException(existingRecord);
      }
    }

    // 创建进行中记录
    final record = DownloadRecord.inProgress(
      album: album,
      targetUin: targetUin ?? _qzoneService.loggedInUin ?? '',
      savePath: savePath,
      totalCount: album.photoCount,
    );

    // 保存到记录服务
    await _recordService.addRecord(record);

    // 更新状态
    state = state.copyWith(
      activeDownloads: {...state.activeDownloads, record.id: record},
    );

    try {
      // 开始下载
      final result = await _qzoneService.downloadAlbum(
        album: album,
        savePath: savePath,
        targetUin: targetUin,
        skipExisting: skipExisting,
        downloadId: record.id, // 使用记录ID作为下载ID
        onProgress: (current, total, message) async {
          if (kDebugMode) {
            print("[DownloadManager] 进度更新: $current/$total - $message");
          }

          // 计算进度百分比（0-100%）
          double progressPercent = total > 0 ? current / total : 0;

          // 更新记录和状态
          final updatedRecord = record.copyWith(
            currentProgress: current,
            currentMessage: message,
          );

          // 更新记录服务 - 只在文件完成时更新数据库，减少IO操作
          if (message.contains('下载完成') || current == 0 || current % 10 == 0) {
            await _recordService.updateDownloadProgress(
                record.id, current, total, message);
          }

          // 更新状态 - 只在文件完成时或每1个文件更新一次状态，减少UI刷新
          if (message.contains('下载完成') || current == 0 || current % 1 == 0) {
            state = state.copyWith(
              activeDownloads: {
                ...state.activeDownloads,
                record.id: updatedRecord
              },
            );

            // 更新通知
            _notificationService.showDownloadProgress(
              id: record.id.hashCode,
              title: "正在下载 ${album.name}",
              message: "$message ($current/$total)",
              progress: progressPercent,
              maxProgress: 1.0,
            );
          }
        },
        onItemComplete: (result) {
          // 可以处理单个项目完成事件
          if (kDebugMode) {
            print(
                "[DownloadManager] 文件下载完成: ${result['filename']}, 状态: ${result['status']}");
          }
        },
      );

      // 完成下载，更新记录
      await _recordService.completeDownload(
        record.id,
        successCount: result['success'],
        failedCount: result['failed'],
        skippedCount: result['skipped'],
      );

      // 更新状态，移除活跃下载
      final newActiveDownloads =
          Map<String, DownloadRecord>.from(state.activeDownloads);
      newActiveDownloads.remove(record.id);
      state = state.copyWith(activeDownloads: newActiveDownloads);

      // 发送通知
      _notificationService.showBatchDownloadComplete(
        albumName: album.name,
        total: result['total'],
        success: result['success'],
        failed: result['failed'],
        skipped: result['skipped'],
        savePath: '$savePath/${album.name}',
      );
    } catch (e) {
      if (kDebugMode) {
        print("[DownloadManager] 下载失败: $e");
      }

      // 更新为失败状态
      await _recordService.completeDownload(
        record.id,
        successCount: 0,
        failedCount: record.totalCount,
        skippedCount: 0,
      );

      // 更新状态，移除活跃下载
      final newActiveDownloads =
          Map<String, DownloadRecord>.from(state.activeDownloads);
      newActiveDownloads.remove(record.id);
      state = state.copyWith(activeDownloads: newActiveDownloads);
    }
  }

  // 取消下载
  Future<void> cancelDownload(String recordId) async {
    if (!state.activeDownloads.containsKey(recordId)) {
      return;
    }

    if (kDebugMode) {
      print("[DownloadManager] 取消下载: $recordId");
    }

    // 调用QZoneService取消下载任务
    _qzoneService.cancelDownload(recordId);

    // 标记为已完成（取消）
    await _recordService.completeDownload(
      recordId,
      successCount: 0,
      failedCount: 0,
      skippedCount: 0,
    );

    // 获取记录信息用于通知（在移除前获取）
    final DownloadRecord? record = state.activeDownloads[recordId];

    // 从活跃下载中移除
    final newActiveDownloads =
        Map<String, DownloadRecord>.from(state.activeDownloads);
    newActiveDownloads.remove(recordId);
    state = state.copyWith(activeDownloads: newActiveDownloads);

    // 更新状态后发送通知
    if (record != null) {
      _notificationService.showDownloadCancelled(
        albumName: record.albumName,
      );
    }
  }
}
