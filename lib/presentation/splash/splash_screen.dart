import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart';
import 'package:qq_zone_flutter_downloader/presentation/login/login_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _isLoading = true;
  String _statusMessage = "正在检查登录状态...";

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
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
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                nickname: qzoneService.loggedInUin ?? "用户",
              ),
            ),
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
        print("登录状态检查出错: $e");
      }
      
      setState(() {
        _statusMessage = "登录状态检查失败，即将跳转到登录页面...";
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

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader(title: const Text('启动中')),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FProgress(),
            const SizedBox(height: 20),
            Text(_statusMessage),
          ],
        ),
      ),
    );
  }
} 