import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qq_zone_flutter_downloader/presentation/download/file_viewer_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FileListViewerScreen extends StatefulWidget {
  final String title;
  final List<String> files;

  const FileListViewerScreen({
    super.key,
    required this.title,
    required this.files,
  });

  @override
  State<FileListViewerScreen> createState() => _FileListViewerScreenState();
}

class _FileListViewerScreenState extends State<FileListViewerScreen> {
  List<FileItem> _fileItems = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFileItems();
  }

  Future<void> _loadFileItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<FileItem> items = [];

      for (final filePath in widget.files) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            final fileName = p.basename(filePath);
            final extension = p.extension(filePath).toLowerCase();
            final isVideo = extension == '.mp4' || extension == '.mov';
            final isImage = extension == '.jpg' ||
                           extension == '.jpeg' ||
                           extension == '.png' ||
                           extension == '.gif';

            if (isImage || isVideo) {
              items.add(FileItem(
                path: filePath,
                name: fileName,
                size: stat.size,
                modified: stat.modified,
                isVideo: isVideo,
              ));
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[FileListViewer] 加载文件失败: $filePath, 错误: $e");
          }
        }
      }

      // 按修改时间排序（最新的在前面）
      items.sort((a, b) => b.modified.compareTo(a.modified));

      setState(() {
        _fileItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "加载文件列表失败: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // 打开文件夹按钮
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFolder,
            tooltip: '打开文件夹',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _loadFileItems,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: FProgress()),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 48)),
          const SizedBox(height: 16),
          Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          Center(
            child: FButton(
              onPress: _loadFileItems,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }

    if (_fileItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.4),
          const Center(
            child: Text('没有找到可显示的文件'),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _fileItems.length,
      itemBuilder: (context, index) {
        final item = _fileItems[index];
        return _buildFileItem(item, index);
      },
    );
  }

  Widget _buildFileItem(FileItem item, int index) {
    final formattedSize = _formatFileSize(item.size);
    final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(item.modified);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildThumbnail(item),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$formattedSize • $formattedDate',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _openFile(item.path),
              tooltip: '打开文件',
            ),
            IconButton(
              icon: const Icon(Icons.fullscreen),
              onPressed: () => _viewFileFullscreen(index),
              tooltip: '全屏查看',
            ),
          ],
        ),
        onTap: () => _viewFileFullscreen(index),
      ),
    );
  }

  Widget _buildThumbnail(FileItem item) {
    if (item.isVideo) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.play_circle_outline,
          color: Colors.white,
          size: 24,
        ),
      );
    } else {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
            image: FileImage(File(item.path)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
  }

  String _formatFileSize(int size) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double s = size.toDouble();
    while (s >= 1024 && i < suffixes.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _openFile(String filePath) async {
    try {
      bool result;

      if (Platform.isWindows) {
        // Windows 平台使用 Process.run 打开文件
        final process = await Process.run('explorer.exe', [filePath]);
        result = process.exitCode == 0;

        if (kDebugMode) {
          print("[FileListViewer] Windows 打开文件: $filePath, 结果: $result");
          if (process.exitCode != 0) {
            print("[FileListViewer] 错误: ${process.stderr}");
          }
        }
      } else {
        // 其他平台使用 launchUrl
        result = await launchUrl(
          Uri.file(filePath),
          mode: LaunchMode.externalApplication,
        );
      }

      if (!result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件: $filePath')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print("[FileListViewer] 打开文件失败: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件失败: $e')),
        );
      }
    }
  }

  // 打开文件所在的文件夹
  Future<void> _openFolder() async {
    try {
      if (_fileItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有可用的文件')),
          );
        }
        return;
      }

      // 获取第一个文件的路径，提取其所在的文件夹
      final String filePath = _fileItems.first.path;
      final String folderPath = p.dirname(filePath);

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

      bool result;

      if (Platform.isWindows) {
        // Windows 平台使用 explorer.exe 打开文件夹
        final process = await Process.run('explorer.exe', [folderPath]);
        result = process.exitCode == 0;

        if (kDebugMode) {
          print("[FileListViewer] Windows 打开文件夹: $folderPath, 结果: $result");
          if (process.exitCode != 0) {
            print("[FileListViewer] 错误: ${process.stderr}");
          }
        }
      } else if (Platform.isAndroid) {
        // Android 平台使用特殊的 Intent 打开文件夹
        // 注意：Android 上打开文件夹的支持有限，可能在某些设备上不工作
        try {
          // 尝试使用 Storage Access Framework 打开文件夹
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          final sdkInt = androidInfo.version.sdkInt;

          if (kDebugMode) {
            print("[FileListViewer] Android SDK 版本: $sdkInt");
            print("[FileListViewer] 尝试打开文件夹: $folderPath");
          }

          // 对于 Android 10+ (API 29+)，我们需要使用 content:// URI
          if (sdkInt >= 29) {
            // 尝试使用系统文件管理器打开
            result = await launchUrl(
              Uri.parse('content://com.android.externalstorage.documents/document/primary:${folderPath.replaceAll('/storage/emulated/0/', '')}'),
              mode: LaunchMode.externalApplication,
            );
          } else {
            // 对于旧版本 Android，尝试直接使用 file:// URI
            result = await launchUrl(
              Uri.directory(folderPath),
              mode: LaunchMode.externalApplication,
            );
          }
        } catch (e) {
          // 如果上面的方法失败，尝试使用通用的文件管理器 Intent
          if (kDebugMode) {
            print("[FileListViewer] 第一种方法打开文件夹失败: $e，尝试备用方法");
          }

          // 尝试使用通用的文件管理器 Intent
          result = await launchUrl(
            Uri.parse('content://com.android.externalstorage.documents/root/primary'),
            mode: LaunchMode.externalApplication,
          );
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
        print("[FileListViewer] 打开文件夹失败: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件夹失败: $e')),
        );
      }
    }
  }

  void _viewFileFullscreen(int index) {
    final filePaths = _fileItems.map((item) => item.path).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileViewerScreen(
          title: widget.title,
          files: filePaths,
          initialIndex: index,
        ),
      ),
    );
  }
}

class FileItem {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final bool isVideo;

  FileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.isVideo,
  });
}
