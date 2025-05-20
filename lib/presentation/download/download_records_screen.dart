import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';  // 导入 Clipboard 和 ClipboardData
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;
import 'package:qq_zone_flutter_downloader/core/models/download_record.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/presentation/download/file_list_viewer_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

class DownloadRecordsScreen extends ConsumerStatefulWidget {
  const DownloadRecordsScreen({super.key});

  @override
  ConsumerState<DownloadRecordsScreen> createState() =>
      _DownloadRecordsScreenState();
}

class _DownloadRecordsScreenState extends ConsumerState<DownloadRecordsScreen> {
  List<DownloadRecord> _records = [];
  List<DownloadRecord> _activeDownloads = [];
  bool _isLoading = true;
  bool _isSelectMode = false;
  Set<String> _selectedRecords = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRecords().then((_) {
      // 初始加载完成后，只有在有活跃下载时才启动定时器
      _startTimerIfNeeded();
    });
  }

  // 根据是否有活跃下载来启动或停止定时器
  void _startTimerIfNeeded() {
    if (_activeDownloads.isNotEmpty) {
      // 有活跃下载，启动定时器（如果尚未启动）
      if (_refreshTimer == null || !_refreshTimer!.isActive) {
        _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (mounted) {
            _loadRecords();
            if (kDebugMode) {
              print("[DownloadRecords] 自动刷新下载记录");
            }
          }
        });
        if (kDebugMode) {
          print("[DownloadRecords] 启动自动刷新定时器");
        }
      }
    } else {
      // 没有活跃下载，停止定时器
      if (_refreshTimer != null && _refreshTimer!.isActive) {
        _refreshTimer!.cancel();
        _refreshTimer = null;
        if (kDebugMode) {
          print("[DownloadRecords] 停止自动刷新定时器");
        }
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    // 如果是自动刷新（定时器触发），不显示加载状态
    bool isAutoRefresh =
        _refreshTimer != null && _refreshTimer!.isActive && !_isLoading;

    if (!isAutoRefresh) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final recordService = ref.read(downloadRecordServiceProvider);

      // 强制重新初始化记录服务，确保从磁盘读取最新数据
      await recordService.initialize(forceReload: true);

      // 获取完整的记录列表和活跃下载
      final records = await recordService.getAllRecords();
      final activeDownloads = await recordService.getActiveDownloads();

      if (mounted) {
        setState(() {
          _records = records.where((r) => r.isComplete).toList(); // 只显示已完成的下载
          _activeDownloads = activeDownloads; // 活跃下载单独存储
          if (!isAutoRefresh) {
            _isLoading = false;
          }
        });

        // 根据活跃下载状态管理定时器
        _startTimerIfNeeded();
      }
    } catch (e) {
      if (!isAutoRefresh && mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载下载记录失败: $e')),
        );
      }

      if (kDebugMode) {
        print("[DownloadRecords] 加载记录失败: $e");
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

    // 显示确认对话框，提供删除文件选项
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        bool deleteFiles = false;

        return StatefulBuilder(
          builder: (context, setState) => FDialog(
            title: const Text('确认删除'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定要删除所选的 ${_selectedRecords.length} 条下载记录吗？'),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Checkbox(
                        value: deleteFiles,
                        onChanged: (value) {
                          setState(() {
                            deleteFiles = value ?? false;
                          });
                        },
                      ),
                      const Text('同时删除已下载的文件'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () => Navigator.of(context).pop({
                  'confirmed': true,
                  'deleteFiles': deleteFiles,
                }),
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['confirmed'] == true && mounted) {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => FDialog(
          title: const Text('正在删除'),
          body: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 16),
              Center(child: FProgress()),
              SizedBox(height: 16),
              Text('正在删除文件，请稍候...'),
            ],
          ),
          actions: [
            // 不提供任何按钮，强制用户等待
          ],
        ),
      );

      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        final bool deleteFiles = result['deleteFiles'] ?? false;

        await recordService.deleteRecords(_selectedRecords.toList(),
            deleteFiles: deleteFiles);

        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 刷新列表
        await _loadRecords();

        // 退出选择模式
        setState(() {
          _isSelectMode = false;
          _selectedRecords.clear();
        });

        if (mounted) {
          String message = '已删除所选记录';
          if (deleteFiles) {
            message += '及相关文件';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e) {
        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除记录失败: $e')),
          );
        }
      }
    }
  }

  // 删除单个记录
  Future<void> _deleteRecord(DownloadRecord record) async {
    // 显示确认对话框，提供删除文件选项
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        bool deleteFiles = false;

        return StatefulBuilder(
          builder: (context, setState) => FDialog(
            title: const Text('确认删除'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定要删除"${record.albumName}"的下载记录吗？'),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Checkbox(
                        value: deleteFiles,
                        onChanged: (value) {
                          setState(() {
                            deleteFiles = value ?? false;
                          });
                        },
                      ),
                      const Text('同时删除已下载的文件'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () => Navigator.of(context).pop({
                  'confirmed': true,
                  'deleteFiles': deleteFiles,
                }),
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['confirmed'] == true && mounted) {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => FDialog(
          title: const Text('正在删除'),
          body: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 16),
              Center(child: FProgress()),
              SizedBox(height: 16),
              Text('正在删除文件，请稍候...'),
            ],
          ),
          actions: [
            // 不提供任何按钮，强制用户等待
          ],
        ),
      );

      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        final bool deleteFiles = result['deleteFiles'] ?? false;

        await recordService.deleteRecord(record.id, deleteFiles: deleteFiles);

        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 刷新列表
        await _loadRecords();

        if (mounted) {
          String message = '已删除"${record.albumName}"的下载记录';
          if (deleteFiles) {
            message += '及相关文件';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e) {
        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();

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

    // 显示确认对话框，提供删除文件选项
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        bool deleteFiles = false;

        return StatefulBuilder(
          builder: (context, setState) => FDialog(
            title: const Text('清空所有记录'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('确定要清空所有下载记录吗？'),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Checkbox(
                        value: deleteFiles,
                        onChanged: (value) {
                          setState(() {
                            deleteFiles = value ?? false;
                          });
                        },
                      ),
                      const Text('同时删除所有已下载的文件'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              FButton(
                onPress: () => Navigator.of(context).pop({
                  'confirmed': true,
                  'deleteFiles': deleteFiles,
                }),
                child: const Text('确认清空'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['confirmed'] == true && mounted) {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => FDialog(
          title: const Text('正在清空记录'),
          body: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 16),
              Center(child: FProgress()),
              SizedBox(height: 16),
              Text('正在删除文件，请稍候...'),
            ],
          ),
          actions: [
            // 不提供任何按钮，强制用户等待
          ],
        ),
      );

      try {
        final recordService = ref.read(downloadRecordServiceProvider);
        final bool deleteFiles = result['deleteFiles'] ?? false;

        await recordService.clearAllRecords(deleteFiles: deleteFiles);

        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 刷新列表
        await _loadRecords();

        // 退出选择模式
        setState(() {
          _isSelectMode = false;
          _selectedRecords.clear();
        });

        if (mounted) {
          String message = '已清空所有下载记录';
          if (deleteFiles) {
            message += '及相关文件';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e) {
        // 关闭加载对话框
        if (mounted) {
          Navigator.of(context).pop();

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
    // 监听下载管理器状态变化
    ref.listen(downloadManagerProvider, (previous, next) {
      // 当下载管理器状态变化时，刷新活跃下载列表
      if (previous?.activeDownloads.length != next.activeDownloads.length ||
          previous?.activeDownloads.keys.toString() !=
              next.activeDownloads.keys.toString()) {
        if (kDebugMode) {
          print("[DownloadRecords] 下载管理器状态变化，刷新活跃下载列表");
        }
        _loadRecords();

        // 如果活跃下载数量从有到无或从无到有，需要管理定时器
        if ((previous?.activeDownloads.isEmpty ?? true) && next.activeDownloads.isNotEmpty) {
          // 从无到有，确保定时器启动
          if (kDebugMode) {
            print("[DownloadRecords] 检测到新的活跃下载，确保定时器启动");
          }
          _startTimerIfNeeded();
        } else if ((previous?.activeDownloads.isNotEmpty ?? false) && next.activeDownloads.isEmpty) {
          // 从有到无，停止定时器
          if (kDebugMode) {
            print("[DownloadRecords] 检测到活跃下载已全部完成，停止定时器");
          }
          _startTimerIfNeeded();
        }
      }
    });

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
              onPressed:
                  _selectedRecords.isNotEmpty ? _deleteSelectedRecords : null,
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
                subtitle: Text(
                    '总数: ${record.totalCount} 下载中: ${record.currentProgress}/${record.totalCount}'),
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                            '${(record.progressPercentage * 100).toStringAsFixed(1)}%'),
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

  // 打开文件夹
  Future<void> _openFolder(DownloadRecord record) async {
    try {
      final String folderPath;
      if (record.filename != null) {
        // 单个文件下载，打开文件所在目录
        folderPath = record.savePath;
      } else {
        // 相册下载，打开相册目录
        folderPath = '${record.savePath}/${record.albumName}';
      }

      // 检查文件夹是否存在
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文件夹不存在: $folderPath')),
          );
        }
        return;
      }

      // 根据平台使用不同的打开方式
      bool result;
      if (Platform.isWindows) {
        // Windows 平台使用 explorer.exe 打开文件夹
        final process = await Process.run('explorer.exe', [folderPath]);
        result = process.exitCode == 0;

        if (kDebugMode) {
          print("[OpenFolder] Windows 打开文件夹: $folderPath, 结果: $result");
          if (process.exitCode != 0) {
            print("[OpenFolder] 错误: ${process.stderr}");
          }
        }
      } else if (Platform.isAndroid) {
        // Android 平台使用原生 Intent API 打开文件夹
        try {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          final sdkInt = androidInfo.version.sdkInt;

          if (kDebugMode) {
            print("[OpenFolder] Android SDK 版本: $sdkInt");
            print("[OpenFolder] 尝试打开文件夹: $folderPath");
          }

          // 尝试方法1: 使用文件管理器直接打开文件夹
          // 这种方法在大多数Android设备上应该能工作
          String normalizedPath = folderPath;

          // 确保路径格式正确
          if (folderPath.startsWith('/storage/emulated/0/')) {
            // 转换为更通用的路径格式
            normalizedPath = folderPath.replaceFirst('/storage/emulated/0/', '/sdcard/');
          }

          if (kDebugMode) {
            print("[OpenFolder] 规范化路径: $normalizedPath");
          }

          // 尝试使用文件管理器打开
          final intent = AndroidIntent(
            action: 'android.intent.action.VIEW',
            data: 'file://$normalizedPath',
            flags: <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
          );

          await intent.launch();
          result = true;

          if (kDebugMode) {
            print("[OpenFolder] 使用文件管理器打开文件夹: $normalizedPath");
          }
        } catch (e) {
          // 如果第一种方法失败，尝试使用其他文件管理器
          if (kDebugMode) {
            print("[OpenFolder] 第一种方法失败: $e，尝试使用其他文件管理器");
          }

          try {
            // 尝试方法2: 使用ES文件浏览器(如果已安装)
            final esIntent = AndroidIntent(
              action: 'android.intent.action.VIEW',
              package: 'com.estrongs.android.pop',
              componentName: 'com.estrongs.android.pop.view.FileExplorerActivity',
              data: 'file://$folderPath',
              flags: <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
            );

            await esIntent.launch();
            result = true;

            if (kDebugMode) {
              print("[OpenFolder] 使用ES文件浏览器打开文件夹");
            }
          } catch (e2) {
            // 如果ES文件浏览器不可用，尝试使用系统文件管理器
            if (kDebugMode) {
              print("[OpenFolder] ES文件浏览器不可用: $e2，尝试使用系统文件管理器");
            }

            try {
              // 尝试方法3: 使用系统文件管理器
              final documentIntent = AndroidIntent(
                action: 'android.intent.action.VIEW',
                type: 'resource/folder',
                data: 'content://com.android.externalstorage.documents/document/primary:${folderPath.replaceAll('/storage/emulated/0/', '')}',
                flags: <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
              );

              await documentIntent.launch();
              result = true;

              if (kDebugMode) {
                print("[OpenFolder] 使用系统文件管理器打开文件夹");
              }
            } catch (e3) {
              // 如果所有方法都失败，显示一个对话框，让用户手动导航
              if (kDebugMode) {
                print("[OpenFolder] 所有方法都失败: $e3，显示路径信息");
              }

              // 打开默认文件管理器
              result = await launchUrl(
                Uri.parse('content://com.android.externalstorage.documents/root/primary'),
                mode: LaunchMode.externalApplication,
              );

              // 显示路径信息，帮助用户手动导航
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('请手动导航到以下路径: $folderPath'),
                    duration: const Duration(seconds: 10),
                    action: SnackBarAction(
                      label: '复制路径',
                      onPressed: () {
                        // 复制路径到剪贴板
                        Clipboard.setData(ClipboardData(text: folderPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('路径已复制到剪贴板')),
                        );
                      },
                    ),
                  ),
                );
              }
            }
          }
        }
      } else {
        // iOS 和其他平台
        result = await launchUrl(
          Uri.directory(folderPath),
          mode: LaunchMode.externalApplication,
        );
      }

      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件夹: $folderPath')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print("[OpenFolder] 打开文件夹失败: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件夹失败: $e')),
        );
      }
    }
  }

  // 查看文件
  Future<void> _viewFiles(DownloadRecord record) async {
    try {
      final String path;
      final List<FileSystemEntity> files = [];

      if (record.filename != null) {
        // 单个文件下载
        path = '${record.savePath}/${record.filename}';
        final file = File(path);
        if (await file.exists()) {
          files.add(file);
        }
      } else {
        // 相册下载，获取所有文件
        path = '${record.savePath}/${record.albumName}';
        final directory = Directory(path);
        if (await directory.exists()) {
          files.addAll(await directory
              .list()
              .where((entity) => entity is File)
              .toList());
        }
      }

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有找到文件')),
          );
        }
        return;
      }

      // 过滤和排序文件
      final List<String> filePaths = files.map((e) => e.path).where((path) {
        // 只显示图片和视频文件
        final ext = p.extension(path).toLowerCase();
        return ext == '.jpg' ||
            ext == '.jpeg' ||
            ext == '.png' ||
            ext == '.gif' ||
            ext == '.mp4' ||
            ext == '.mov';
      }).toList();

      // 按文件名排序
      filePaths.sort();

      if (filePaths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有找到可显示的图片或视频文件')),
          );
        }
        return;
      }

      // 打开文件列表查看器
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FileListViewerScreen(
              title: record.albumName,
              files: filePaths,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('查看文件失败: $e')),
        );
      }
    }
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
                  child: Material(
                    color: Colors.transparent,
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
                ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: record.statusText == '下载完成'
                      ? Colors.green
                      : (record.statusText == '部分完成'
                          ? Colors.amber
                          : Colors.red),
                  child: Icon(
                    record.statusText == '下载完成'
                        ? Icons.check
                        : (record.statusText == '部分完成'
                            ? Icons.warning
                            : Icons.error),
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FButton(
                          style: FButtonStyle.outline,
                          onPress: () => _openFolder(record),
                          child: const Text('打开文件夹'),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          onPress: () => _viewFiles(record),
                          child: const Text('查看文件'),
                        ),
                      ],
                    ),
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
