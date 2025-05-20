import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class FileViewerScreen extends StatefulWidget {
  final String title;
  final List<String> files;
  final int initialIndex;

  const FileViewerScreen({
    super.key,
    required this.title,
    required this.files,
    this.initialIndex = 0,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadFileAtIndex(widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  void _disposeVideoController() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  Future<void> _loadFileAtIndex(int index) async {
    if (index < 0 || index >= widget.files.length) return;

    final filePath = widget.files[index];
    final extension = p.extension(filePath).toLowerCase();

    // 如果是视频文件，初始化视频播放器
    if (extension == '.mp4' || extension == '.mov') {
      setState(() {
        _isVideoLoading = true;
      });

      // 先释放之前的控制器
      _disposeVideoController();

      try {
        // 确保文件存在
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('视频文件不存在');
        }

        // 检查文件大小
        final fileSize = await file.length();
        if (fileSize < 1024) {
          // 小于1KB的文件可能不是有效视频
          throw Exception('视频文件无效或损坏');
        }

        // 检查文件头部，判断是否为图片而不是视频
        final bytes = await file.openRead(0, 12).toList();
        if (bytes.isNotEmpty) {
          final firstBytes = bytes.first;

          // 检查是否为JPEG文件头 (FF D8 FF)
          bool isJpeg = firstBytes.length >= 3 &&
              firstBytes[0] == 0xFF &&
              firstBytes[1] == 0xD8 &&
              firstBytes[2] == 0xFF;

          // 检查是否为PNG文件头 (89 50 4E 47)
          bool isPng = firstBytes.length >= 4 &&
              firstBytes[0] == 0x89 &&
              firstBytes[1] == 0x50 &&
              firstBytes[2] == 0x4E &&
              firstBytes[3] == 0x47;

          if (isJpeg || isPng) {
            // 如果是图片文件但扩展名是视频，尝试重命名
            if (filePath.toLowerCase().endsWith('.mp4') ||
                filePath.toLowerCase().endsWith('.mov')) {
              // 创建新的文件名
              String newFilePath;
              if (isJpeg) {
                newFilePath =
                    '${filePath.substring(0, filePath.lastIndexOf('.'))}.jpg';
              } else {
                newFilePath =
                    '${filePath.substring(0, filePath.lastIndexOf('.'))}.png';
              }

              try {
                // 复制文件而不是重命名，以保留原始文件
                await file.copy(newFilePath);

                // 更新widget.files列表中的文件路径
                for (int i = 0; i < widget.files.length; i++) {
                  if (widget.files[i] == filePath) {
                    widget.files[i] = newFilePath;
                    break;
                  }
                }

                // 显示提示
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('检测到视频文件实际是图片，已自动转换为图片文件')),
                  );
                }

                // 重新加载为图片
                setState(() {
                  _currentIndex = _currentIndex;
                });

                return;
              } catch (e) {
                if (kDebugMode) {
                  print('重命名文件失败: $e');
                }
              }
            }

            throw Exception('此文件是图片而不是视频，请使用图片查看器打开');
          }
        }

        // 创建视频控制器
        _videoController = VideoPlayerController.file(file);
        await _videoController!.initialize();

        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          aspectRatio: _videoController!.value.aspectRatio,
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Text(
                '视频加载失败: $errorMessage',
                style: const TextStyle(color: Colors.white),
              ),
            );
          },
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频加载失败: $e')),
          );
        }
      }

      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareCurrentFile(),
            tooltip: '分享',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 文件查看器
          PageView.builder(
            controller: _pageController,
            itemCount: widget.files.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _loadFileAtIndex(index);
            },
            itemBuilder: (context, index) {
              final filePath = widget.files[index];
              final extension = p.extension(filePath).toLowerCase();

              // 根据文件类型显示不同的查看器
              if (extension == '.mp4' || extension == '.mov') {
                // 视频文件
                if (_isVideoLoading) {
                  return const Center(child: FProgress());
                }

                if (_chewieController != null) {
                  return Center(
                    child: Chewie(controller: _chewieController!),
                  );
                } else {
                  // 视频加载失败，尝试作为图片加载
                  return Stack(
                    children: [
                      // 尝试作为图片加载
                      PhotoView(
                        imageProvider: FileImage(File(filePath)),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 2,
                        backgroundDecoration: const BoxDecoration(
                          color: Colors.black,
                        ),
                        loadingBuilder: (context, event) => const Center(
                          child: FProgress(),
                        ),
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Text('视频加载失败，且无法作为图片显示'),
                        ),
                      ),
                      // 显示提示信息
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  Colors.red.withAlpha(204), // 0.8 * 255 = 204
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '视频加载失败，正在尝试作为图片显示',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              } else {
                // 图片文件
                return PhotoView(
                  imageProvider: FileImage(File(filePath)),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.black,
                  ),
                  loadingBuilder: (context, event) => const Center(
                    child: FProgress(),
                  ),
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text('图片加载失败: $error'),
                  ),
                );
              }
            },
          ),

          // 底部指示器
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.files.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _shareCurrentFile() {
    if (_currentIndex >= 0 && _currentIndex < widget.files.length) {
      final filePath = widget.files[_currentIndex];
      // 实现分享功能
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享功能尚未实现: $filePath')),
      );
    }
  }
}
