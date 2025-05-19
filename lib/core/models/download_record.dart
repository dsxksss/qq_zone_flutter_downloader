import 'package:qq_zone_flutter_downloader/core/models/album.dart';

class DownloadRecord {
  final String id; // 唯一ID
  final String albumId; // 相册ID
  final String albumName; // 相册名称
  final String targetUin; // 所属QQ
  final String savePath; // 保存路径
  final int totalCount; // 总数量
  final int successCount; // 成功数量
  final int failedCount; // 失败数量
  final int skippedCount; // 跳过数量
  final bool isComplete; // 是否完成
  final DateTime downloadTime; // 下载时间
  final bool isVideo; // 是否为视频
  final String? thumbnailUrl; // 缩略图URL
  final String? filename; // 单个文件名称（批量下载为null）

  DownloadRecord({
    required this.id,
    required this.albumId,
    required this.albumName,
    required this.targetUin,
    required this.savePath,
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    required this.isComplete,
    required this.downloadTime,
    this.isVideo = false,
    this.thumbnailUrl,
    this.filename,
  });

  // 创建批量下载记录
  factory DownloadRecord.fromBatchDownload({
    required Album album,
    required String targetUin,
    required String savePath,
    required int totalCount,
    required int successCount,
    required int failedCount,
    required int skippedCount,
  }) {
    return DownloadRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      albumId: album.id,
      albumName: album.name,
      targetUin: targetUin,
      savePath: savePath,
      totalCount: totalCount,
      successCount: successCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      isComplete: true,
      downloadTime: DateTime.now(),
      thumbnailUrl: album.coverUrl,
    );
  }

  // 创建单个文件下载记录
  factory DownloadRecord.fromSingleFile({
    required String albumId,
    required String albumName,
    required String targetUin,
    required String savePath,
    required String filename,
    required bool isVideo,
    String? thumbnailUrl,
  }) {
    return DownloadRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      albumId: albumId,
      albumName: albumName,
      targetUin: targetUin,
      savePath: savePath,
      totalCount: 1,
      successCount: 1,
      failedCount: 0,
      skippedCount: 0,
      isComplete: true,
      downloadTime: DateTime.now(),
      isVideo: isVideo,
      thumbnailUrl: thumbnailUrl,
      filename: filename,
    );
  }

  // 从JSON转换
  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    return DownloadRecord(
      id: json['id'],
      albumId: json['albumId'],
      albumName: json['albumName'],
      targetUin: json['targetUin'],
      savePath: json['savePath'],
      totalCount: json['totalCount'],
      successCount: json['successCount'],
      failedCount: json['failedCount'],
      skippedCount: json['skippedCount'],
      isComplete: json['isComplete'],
      downloadTime: DateTime.parse(json['downloadTime']),
      isVideo: json['isVideo'] ?? false,
      thumbnailUrl: json['thumbnailUrl'],
      filename: json['filename'],
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'albumId': albumId,
      'albumName': albumName,
      'targetUin': targetUin,
      'savePath': savePath,
      'totalCount': totalCount,
      'successCount': successCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      'isComplete': isComplete,
      'downloadTime': downloadTime.toIso8601String(),
      'isVideo': isVideo,
      'thumbnailUrl': thumbnailUrl,
      'filename': filename,
    };
  }

  // 格式化下载时间
  String get formattedDownloadTime {
    return '${downloadTime.year}-${downloadTime.month.toString().padLeft(2, '0')}-${downloadTime.day.toString().padLeft(2, '0')} ${downloadTime.hour.toString().padLeft(2, '0')}:${downloadTime.minute.toString().padLeft(2, '0')}';
  }

  // 获取状态描述
  String get statusText {
    if (isComplete) {
      if (totalCount == successCount) {
        return '下载完成';
      } else if (successCount > 0) {
        return '部分完成';
      } else {
        return '下载失败';
      }
    } else {
      return '下载中';
    }
  }
} 