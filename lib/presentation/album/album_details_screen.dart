import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/models/album.dart';
import 'package:qq_zone_flutter_downloader/core/models/photo.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class AlbumDetailsScreen extends ConsumerStatefulWidget {
  final Album album;
  
  const AlbumDetailsScreen({super.key, required this.album});
  
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
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
      );
      
      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false;
          _pageStart = _pageSize;
          _hasMore = photos.length >= _pageSize && photos.length < widget.album.photoCount;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("[AlbumDetails] 加载照片失败: $e");
      }
      
      if (mounted) {
        setState(() {
          _errorMessage = "加载照片失败: ${e.toString()}";
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
        print("[AlbumDetails] 加载更多照片，当前页码: $_pageStart，当前照片数: ${_photos.length}");
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
        pageStart: _pageStart,  // 使用当前的页码作为起始位置
      );
      
      if (mounted) {
        // 过滤掉已有的照片
        final newPhotos = morePhotos.where((newPhoto) => 
          !_photos.any((existingPhoto) => existingPhoto.id == newPhoto.id)
        ).toList();
        
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("加载更多照片失败: ${e.toString()}"),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '重试',
              onPressed: _loadMorePhotos,
            ),
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
        ),
      ),
    );
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
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "共 ${widget.album.photoCount} 张照片，已加载 ${_photos.length} 张", 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
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
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FButton(
                        onPress: _loadPhotos,
                        child: const Text("重试"),
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
                  itemCount: _isLoadingMore ? _photos.length + 1 : _photos.length,
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
                                placeholder: (context, url) => const Center(
                                  child: FProgress(),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.image_not_supported,
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
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
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
                                color: Colors.black.withOpacity(0.5),
                                child: Text(
                                  photo.isVideo ? "【视频】${photo.name}" : photo.name,
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
}

// 照片画廊屏幕
class PhotoGalleryScreen extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  
  const PhotoGalleryScreen({
    Key? key,
    required this.photos,
    required this.initialIndex,
  }) : super(key: key);
  
  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
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
      final videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
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
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("视频加载失败: ${e.toString()}")),
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
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // TODO: 实现下载功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("下载功能尚未实现")),
              );
            },
          ),
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
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
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
                    imageProvider: NetworkImage(item.url!),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    loadingBuilder: (context, event) => const Center(
                      child: FProgress(),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.error,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  );
                }
                
                // 如果没有URL，显示错误图标
                return const Center(
                  child: Icon(
                    Icons.error,
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