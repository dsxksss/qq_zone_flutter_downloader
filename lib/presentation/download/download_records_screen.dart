import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:path/path.dart' as p;

class DownloadRecordsScreen extends ConsumerStatefulWidget {
  const DownloadRecordsScreen({super.key});

  @override
  ConsumerState<DownloadRecordsScreen> createState() => _DownloadRecordsScreenState();
}

class _DownloadRecordsScreenState extends ConsumerState<DownloadRecordsScreen> {
  List<DownloadRecord> _records = [];
  bool _isLoading = true;
  bool _isSelectMode = false;
  Set<String> _selectedRecords = {};

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final recordService = ref.read(downloadRecordServiceProvider);
      final records = await recordService.getAllRecords();

      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载下载记录失败: $e')),
        );
      }
    }
  }

  // 切换选择模式
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      _selectedRecords.clear(); // 清空已选项
    });
  }

  // 选择/取消选择记录
  void _toggleSelectRecord(String recordId) {
    setState(() {
      if (_selectedRecords.contains(recordId)) {
        _selectedRecords.remove(recordId);
      } else {
        _selectedRecords.add(recordId);
      }
    });
  }

  // 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedRecords.length == _records.length) {
        _selectedRecords.clear();
      } else {
        _selectedRecords = _records.map((r) => r.id).toSet();
      }
    });
  }

  // 删除所选记录
  Future<void> _deleteSelectedRecords() async {
    if (_selectedRecords.isEmpty) return;
    
    // 显示确认对话框
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        title: const Text('确认删除'),
        body: Text('确定要删除所选的 ${_selectedRecords.length} 条下载记录吗？\n注意：这只会删除记录，不会删除已下载的文件。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        await recordService.deleteRecords(_selectedRecords.toList());
        
        // 刷新列表
        await _loadRecords();
        
        // 退出选择模式
        setState(() {
          _isSelectMode = false;
          _selectedRecords.clear();
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除所选记录')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除记录失败: $e')),
          );
        }
      }
    }
  }

  // 删除单个记录
  Future<void> _deleteRecord(DownloadRecord record) async {
    // 显示确认对话框
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        title: const Text('确认删除'),
        body: Text('确定要删除"${record.albumName}"的下载记录吗？\n注意：这只会删除记录，不会删除已下载的文件。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        await recordService.deleteRecord(record.id);
        
        // 刷新列表
        await _loadRecords();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除"${record.albumName}"的下载记录')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除记录失败: $e')),
          );
        }
      }
    }
  }
  
  // 清理所有记录
  Future<void> _clearAllRecords() async {
    if (_records.isEmpty) return;
    
    // 显示确认对话框
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        title: const Text('清空所有记录'),
        body: const Text('确定要清空所有下载记录吗？\n注意：这只会删除记录，不会删除已下载的文件。'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        await recordService.clearAllRecords();
        
        // 刷新列表
        await _loadRecords();
        
        // 退出选择模式
        setState(() {
          _isSelectMode = false;
          _selectedRecords.clear();
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清空所有下载记录')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清空记录失败: $e')),
          );
        }
      }
    }
  }
  
  // 清理无效记录（文件已删除的记录）
  Future<void> _cleanupInvalidRecords() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final recordService = ref.read(downloadRecordServiceProvider);
      final removedCount = await recordService.cleanupNonExistentRecords();
      
      // 刷新列表
      await _loadRecords();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理完成，已移除 $removedCount 条无效记录')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理无效记录失败: $e')),
        );
      }
    }
  }
  
  // 打开文件所在目录
  Future<void> _openFolder(DownloadRecord record) async {
    try {
      // 由于不同平台的文件管理器打开方式不同，这里只简单地显示路径信息
      showDialog(
        context: context,
        builder: (context) => FDialog(
          title: const Text('文件位置'),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('保存路径：${record.savePath}'),
              if (record.filename != null)
                Text('文件名：${record.filename}'),
              
              const SizedBox(height: 8),
              
              const Text('您可以通过文件管理器访问以上位置来查看下载的文件。'),
            ],
          ),
          actions: [
            FButton(
              onPress: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件夹失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载记录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedRecords.isNotEmpty ? _deleteSelectedRecords : null,
              tooltip: '删除所选',
            ),
          if (_records.isNotEmpty)
            IconButton(
              icon: Icon(_isSelectMode ? Icons.cancel : Icons.select_all),
              onPressed: _toggleSelectMode,
              tooltip: _isSelectMode ? '取消选择' : '选择模式',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecords,
            tooltip: '刷新',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'cleanup':
                  _cleanupInvalidRecords();
                  break;
                case 'clear_all':
                  _clearAllRecords();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cleanup',
                child: Text('清理无效记录'),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Text('清空所有记录'),
              ),
            ],
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: FProgress());
    }
    
    if (_records.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无下载记录', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // 选择模式下显示操作栏
        if (_isSelectMode) 
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _selectedRecords.length == _records.length && _records.isNotEmpty,
                      onChanged: (_) => _toggleSelectAll(),
                    ),
                    GestureDetector(
                      onTap: _toggleSelectAll,
                      child: const Text('全选'),
                    ),
                  ],
                ),
                Text('已选择 ${_selectedRecords.length}/${_records.length} 项'),
              ],
            ),
          ),
          
        // 记录列表
        Expanded(
          child: ListView.builder(
            itemCount: _records.length,
            itemBuilder: (context, index) {
              final record = _records[index];
              return _buildRecordItem(record);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecordItem(DownloadRecord record) {
    final isSelected = _selectedRecords.contains(record.id);
    
    // 判断文件是否存在
    bool fileExists = false;
    if (record.filename != null) {
      final file = File('${record.savePath}/${record.filename}');
      fileExists = file.existsSync();
    } else {
      final directory = Directory(record.savePath);
      fileExists = directory.existsSync();
    }
    
    // 构建缩略图
    Widget thumbnail;
    if (record.thumbnailUrl != null) {
      thumbnail = Image.network(
        record.thumbnailUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultThumbnail(record);
        },
      );
    } else {
      thumbnail = _buildDefaultThumbnail(record);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: _isSelectMode ? () => _toggleSelectRecord(record.id) : () => _openFolder(record),
        onLongPress: !_isSelectMode ? () {
          setState(() {
            _isSelectMode = true;
            _selectedRecords.add(record.id);
          });
        } : null,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 选择模式下显示复选框
              if (_isSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 16),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelectRecord(record.id),
                  ),
                ),
              
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: thumbnail,
              ),
              
              // 记录信息
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              record.albumName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isSelectMode)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'delete':
                                    _deleteRecord(record);
                                    break;
                                  case 'open':
                                    _openFolder(record);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Text('查看文件位置'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除记录'),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      Text(
                        record.filename != null 
                          ? '文件名: ${p.basename(record.filename!)}'
                          : '共下载${record.totalCount}个文件：成功${record.successCount}个${record.failedCount > 0 ? ', 失败${record.failedCount}个' : ''}${record.skippedCount > 0 ? ', 跳过${record.skippedCount}个' : ''}',
                        style: const TextStyle(fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 2),
                      
                      Row(
                        children: [
                          Icon(
                            fileExists ? Icons.check_circle : Icons.error,
                            size: 14,
                            color: fileExists ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fileExists ? record.statusText : '文件已删除',
                            style: TextStyle(
                              fontSize: 14,
                              color: fileExists ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 2),
                      
                      Text(
                        '下载时间: ${record.formattedDownloadTime}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      
                      if (record.targetUin.isNotEmpty && record.targetUin != "null")
                        Text(
                          '所属QQ: ${record.targetUin}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultThumbnail(DownloadRecord record) {
    return Container(
      width: 60,
      height: 60,
      color: Colors.grey[200],
      child: Icon(
        record.isVideo ? Icons.video_library : Icons.photo_library,
        color: Colors.grey,
        size: 30,
      ),
    );
  }
} 