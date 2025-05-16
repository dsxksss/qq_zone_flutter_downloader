import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/models/album.dart';
import 'package:qq_zone_flutter_downloader/core/models/photo.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';

class AlbumDetailsScreen extends ConsumerStatefulWidget {
  final Album album;
  
  const AlbumDetailsScreen({super.key, required this.album});
  
  @override
  ConsumerState<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends ConsumerState<AlbumDetailsScreen> {
  bool _isLoading = false;
  List<Photo> _photos = [];
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }
  
  Future<void> _loadPhotos() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
                Text("共 ${widget.album.photoCount} 张照片", 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8.0,
                    mainAxisSpacing: 8.0,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          // 显示大图
                          if (photo.url != null) {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: Image.network(
                                        photo.url!,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Center(
                                            child: FProgress(
                                              value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded / 
                                                  (loadingProgress.expectedTotalBytes ?? 1)
                                                : null,
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(Icons.error, size: 50),
                                          );
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        photo.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (photo.desc != null && photo.desc!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0, 
                                          right: 8.0,
                                          bottom: 16.0,
                                        ),
                                        child: Text(photo.desc!),
                                      ),
                                    FButton(
                                      child: const Text("关闭"),
                                      onPress: () => Navigator.of(context).pop(),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            photo.thumbUrl != null
                                ? Image.network(
                                    photo.thumbUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Icon(
                                          Icons.image_not_supported,
                                          size: 50,
                                          color: Colors.grey,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.photo,
                                      size: 50,
                                      color: Colors.grey,
                                    ),
                                  ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4.0),
                                color: Colors.black.withOpacity(0.5),
                                child: Text(
                                  photo.name,
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