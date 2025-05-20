import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/models/album.dart';
import 'package:qq_zone_flutter_downloader/core/models/photo.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/core/providers/download_manager_provider.dart'; // 导入下载管理器
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:qq_zone_flutter_downloader/core/providers/qzone_image_provider.dart';
import 'package:qq_zone_flutter_downloader/presentation/download/download_records_screen.dart';

// 获取保存照片的目录
Future<String> _getPhotoSaveDirectory() async {
  if (Platform.isAndroid) {
    try {
      // 获取Android版本
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Android 10及以上，优先使用Pictures目录
      if (sdkInt >= 29) {
        try {
          // 使用Pictures目录
          final directories = await getExternalStorageDirectories(
              type: StorageDirectory.pictures);
          if (directories != null && directories.isNotEmpty) {
            // 这个路径通常会是类似 /storage/emulated/0/Android/data/packagename/files/Pictures
            // 我们需要提取根路径，然后构建正确的Pictures路径
            String path = directories.first.path;
            List<String> segments = path.split('/');
            int androidIndex = segments.indexOf('Android');

            if (androidIndex > 0) {
              // 构建到根的路径 (如 /storage/emulated/0)
              String rootPath = segments.sublist(0, androidIndex).join('/');
              // 构建Pictures/qq_zone_downloader路径
              final picturesPath =
                  Directory('$rootPath/Pictures/qq_zone_downloader');

              if (!await picturesPath.exists()) {
                await picturesPath.create(recursive: true);
              }

              if (kDebugMode) {
                print("[AlbumDetails] 使用Pictures目录: ${picturesPath.path}");
              }

              return picturesPath.path;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[AlbumDetails] 获取Pictures目录失败: $e");
          }
        }
      }

      // 对于旧版本Android，直接构建Pictures路径
      try {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          String path = directory.path;
          List<String> segments = path.split('/');
          int androidIndex = segments.indexOf('Android');

          if (androidIndex > 0) {
            // 构建从根到Android前的路径 (如 /storage/emulated/0)
            String rootPath = segments.sublist(0, androidIndex).join('/');

            // 创建Pictures/qq_zone_downloader路径
            final picturesPath =
                Directory('$rootPath/Pictures/qq_zone_downloader');
            try {
              if (!await picturesPath.exists()) {
                await picturesPath.create(recursive: true);
              }
              if (kDebugMode) {
                print("[AlbumDetails] 使用传统Pictures目录: ${picturesPath.path}");
              }
              return picturesPath.path;
            } catch (e) {
              if (kDebugMode) {
                print("[AlbumDetails] 创建传统Pictures目录失败: $e");
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print("[AlbumDetails] 获取传统存储路径失败: $e");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[AlbumDetails] 获取Android版本信息失败: $e");
      }
    }
  } else if (Platform.isIOS) {
    // iOS系统使用照片库
    try {
      final directory = await getApplicationDocumentsDirectory();
      final iosPath = Directory('${directory.path}/qq_zone_downloader');
      if (!await iosPath.exists()) {
        await iosPath.create(recursive: true);
      }
      return iosPath.path;
    } catch (e) {
      if (kDebugMode) {
        print("[AlbumDetails] 创建iOS存储目录失败: $e");
      }
    }
  }

  // 所有方法都失败后，退回到应用文档目录
  try {
    final directory = await getApplicationDocumentsDirectory();
    final fallbackPath = Directory('${directory.path}/qq_zone_downloader');
    if (!await fallbackPath.exists()) {
      await fallbackPath.create(recursive: true);
    }
    if (kDebugMode) {
      print("[AlbumDetails] 使用应用文档目录作为备选: ${fallbackPath.path}");
    }
    return fallbackPath.path;
  } catch (e) {
    if (kDebugMode) {
      print("[AlbumDetails] 创建备选存储目录失败: $e");
    }

    // 最后的备选方案
    return Directory.systemTemp.path;
  }
}

class AlbumDetailsScreen extends ConsumerStatefulWidget {
  final Album album;
  final String? targetUin; // 添加目标用户参数

  const AlbumDetailsScreen({
    super.key,
    required this.album,
    this.targetUin,
  });

  @override
  ConsumerState<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends ConsumerState<AlbumDetailsScreen> {
  bool _isLoading = false;
  bool _isLoadingMore = false;
  List<Photo> _photos = [];
  String? _errorMessage;
  int _pageStart = 0;
  final int _pageSize = 30;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  // 下载状态
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMorePhotos();
    }
  }

  Future<void> _loadPhotos() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pageStart = 0;
      _hasMore = true;
    });

    try {
      final qzoneService = ref.read(qZoneServiceProvider);

      final photos = await qzoneService.getPhotoList(
        albumId: widget.album.id,
        targetUin: widget.targetUin,
      );

      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false;
          _pageStart = _pageSize;
          _hasMore = photos.length >= _pageSize &&
              photos.length < widget.album.photoCount;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("[AlbumDetails] 加载照片失败: $e");
      }

      // 错误可能包含"对不起，回答错误"或"code: -10805"，尝试备用加载方法
      try {
        final qzoneService = ref.read(qZoneServiceProvider);

        if (kDebugMode) {
          print("[AlbumDetails] 尝试直接下载相册获取照片...");
        }

        // 直接使用下载方法，而不是反射调用私有方法
        final tempDir = await getTemporaryDirectory();

        // 这里是为了获取照片列表，所以即使相册已下载过也要继续
        // 使用 try-catch 捕获可能的 AlbumAlreadyDownloadedException 异常
        Map<String, dynamic> result;
        try {
          result = await qzoneService.downloadAlbum(
            album: widget.album,
            savePath: tempDir.path,
            targetUin: widget.targetUin,
            skipExisting: true,
          );
        } catch (downloadError) {
          // 如果是相册已下载的异常，我们可以忽略，因为这里只是为了获取照片列表
          if (kDebugMode) {
            print("[AlbumDetails] 下载相册时出现异常，但我们将继续尝试获取照片列表: $downloadError");
          }

          // 创建一个空结果，表示没有成功下载任何照片
          result = {
            'success': 0,
            'failed': 0,
            'skipped': 0,
            'total': 0,
          };
        }

        if (result['success'] > 0 && mounted) {
          // 重新加载照片列表
          final photos = await qzoneService.getPhotoList(
            albumId: widget.album.id,
            targetUin: widget.targetUin,
          );

          if (photos.isNotEmpty && mounted) {
            setState(() {
              _photos = photos;
              _isLoading = false;
              _pageStart = _pageSize;
              _hasMore = photos.length >= _pageSize &&
                  photos.length < widget.album.photoCount;
            });
            return;
          }
        }
      } catch (backupError) {
        if (kDebugMode) {
          print("[AlbumDetails] 备用方法也失败: $backupError");
        }
      }

      if (mounted) {
        // 检查错误是否包含"对不起，回答错误"或"code: -10805"，这表示这是一个加密相册
        final String errorStr = e.toString().toLowerCase();
        final bool isEncryptedAlbumError = errorStr.contains("回答错误") ||
            errorStr.contains("code: -10805") ||
            errorStr.contains("访问权限");

        setState(() {
          if (isEncryptedAlbumError) {
            _errorMessage = "这是一个加密相册，无法查看相册内容，但可以尝试下载。";
          } else {
            _errorMessage = "加载照片失败: ${e.toString()}";
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final qzoneService = ref.read(qZoneServiceProvider);

      if (kDebugMode) {
        print(
            "[AlbumDetails] 加载更多照片，当前页码: $_pageStart，当前照片数: ${_photos.length}");
      }

      if (_photos.length >= widget.album.photoCount) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
        return;
      }

      final morePhotos = await qzoneService.getPhotoList(
        albumId: widget.album.id,
        pageStart: _pageStart, // 使用当前的页码作为起始位置
        targetUin: widget.targetUin,
      );

      if (mounted) {
        // 过滤掉已有的照片
        final newPhotos = morePhotos
            .where((newPhoto) => !_photos
                .any((existingPhoto) => existingPhoto.id == newPhoto.id))
            .toList();

        if (kDebugMode) {
          print("[AlbumDetails] 获取到新照片: ${newPhotos.length}张");
        }

        if (newPhotos.isNotEmpty) {
          setState(() {
            _photos.addAll(newPhotos);
            _pageStart += _pageSize;
            _hasMore = _photos.length < widget.album.photoCount;
          });
        } else {
          // 如果没有新照片，就认为已经全部加载完成
          setState(() {
            _hasMore = false;
          });
        }

        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("[AlbumDetails] 加载更多照片失败: $e");
      }

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });

        // 显示一个简短的提示，但不阻止用户继续浏览已加载的照片
        showDialog(
          context: context,
          builder: (context) => FDialog(
            title: const Text('加载更多照片失败'),
            body: Text(e.toString()),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: _loadMorePhotos,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _openGallery(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoGalleryScreen(
          photos: _photos,
          initialIndex: index,
          album: widget.album,
          targetUin: widget.targetUin,
        ),
      ),
    );
  }

  void _showPermissionDeniedDialog(int sdkInt) {
    String message = "下载需要存储权限。\n请在系统设置中授予该权限。";
    if (sdkInt >= 30) {
      // Android 11+
      message = "下载需要\"所有文件访问\"权限。\n请在系统设置中为此应用开启该权限。";
    }

    showDialog(
      context: context,
      builder: (context) => FDialog(
        title: const Text('权限不足'),
        body: Text(message),
        actions: [
          FButton(
            style: FButtonStyle.outline,
            onPress: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FButton(
            onPress: () {
              openAppSettings(); // permission_handler提供的函数
              Navigator.of(context).pop();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAlbum({bool forceDownload = false}) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadMessage = '准备下载...';
    });

    try {
      // 检查存储权限
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        bool permissionOk = false;

        if (sdkInt >= 30) {
          // Android 11+
          if (await Permission.manageExternalStorage.isGranted) {
            permissionOk = true;
          }
        } else {
          // Android 10 及以下
          if (await Permission.storage.isGranted) {
            permissionOk = true;
          } else {
            // 对于旧版本，如果权限尚未授予，则尝试再次请求
            if (await Permission.storage.request().isGranted) {
              permissionOk = true;
            }
          }
        }

        if (!permissionOk) {
          if (mounted) {
            _showPermissionDeniedDialog(sdkInt);
          }
          throw Exception(
              '存储权限未授予。请检查应用权限设置。 (${sdkInt >= 30 ? '需要MANAGE_EXTERNAL_STORAGE' : '需要STORAGE'})');
        }
      }

      // 获取保存路径
      final savePath = await _getPhotoSaveDirectory();

      // 使用下载管理器开始下载
      final downloadManager = ref.read(downloadManagerProvider.notifier);

      try {
        await downloadManager.downloadAlbum(
          album: widget.album,
          savePath: savePath,
          targetUin: widget.targetUin,
          skipExisting: true,
          forceDownload: forceDownload,
        );

        // 立即更新UI状态，不等待下载完成
        if (mounted) {
          setState(() {
            _isDownloading = false;
          });

          // 显示开始下载的通知
          showDialog(
            context: context,
            builder: (context) => FDialog(
              title: const Text('下载开始'),
              body: Text('已开始下载"${widget.album.name}"，可在下载记录中查看进度'),
              actions: [
                FButton(
                  style: FButtonStyle.outline,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                FButton(
                  onPress: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DownloadRecordsScreen(),
                      ),
                    );
                  },
                  child: const Text('查看'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        // 检查是否是相册已下载的异常
        if (e is AlbumAlreadyDownloadedException && mounted) {
          setState(() {
            _isDownloading = false;
          });

          // 显示确认对话框，询问是否重新下载
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => FDialog(
              title: const Text('相册已下载'),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('相册"${widget.album.name}"已经下载过。'),
                  const SizedBox(height: 8),
                  Text(
                    '下载时间: ${e.existingRecord.formattedDownloadTime}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '状态: ${e.existingRecord.statusText}',
                    style: TextStyle(
                      fontSize: 12,
                      color: e.existingRecord.statusText == '下载完成'
                          ? Colors.green
                          : Colors.orange
                    ),
                  ),
                  Text(
                    '保存位置: ${e.existingRecord.savePath}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                FButton(
                  style: FButtonStyle.outline,
                  onPress: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FButton(
                  onPress: () => Navigator.of(context).pop(true),
                  child: const Text('重新下载'),
                ),
              ],
            ),
          );

          // 如果用户选择重新下载
          if (result == true) {
            // 递归调用，但设置强制下载标志
            return _downloadAlbum(forceDownload: true);
          }

          return; // 用户取消，直接返回
        } else {
          // 其他异常，继续抛出
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });

        showDialog(
          context: context,
          builder: (context) => FDialog(
            title: const Text('下载失败'),
            body: Text(e.toString()),
            actions: [
              FButton(
                style: FButtonStyle.outline,
                onPress: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader(
        title: Text(widget.album.name),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      "共 ${widget.album.photoCount} 张照片/视频",
                      textAlign: TextAlign.center,
                    ),
                  ),
                  _buildDownloadButton(),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 显示下载进度
            if (_isDownloading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(red: 0, green: 0, blue: 255, alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 使用ForUI的FProgress组件
                                const FProgress(),
                                const SizedBox(height: 4),
                                Text(
                                  _downloadMessage,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _downloadProgress <= 0
                                ? '准备中'
                                : _downloadProgress >= 1
                                    ? '完成'
                                    : '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // 照片内容
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: FProgress(),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _errorMessage!.contains("加密相册")
                            ? Icons.lock
                            : Icons.error,
                        color: _errorMessage!.contains("加密相册")
                            ? Colors.amber
                            : Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _errorMessage!.contains("加密相册")
                              ? Colors.amber.withValues(
                                  red: 255, green: 193, blue: 7, alpha: 0.1)
                              : Colors.red.withValues(
                                  red: 255, green: 0, blue: 0, alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: _errorMessage!.contains("加密相册")
                                ? Colors.amber[900]
                                : Colors.red,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FButton(
                            onPress: _loadPhotos,
                            child: const Text("重试"),
                          ),
                          const SizedBox(width: 16),
                          if (_errorMessage!.contains("加密相册"))
                            FButton(
                              onPress: _downloadAlbum,
                              child: const Text("尝试下载"),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_photos.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("该相册没有照片"),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  controller: _scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8.0,
                    mainAxisSpacing: 8.0,
                  ),
                  itemCount:
                      _isLoadingMore ? _photos.length + 1 : _photos.length,
                  itemBuilder: (context, index) {
                    // 显示加载更多指示器
                    if (_isLoadingMore && index == _photos.length) {
                      return const Card(
                        child: Center(
                          child: FProgress(),
                        ),
                      );
                    }

                    final photo = _photos[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openGallery(index),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 缩略图
                            if (photo.thumbUrl != null)
                              CachedNetworkImage(
                                imageUrl: photo.thumbUrl!,
                                fit: BoxFit.cover,
                                imageBuilder: (context, imageProvider) {
                                  // 尝试使用自定义图片加载器
                                  return Image(
                                    image: QzoneImageProvider(
                                        photo.thumbUrl!, ref),
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 50,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                },
                                placeholder: (context, url) => const Center(
                                  child: FProgress(),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            else
                              Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.photo,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              ),

                            // 视频标识
                            if (photo.isVideo)
                              Positioned.fill(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                          red: 0,
                                          green: 0,
                                          blue: 0,
                                          alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_circle_filled,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),

                            // 照片名称
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4.0),
                                color: Colors.black.withValues(
                                    red: 0, green: 0, blue: 0, alpha: 0.5),
                                child: Text(
                                  photo.isVideo
                                      ? "【视频】${photo.name}"
                                      : photo.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    if (_isDownloading) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在下载: $_downloadMessage',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.download),
        onPressed: _downloadAlbum,
        tooltip: '下载整个相册',
      );
    }
  }
}

// 照片画廊屏幕
class PhotoGalleryScreen extends ConsumerStatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  final Album album;
  final String? targetUin;

  const PhotoGalleryScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.album,
    this.targetUin,
  });

  @override
  ConsumerState<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends ConsumerState<PhotoGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _initializeVideoControllerIfNeeded();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  // 初始化视频控制器（如果当前项是视频）
  Future<void> _initializeVideoControllerIfNeeded() async {
    if (_currentIndex >= 0 && _currentIndex < widget.photos.length) {
      final photo = widget.photos[_currentIndex];
      if (photo.isVideo && photo.videoUrl != null) {
        _loadVideo(photo.videoUrl!);
      }
    }
  }

  // 加载视频
  Future<void> _loadVideo(String videoUrl) async {
    // 先释放之前的控制器
    _disposeVideoController();

    setState(() {
      _isVideoLoading = true;
    });

    try {
      final videoController =
          VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await videoController.initialize();

      if (mounted) {
        _videoController = videoController;
        _chewieController = ChewieController(
          videoPlayerController: videoController,
          autoPlay: true,
          looping: false,
          aspectRatio: videoController.value.aspectRatio,
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    "视频加载失败: $errorMessage",
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );

        setState(() {
          _isVideoLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("[VideoPlayer] 视频加载失败: $e");
      }

      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
        showDialog(
          context: context,
          builder: (context) => FDialog(
            title: const Text('视频加载失败'),
            body: Text(e.toString()),
            actions: [
              FButton(
                onPress: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  // 释放视频控制器资源
  void _disposeVideoController() {
    if (_chewieController != null) {
      _chewieController!.dispose();
      _chewieController = null;
    }

    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }
  }

  // 页面切换时处理
  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // 如果切换到视频，加载视频
    final photo = widget.photos[index];
    if (photo.isVideo && photo.videoUrl != null) {
      _loadVideo(photo.videoUrl!);
    } else {
      // 如果切换到图片，释放之前的视频资源
      _disposeVideoController();
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white, // 设置文字和图标颜色
        title: Text(
          photo.name,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          // 添加下载按钮          IconButton(            icon: const Icon(FIcons.download),            onPressed: _downloadSingleFile,          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final item = widget.photos[index];

                // 显示视频
                if (item.isVideo) {
                  if (_isVideoLoading) {
                    return const Center(
                      child: FProgress(),
                    );
                  }

                  if (_currentIndex == index && _chewieController != null) {
                    return Chewie(controller: _chewieController!);
                  }

                  // 显示视频缩略图
                  return Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (item.thumbUrl != null)
                          Image.network(
                            item.thumbUrl!,
                            fit: BoxFit.contain,
                          ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                                red: 0, green: 0, blue: 0, alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_circle_filled,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // 显示图片
                if (item.url != null) {
                  return PhotoView(
                    imageProvider: QzoneImageProvider(item.url!, ref),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    loadingBuilder: (context, event) => const Center(
                      child: FProgress(),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  );
                }

                // 如果没有URL，显示错误图标
                return const Center(
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 50,
                  ),
                );
              },
            ),
          ),

          // 底部信息和描述
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (photo.desc != null && photo.desc!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      photo.desc!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                Text(
                  "${_currentIndex + 1} / ${widget.photos.length}",
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
