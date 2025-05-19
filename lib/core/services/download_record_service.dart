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
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_recordsFileName');
      
      if (await file.exists()) {
        final String data = await file.readAsString();
        if (data.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(data);
          _records = jsonList.map((json) => DownloadRecord.fromJson(json)).toList();
          
          // 按下载时间倒序排序
          _records.sort((a, b) => b.downloadTime.compareTo(a.downloadTime));
        }
      } else {
        // 创建空文件
        await file.create();
        await file.writeAsString('[]');
      }
      
      _isInitialized = true;
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

  // 删除下载记录
  Future<void> deleteRecord(String recordId) async {
    await initialize();
    
    _records.removeWhere((r) => r.id == recordId);
    await _saveRecords();
  }

  // 批量删除下载记录
  Future<void> deleteRecords(List<String> recordIds) async {
    await initialize();
    
    _records.removeWhere((r) => recordIds.contains(r.id));
    await _saveRecords();
  }

  // 清空所有下载记录
  Future<void> clearAllRecords() async {
    await initialize();
    
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