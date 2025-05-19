import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';

class DownloadRecordService {
  static const String _recordsFileName = 'download_records.json';
  List<DownloadRecord> _records = [];
  bool _isInitialized = false;

  // 初始化，从本地读取记录
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_recordsFileName');

      if (await file.exists()) {
        final String data = await file.readAsString();
        if (data.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(data);
          _records =
              jsonList.map((json) => DownloadRecord.fromJson(json)).toList();

          // 按下载时间倒序排序
          _records.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
        } else {
          _records = [];
        }
      } else {
        // 创建空文件
        await file.create();
        await file.writeAsString('[]');
        _records = [];
      }

      _isInitialized = true;

      if (kDebugMode && forceReload) {
        print("[DownloadRecordService] 强制重新加载记录，共加载 ${_records.length} 条记录");
      }
    } catch (e) {
      if (kDebugMode) {
        print("[DownloadRecordService] 初始化失败: $e");
      }
      // 如果读取失败，初始化为空列表
      _records = [];
      _isInitialized = true;
    }
  }

  // 获取所有下载记录
  Future<List<DownloadRecord>> getAllRecords() async {
    await initialize();
    return _records;
  }

  // 获取正在进行中的下载记录
  Future<List<DownloadRecord>> getActiveDownloads() async {
    await initialize();
    return _records.where((record) => !record.isComplete).toList();
  }

  // 添加下载记录
  Future<void> addRecord(DownloadRecord record) async {
    await initialize();

    // 避免重复记录
    if (_records.any((r) => r.id == record.id)) {
      return;
    }

    _records.insert(0, record); // 添加到列表开头
    await _saveRecords();
  }

  // 更新下载记录
  Future<void> updateRecord(DownloadRecord record) async {
    await initialize();

    final index = _records.indexWhere((r) => r.id == record.id);
    if (index != -1) {
      _records[index] = record;
      await _saveRecords();
    }
  }

  // 更新下载进度
  Future<void> updateDownloadProgress(
      String recordId, int current, int total, String message) async {
    await initialize();

    final index = _records.indexWhere((r) => r.id == recordId);
    if (index != -1) {
      final record = _records[index];
      _records[index] = record.copyWith(
        currentProgress: current,
        currentMessage: message,
      );
      await _saveRecords();
    }
  }

  // 更新下载结果
  Future<void> completeDownload(
    String recordId, {
    required int successCount,
    required int failedCount,
    required int skippedCount,
  }) async {
    await initialize();

    final index = _records.indexWhere((r) => r.id == recordId);
    if (index != -1) {
      final record = _records[index];
      _records[index] = record.copyWith(
        isComplete: true,
        successCount: successCount,
        failedCount: failedCount,
        skippedCount: skippedCount,
        currentMessage: '下载完成',
        currentProgress: record.totalCount,
      );
      await _saveRecords();
    }
  }

  // 删除下载记录
  Future<void> deleteRecord(String recordId, {bool deleteFiles = false}) async {
    await initialize();

    if (deleteFiles) {
      // 先获取记录，然后删除文件
      try {
        final record = _records.firstWhere((r) => r.id == recordId);
        await _deleteRecordFiles(record);
      } catch (e) {
        // 记录不存在，忽略
        if (kDebugMode) {
          print("[DownloadRecordService] 记录不存在: $recordId");
        }
      }
    }

    _records.removeWhere((r) => r.id == recordId);
    await _saveRecords();
  }

  // 批量删除下载记录
  Future<void> deleteRecords(List<String> recordIds,
      {bool deleteFiles = false}) async {
    await initialize();

    if (deleteFiles) {
      // 先获取所有要删除的记录
      final recordsToDelete =
          _records.where((r) => recordIds.contains(r.id)).toList();

      if (kDebugMode) {
        print("[DownloadRecordService] 准备删除 ${recordsToDelete.length} 条记录的文件");
      }

      // 按照相册分组，避免重复删除同一个相册
      final albumPaths = <String>{};
      final singleFiles = <DownloadRecord>[];

      for (final record in recordsToDelete) {
        if (record.filename != null) {
          // 单个文件记录
          singleFiles.add(record);
        } else {
          // 相册记录，记录相册路径
          final albumPath = '${record.savePath}/${record.albumName}';
          albumPaths.add(albumPath);
        }
      }

      // 删除相册目录
      for (final albumPath in albumPaths) {
        try {
          final directory = Directory(albumPath);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
            if (kDebugMode) {
              print("[DownloadRecordService] 已删除整个相册目录: $albumPath");
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[DownloadRecordService] 删除相册目录失败: $albumPath, 错误: $e");
          }
        }
      }

      // 删除单个文件
      for (final record in singleFiles) {
        await _deleteRecordFiles(record);
      }
    }

    _records.removeWhere((r) => recordIds.contains(r.id));
    await _saveRecords();
  }

  // 删除记录相关的文件
  Future<void> _deleteRecordFiles(DownloadRecord record) async {
    try {
      if (record.filename != null) {
        // 单个文件下载记录
        final filePath = '${record.savePath}/${record.filename}';
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {
            print("[DownloadRecordService] 已删除文件: $filePath");
          }
        }
      } else {
        // 批量下载记录，直接删除整个相册目录
        final albumPath = '${record.savePath}/${record.albumName}';
        final directory = Directory(albumPath);
        if (await directory.exists()) {
          // 直接删除整个目录
          await directory.delete(recursive: true);
          if (kDebugMode) {
            print("[DownloadRecordService] 已删除整个相册目录: $albumPath");
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[DownloadRecordService] 删除文件失败: $e");
      }
    }
  }

  // 清空所有下载记录
  Future<void> clearAllRecords({bool deleteFiles = false}) async {
    await initialize();

    if (deleteFiles) {
      if (kDebugMode) {
        print("[DownloadRecordService] 准备清空所有记录的文件，共 ${_records.length} 条记录");
      }

      // 按照相册分组，避免重复删除同一个相册
      final albumPaths = <String>{};
      final singleFiles = <DownloadRecord>[];

      for (final record in _records) {
        if (record.filename != null) {
          // 单个文件记录
          singleFiles.add(record);
        } else {
          // 相册记录，记录相册路径
          final albumPath = '${record.savePath}/${record.albumName}';
          albumPaths.add(albumPath);
        }
      }

      // 删除相册目录
      for (final albumPath in albumPaths) {
        try {
          final directory = Directory(albumPath);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
            if (kDebugMode) {
              print("[DownloadRecordService] 已删除整个相册目录: $albumPath");
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[DownloadRecordService] 删除相册目录失败: $albumPath, 错误: $e");
          }
        }
      }

      // 删除单个文件
      for (final record in singleFiles) {
        await _deleteRecordFiles(record);
      }
    }

    _records.clear();
    await _saveRecords();
  }

  // 保存记录到本地
  Future<void> _saveRecords() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_recordsFileName');

      final String data = jsonEncode(_records.map((r) => r.toJson()).toList());
      await file.writeAsString(data);
    } catch (e) {
      if (kDebugMode) {
        print("[DownloadRecordService] 保存记录失败: $e");
      }
    }
  }

  // 检查并删除不存在的文件记录
  Future<int> cleanupNonExistentRecords() async {
    await initialize();
    int removedCount = 0;

    List<DownloadRecord> recordsToRemove = [];

    for (var record in _records) {
      if (record.filename != null) {
        // 单个文件下载记录
        final filePath = '${record.savePath}/${record.filename}';
        final file = File(filePath);
        if (!await file.exists()) {
          recordsToRemove.add(record);
          removedCount++;
        }
      } else {
        // 批量下载记录，检查目录是否存在
        final directory = Directory(record.savePath);
        if (!await directory.exists()) {
          recordsToRemove.add(record);
          removedCount++;
        }
      }
    }

    if (recordsToRemove.isNotEmpty) {
      _records.removeWhere((r) => recordsToRemove.contains(r));
      await _saveRecords();
    }

    return removedCount;
  }

  // 获取特定记录
  Future<DownloadRecord?> getRecord(String recordId) async {
    await initialize();

    try {
      return _records.firstWhere((r) => r.id == recordId);
    } catch (e) {
      return null;
    }
  }

  // 根据相册ID获取记录
  Future<List<DownloadRecord>> getRecordsByAlbumId(String albumId) async {
    await initialize();

    return _records.where((r) => r.albumId == albumId).toList();
  }
}
