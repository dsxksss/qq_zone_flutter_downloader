import 'package:flutter/foundation.dart'; // 导入 kDebugMode
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 导入 Riverpod
import 'package:qq_zone_flutter_downloader/core/models/album.dart'; // 导入 Album
import 'package:qq_zone_flutter_downloader/core/models/friend.dart'; // 导入 Friend
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart'; // 导入 Provider
import 'package:qq_zone_flutter_downloader/presentation/login/login_screen.dart';
import 'package:qq_zone_flutter_downloader/presentation/album/album_details_screen.dart';
import 'package:qq_zone_flutter_downloader/presentation/download/download_records_screen.dart';
import 'package:qq_zone_flutter_downloader/core/providers/qzone_image_provider.dart'; // 导入QzoneImageProvider

class HomeScreen extends ConsumerStatefulWidget {
  // 修改为 ConsumerStatefulWidget
  final String? nickname;

  const HomeScreen({super.key, this.nickname});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  // 创建 State 类
  List<Album> _albums = [];
  List<Friend> _friends = [];
  List<Friend> _filteredFriends = []; // 筛选后的好友列表
  bool _isLoadingAlbums = false;
  bool _isLoadingFriends = false;
  String? _albumError;
  String? _friendError;
  String? _selectedFriendUin; // 当前选中的好友QQ号
  late TabController _tabController;
  final TextEditingController _searchController =
      TextEditingController(); // 搜索框控制器

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 为搜索框添加监听
    _searchController.addListener(_filterFriends);

