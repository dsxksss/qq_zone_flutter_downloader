import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart';
import 'package:qq_zone_flutter_downloader/presentation/login/login_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _statusMessage = "正在检查登录状态...";

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 检查并请求权限
      await _checkAndRequestPermissions();

      // 检查登录状态
      final isLoggedIn = await _checkLoginStatus();

      if (isLoggedIn) {
        if (kDebugMode) {
          print("用户已登录，跳转到主页");
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        if (kDebugMode) {
          print("用户未登录，跳转到登录页面");
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("初始化出错: $e");
      }

      setState(() {
        _statusMessage = "初始化失败，即将跳转到登录页面...";
      });

      // 出错时也导航到登录页面
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 30) {
        // Android 11 (API 30) 及以上
        if (await Permission.manageExternalStorage.status.isDenied) {
          if (kDebugMode) {
            print("[SplashScreen] Android 11+: 请求 MANAGE_EXTERNAL_STORAGE 权限");
          }
          await Permission.manageExternalStorage.request();
        }
      } else {
        // Android 10 (API 29) 及以下
        if (await Permission.storage.status.isDenied) {
          if (kDebugMode) {
            print("[SplashScreen] Android <11: 请求 STORAGE 权限");
          }
          await Permission.storage.request();
        }
      }

      // 统一请求通知权限 (Android 13+ 需要显式请求)
      if (await Permission.notification.status.isDenied) {
        if (kDebugMode) {
          print("[SplashScreen] 请求 NOTIFICATION 权限");
        }
        await Permission.notification.request();
      }
    }
    // 对于 iOS, 如果未来需要访问照片库等，可以在此处添加相应权限请求
    // 例如: if (Platform.isIOS) { await Permission.photos.request(); }
    // 当前保存到应用文档目录，通常不需要额外权限。
  }

  Future<bool> _checkLoginStatus() async {
    await Future.delayed(const Duration(seconds: 1)); // 给服务初始化一些时间

    try {
      final qzoneService = ref.read(qZoneServiceProvider);

      // 等待服务初始化完成
      if (!qzoneService.isInitialized) {
        setState(() {
          _statusMessage = "正在初始化服务...";
        });
        // 给服务多一点时间初始化
        await Future.delayed(const Duration(seconds: 2));
      }

      if (qzoneService.isLoggedIn) {
        if (kDebugMode) {
          print("用户已登录，nickname: ${qzoneService.loggedInUin}");
        }

        return true;
      } else {
        if (kDebugMode) {
          print("用户未登录，跳转到登录页面");
        }

        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print("登录状态检查出错: $e");
      }

      setState(() {
        _statusMessage = "登录状态检查失败，即将跳转到登录页面...";
      });

      // 出错时也导航到登录页面
      await Future.delayed(const Duration(seconds: 2));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader(title: const Text('启动中')),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.space_dashboard,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const FProgress(),
            const SizedBox(height: 20),
            Text(_statusMessage),
          ],
        ),
      ),
    );
  }
}
