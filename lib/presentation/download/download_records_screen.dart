
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';

class DownloadRecordsScreen extends ConsumerStatefulWidget {
  const DownloadRecordsScreen({super.key});

  @override
  ConsumerState<DownloadRecordsScreen> createState() => _DownloadRecordsScreenState();
}

class _DownloadRecordsScreenState extends ConsumerState<DownloadRecordsScreen> {
  List<DownloadRecord> _records = [];
  List<DownloadRecord> _activeDownloads = [];
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
      final activeDownloads = await recordService.getActiveDownloads();

      setState(() {
        _records = records.where((r) => r.isComplete).toList(); // 只显示已完成的下载
        _activeDownloads = activeDownloads; // 活跃下载单独存储
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

  // 取消下载
  Future<void> _cancelDownload(DownloadRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => FDialog(
        title: const Text('确认取消'),
        body: Text('确定要取消"${record.albumName}"的下载吗？'),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('继续下载'),
          ),
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final downloadManager = ref.read(downloadManagerProvider.notifier);
        await downloadManager.cancelDownload(record.id);
        
        // 刷新列表
        await _loadRecords();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已取消"${record.albumName}"的下载')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('取消下载失败: $e')),
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
              icon: const Icon(Icons.select_all),
              onPressed: _toggleSelectAll,
              tooltip: '全选/取消全选',
            ),
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedRecords.isNotEmpty ? _deleteSelectedRecords : null,
              tooltip: '删除所选',
            ),
          IconButton(
            icon: Icon(_isSelectMode ? Icons.cancel : Icons.checklist),
            onPressed: _toggleSelectMode,
            tooltip: _isSelectMode ? '取消选择' : '多选',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  _clearAllRecords();
                  break;
                case 'cleanup':
                  _cleanupInvalidRecords();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空所有记录'),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: Text('清理无效记录'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: _isLoading
            ? const Center(child: FProgress())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_activeDownloads.isNotEmpty) ...[
                        const Text(
                          '正在下载',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildActiveDownloadCards(),
                        const SizedBox(height: 24),
                      ],
                      if (_records.isEmpty && _activeDownloads.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text('暂无下载记录'),
                          ),
                        )
                      else if (_records.isNotEmpty) ...[
                        const Text(
                          '已完成下载',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._buildCompletedDownloadCards(),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // 创建活跃下载卡片
  List<Widget> _buildActiveDownloadCards() {
    return _activeDownloads.map((record) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: FCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.downloading, color: Colors.white),
                ),
                title: Text(record.albumName),
                subtitle: Text('总数: ${record.totalCount} 下载中: ${record.currentProgress}/${record.totalCount}'),
                trailing: IconButton(
                  icon: const Icon(Icons.cancel),
                  onPressed: () => _cancelDownload(record),
                  tooltip: '取消下载',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: record.progressPercentage,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${(record.progressPercentage * 100).toStringAsFixed(1)}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(record.currentMessage),
                    Text('开始时间: ${record.formattedDownloadTime}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // 创建完成下载卡片
  List<Widget> _buildCompletedDownloadCards() {
    return _records.map((record) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: FCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSelectMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectedRecords.contains(record.id),
                        onChanged: (value) {
                          if (value == true) {
                            _toggleSelectRecord(record.id);
                          } else {
                            _toggleSelectRecord(record.id);
                          }
                        },
                      ),
                      const Text('选择'),
                    ],
                  ),
                ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: record.statusText == '下载完成'
                      ? Colors.green
                      : (record.statusText == '部分完成' ? Colors.amber : Colors.red),
                  child: Icon(
                    record.statusText == '下载完成'
                        ? Icons.check
                        : (record.statusText == '部分完成' ? Icons.warning : Icons.error),
                    color: Colors.white,
                  ),
                ),
                title: Text(record.albumName),
                subtitle: Text(
                    '总数: ${record.totalCount}, 成功: ${record.successCount}, 失败: ${record.failedCount}, 跳过: ${record.skippedCount}'),
                trailing: !_isSelectMode
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteRecord(record),
                        tooltip: '删除记录',
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('状态: ${record.statusText}'),
                    Text('下载时间: ${record.formattedDownloadTime}'),
                    Text('保存位置: ${record.savePath}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
} 