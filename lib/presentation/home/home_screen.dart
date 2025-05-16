import 'package:flutter/foundation.dart'; // 导入 kDebugMode
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 导入 Riverpod
import 'package:qq_zone_flutter_downloader/core/models/album.dart'; // 导入 Album
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart'; // 导入 Provider
import 'package:qq_zone_flutter_downloader/presentation/login/login_screen.dart';

class HomeScreen extends ConsumerStatefulWidget { // 修改为 ConsumerStatefulWidget
  final String? nickname;

  const HomeScreen({super.key, this.nickname});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> { // 创建 State 类
  List<Album> _albums = [];
  bool _isLoadingAlbums = false;
  String? _albumError;

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoadingAlbums = true;
      _albumError = null;
      _albums = []; // 清空之前的列表
    });
    try {
      final qzoneService = ref.read(qZoneServiceProvider);
      // DEBUGGING: Print gTk and uin from the service instance HomeScreen is using
      if (kDebugMode) {
        print("[HomeScreen DEBUG] Attempting to load albums. QZoneService instance has gTk: ${qzoneService.gTk}, loggedInUin: ${qzoneService.loggedInUin}");
      }
      final albums = await qzoneService.getAlbumList(); // uin 可以根据需要传递
      if (mounted) {
        setState(() {
          _albums = albums;
          _isLoadingAlbums = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _albumError = e.toString();
          _isLoadingAlbums = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader(
        title: Text(widget.nickname ?? '主页'),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '欢迎, ${widget.nickname ?? '用户'}!',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                FButton(
                  child: const Text('登出'),
                  onPress: () async {
                    final qzoneService = ref.read(qZoneServiceProvider);
                    await qzoneService.logout();
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (Route<dynamic> route) => false,
                      );
                    }
                  }
                ),
              ],
            ),
            const SizedBox(height: 20),
            FButton(
              child: const Text('加载相册列表'),
              onPress: _isLoadingAlbums ? null : _loadAlbums, // 加载时禁用按钮
              // icon: _isLoadingAlbums ? const FSpinner() : null, // 可选：加载时显示Spinner
            ),
            const SizedBox(height: 10),
            if (_isLoadingAlbums)
              const Center(child: FProgress()) // 显示加载指示器
            else if (_albumError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('加载相册失败: $_albumError', style: const TextStyle(color: Colors.red)),
              )
            else if (_albums.isEmpty && !_isLoadingAlbums) // 且不是因为正在加载而为空
               Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: const Text('暂无相册，或点击按钮加载。'),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    return FCard(
                      child: ListTile(
                        leading: album.coverUrl != null 
                            ? Image.network(album.coverUrl!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, o, s) => const Icon(Icons.image_not_supported, size: 40,)) 
                            : const Icon(Icons.photo_album, size: 40),
                        title: Text(album.name),
                        subtitle: Text('共 ${album.photoCount} 张照片'),
                        onTap: () {
                          // TODO: 点击相册，导航到照片列表页
                          if (kDebugMode) {
                            print('点击了相册: ${album.name} (ID: ${album.id})');
                          }
                        },
                      )
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