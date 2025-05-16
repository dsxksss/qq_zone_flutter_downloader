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

  // 处理登出
  Future<void> _handleLogout() async {
    try {
      // 显示加载指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('正在登出'),
          content: const SizedBox(
            height: 100,
            child: Center(child: FProgress()),
          ),
        ),
      );

      // 清除登录状态
      final qzoneService = ref.read(qZoneServiceProvider);
      await qzoneService.clearLoginState();
      
      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // 跳转到登录页面
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // 显示错误
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('登出失败'),
            content: Text('发生错误：${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
                    onPress: _handleLogout, // 使用新的登出方法
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
            // 显示相册列表
            else if (_albums.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        title: Text(album.name),
                        subtitle: Text('照片数量: ${album.photoCount}'),
                        leading: album.coverUrl != null
                            ? SizedBox(
                                width: 50,
                                height: 50,
                                child: Image.network(
                                  album.coverUrl!,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.image);
                                  },
                                ),
                              )
                            : const Icon(Icons.photo_album),
                        onTap: () {
                          // TODO: 实现相册详情页面
                        },
                      ),
                    );
                  },
                ),
              )
            else if (!_isLoadingAlbums)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text('暂无相册数据，请点击上方按钮加载'),
                ),
              ),
          ],
        ),
      ),
    );
  }
} 