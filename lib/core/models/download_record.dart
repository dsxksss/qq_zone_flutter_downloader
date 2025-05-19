import 'package:qq_zone_flutter_downloader/core/models/album.dart';

class DownloadRecord {
  final String id; // 唯一ID
  final String albumId; // 相册ID
  final String albumName; // 相册名称
  final String targetUin; // 所属QQ
  final String savePath; // 保存路径
  final int totalCount; // 总数量
  int successCount; // 成功数量
  int failedCount; // 失败数量
  int skippedCount; // 跳过数量
  bool isComplete; // 是否完成
  final DateTime downloadTime; // 下载时间
  final bool isVideo; // 是否为视频
  final String? thumbnailUrl; // 缩略图URL
  final String? filename; // 单个文件名称（批量下载为null）
  // 新增字段
  int currentProgress; // 当前进度（已处理数量）
  String currentMessage; // 当前状态消息
  DateTime lastUpdated; // 最后更新时间

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
    this.currentProgress = 0,
    this.currentMessage = '',
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  // 创建批量下载记录
  factory DownloadRecord.fromBatchDownload({
    required Album album,
    required String targetUin,
    required String savePath,
    required int totalCount,
    required int successCount,
    required int failedCount,
    required int skippedCount,
    bool isComplete = true,
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
      isComplete: isComplete,
      downloadTime: DateTime.now(),
      thumbnailUrl: album.coverUrl,
    );
  }

  // 新增：创建进行中的下载记录
  factory DownloadRecord.inProgress({
    required Album album,
    required String targetUin,
    required String savePath,
    required int totalCount,
  }) {
    return DownloadRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      albumId: album.id,
      albumName: album.name,
      targetUin: targetUin,
      savePath: savePath,
      totalCount: totalCount,
      successCount: 0,
      failedCount: 0,
      skippedCount: 0,
      isComplete: false,
      downloadTime: DateTime.now(),
      thumbnailUrl: album.coverUrl,
      currentProgress: 0,
      currentMessage: '准备下载...',
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
      currentProgress: json['currentProgress'] ?? 0,
      currentMessage: json['currentMessage'] ?? '',
      lastUpdated: json['lastUpdated'] != null ? DateTime.parse(json['lastUpdated']) : DateTime.now(),
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
      'currentProgress': currentProgress,
      'currentMessage': currentMessage,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  // 更新记录（创建一个新的实例）
  DownloadRecord copyWith({
    int? successCount,
    int? failedCount,
    int? skippedCount,
    bool? isComplete,
    int? currentProgress,
    String? currentMessage,
    double? progressPercent,
  }) {
    return DownloadRecord(
      id: id,
      albumId: albumId,
      albumName: albumName,
      targetUin: targetUin,
      savePath: savePath,
      totalCount: totalCount,
      successCount: successCount ?? this.successCount,
      failedCount: failedCount ?? this.failedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      isComplete: isComplete ?? this.isComplete,
      downloadTime: downloadTime,
      isVideo: isVideo,
      thumbnailUrl: thumbnailUrl,
      filename: filename,
      currentProgress: currentProgress ?? this.currentProgress,
      currentMessage: currentMessage ?? this.currentMessage,
      lastUpdated: DateTime.now(),
    );
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

  // 获取下载进度百分比
  double get progressPercentage {
    if (totalCount == 0) return 0.0;
    return currentProgress / totalCount;
  }
} 