    // 页面加载后自动加载相册列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlbums();
      _loadFriends();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterFriends);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // 根据搜索关键字筛选好友
  void _filterFriends() {
    final String keyword = _searchController.text.toLowerCase();
    if (keyword.isEmpty) {
      setState(() {
        _filteredFriends = List.from(_friends);
      });
    } else {
      setState(() {
        _filteredFriends = _friends.where((friend) {
          return friend.nickname.toLowerCase().contains(keyword) ||
              friend.uin.toLowerCase().contains(keyword);
        }).toList();
      });
    }
  }

  // 加载我的相册
  Future<void> _loadAlbums() async {
    if (kDebugMode) {
      print("[HomeScreen DEBUG] 开始加载相册列表");
      print(
          "[HomeScreen DEBUG] 当前状态: _isLoadingAlbums=$_isLoadingAlbums, _albumError=$_albumError");
      print(
          "[HomeScreen DEBUG] 当前选中的好友: _selectedFriendUin=$_selectedFriendUin");
    }

    setState(() {
      _isLoadingAlbums = true;
      _albumError = null;
      _albums = []; // 清空之前的列表
    });
    try {
      final qzoneService = ref.read(qZoneServiceProvider);
      if (kDebugMode) {
        print(
            "[HomeScreen DEBUG] 登录状态检查: isLoggedIn=${qzoneService.isLoggedIn}");
        print(
            "[HomeScreen DEBUG] 登录信息: gTk=${qzoneService.gTk}, loggedInUin=${qzoneService.loggedInUin}");
      }

      final albums = await qzoneService.getAlbumList(
        targetUin: _selectedFriendUin,
      );

      if (kDebugMode) {
        print("[HomeScreen DEBUG] 获取到相册数量: ${albums.length}");
        for (var album in albums) {
          print(
              "[HomeScreen DEBUG] 相册信息: name=${album.name}, id=${album.id}, photoCount=${album.photoCount}");
        }
      }

      if (mounted) {
        // 确保相册有效且至少有一张照片
        final validAlbums = albums
            .where((album) => album.id.isNotEmpty && album.photoCount > 0)
            .toList();

        setState(() {
          _albums = validAlbums;
          _isLoadingAlbums = false;
        });

        if (kDebugMode) {
          print(
              "[HomeScreen DEBUG] 状态更新完成: _albums.length=${_albums.length}, _isLoadingAlbums=$_isLoadingAlbums");
        }
      } else {
        if (kDebugMode) {
          print("[HomeScreen DEBUG] Widget已经被销毁，不更新状态");
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("[HomeScreen ERROR] 加载相册失败:");
        print("错误: $e");
        print("堆栈: $stackTrace");
      }

      if (mounted) {
        setState(() {
          _albumError = e.toString();
          _isLoadingAlbums = false;
        });

        if (kDebugMode) {
          print(
              "[HomeScreen DEBUG] 错误状态已更新: _albumError=$_albumError, _isLoadingAlbums=$_isLoadingAlbums");
        }
      }
    }
  }

  // 加载好友列表
  Future<void> _loadFriends() async {
    if (kDebugMode) {
      print("[HomeScreen DEBUG] 开始加载好友列表");
    }

    setState(() {
      _isLoadingFriends = true;
      _friendError = null;
      _friends = []; // 清空之前的列表
      _filteredFriends = []; // 清空筛选列表
    });
    try {
      final qzoneService = ref.read(qZoneServiceProvider);

      if (kDebugMode) {
        print(
            "[HomeScreen DEBUG] 登录状态检查: isLoggedIn=${qzoneService.isLoggedIn}");
        print(
            "[HomeScreen DEBUG] 登录信息: gTk=${qzoneService.gTk}, loggedInUin=${qzoneService.loggedInUin}");
      }

      final friends = await qzoneService.getFriendList();

      if (kDebugMode) {
        print("[HomeScreen DEBUG] 获取到好友数量: ${friends.length}");
      }

      // 过滤掉自己的账号，防止从好友列表进入自己的相册
      final String? currentUserUin = qzoneService.loggedInUin;
      final filteredFriends =
          friends.where((friend) => friend.uin != currentUserUin).toList();

      if (mounted) {
        setState(() {
          _friends = filteredFriends;
          _filteredFriends = List.from(filteredFriends); // 初始时显示全部好友
          _isLoadingFriends = false;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("[HomeScreen ERROR] 加载好友列表失败:");
        print("错误: $e");
        print("堆栈: $stackTrace");
      }

      if (mounted) {
        setState(() {
          _friendError = e.toString();
          _isLoadingFriends = false;
        });
      }
    }
  }

  // 打开相册详情
  void _openAlbumDetails(Album album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AlbumDetailsScreen(
          album: album,
          targetUin: _selectedFriendUin,
        ),
      ),
    );
  }

  // 选择好友
  void _selectFriend(Friend friend) {
    setState(() {
      _selectedFriendUin = friend.uin;
    });

    // 加载所选好友的相册
    _loadAlbums();

    // 切换到相册标签页
    _tabController.animateTo(0);
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
    return Material(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              'QQ空间相册下载${_selectedFriendUin != null ? ' (${_getSelectedFriendName()})' : ''}'),
          actions: [
            // 添加下载记录入口
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DownloadRecordsScreen(),
                  ),
                );
              },
              tooltip: '下载记录',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _handleLogout();
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('退出登录'),
                  ),
                ];
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '我的相册'),
              Tab(text: '好友相册'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // 我的相册
            _buildMyAlbums(),
            // 好友相册
            _buildFriendsTab(),
          ],
        ),
      ),
    );
  }

  // 获取选中好友的名称
  String _getSelectedFriendName() {
    if (_selectedFriendUin == null) return '';

    try {
      return _friends
          .firstWhere((f) => f.uin == _selectedFriendUin,
              orElse: () => Friend(
                  uin: _selectedFriendUin!, nickname: _selectedFriendUin!))
          .nickname;
    } catch (e) {
      return _selectedFriendUin!;
    }
  }

  // 构建相册标签页
  Widget _buildMyAlbums() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前正在查看的好友相册提示
          if (_selectedFriendUin != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              margin: const EdgeInsets.only(bottom: 16.0),
              decoration: BoxDecoration(
                color: Colors.blue
                    .withValues(red: 0, green: 0, blue: 255, alpha: 0.1),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                    color: Colors.blue
                        .withValues(red: 0, green: 0, blue: 255, alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '正在查看: ${_getSelectedFriendName()} 的相册',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  FButton(
                    onPress: () {
                      setState(() {
                        _selectedFriendUin = null;
                      });
                      _loadAlbums();
                    },
                    style: FButtonStyle.outline,
                    child: const Text('返回我的相册'),
                  ),
                ],
              ),
            ),

          // 相册列表标题
          Text(
            _selectedFriendUin != null ? '好友相册' : '我的相册',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),

          // 相册列表内容
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAlbums,
              child: _isLoadingAlbums
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 100),
                        Center(child: FProgress()),
                      ],
                    )
                  : _albumError != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: 100),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _albumError!,
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FButton(
                                    onPress: _loadAlbums,
                                    child: const Text("重试"),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : _albums.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 100),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.folder_open,
                                        size: 54,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        "没有找到相册",
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.8,
                              ),
                              itemCount: _albums.length,
                              padding: EdgeInsets.zero,
                              itemBuilder: (context, index) {
                                if (index >= _albums.length) {
                                  return const SizedBox(); // 防止索引越界
                                }
                                final album = _albums[index];
                                return _buildAlbumCard(album);
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建好友内容
  Widget _buildFriendsContent() {
    if (_isLoadingFriends) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: FProgress()),
        ],
      );
    }

    if (_friendError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 100),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '加载好友失败: $_friendError',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FButton(
                  onPress: _loadFriends,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 显示好友列表
    if (_filteredFriends.isNotEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredFriends.length,
        itemBuilder: (context, index) {
          final friend = _filteredFriends[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8.0),
            elevation: 2,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              title: Text(
                friend.nickname,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text('QQ: ${friend.uin}'),
              leading: ClipOval(
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[200],
                  child: friend.avatarUrl != null
                      ? Image.network(
                          friend.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.person,
                            size: 32,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          size: 32,
                          color: Colors.grey,
                        ),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () => _selectFriend(friend),
            ),
          );
        },
      );
    }

    if (_searchController.text.isNotEmpty && _filteredFriends.isEmpty) {
      // 搜索无结果的提示
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_off,
                  size: 54,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  '没有找到匹配的好友',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 没有好友的提示
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 100),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group,
                size: 54,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                '没有找到好友',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 构建好友标签页
  Widget _buildFriendsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 添加搜索框
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索QQ好友（昵称或QQ号）',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),

          const SizedBox(height: 16),

          // 好友列表标题
          const Row(
            children: [
              Icon(Icons.people, size: 18),
              SizedBox(width: 8),
              Text(
                '好友列表',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadFriends,
              child: _buildFriendsContent(),
            ),
          ),
        ],
      ),
    );
  }

  // 构建相册卡片
  Widget _buildAlbumCard(Album album) {
    // 处理错误相册的特殊显示
    if (album.id == 'error') {
      return Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                album.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (album.desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  album.desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FButton(
              style: FButtonStyle.outline,
              onPress: _loadAlbums,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: () => _openAlbumDetails(album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 相册封面
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图片
                  album.coverUrl != null
                      ? Image(
                          image: QzoneImageProvider(album.coverUrl!, ref),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(
                                  Icons.photo_library,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.photo_library,
                              size: 48,
                              color: Colors.grey,
                            ),
                          ),
                        ),

                  // 照片数量标签
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.image,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${album.photoCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 相册信息
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    );
  }
}
