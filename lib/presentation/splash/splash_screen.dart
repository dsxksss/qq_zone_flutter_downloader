import 'package:flutter/foundation.dart'; // Import kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart';
import 'package:qq_zone_flutter_downloader/presentation/login/login_screen.dart';
import 'package:forui/forui.dart'; // For FProgress

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    final qzoneService = ref.read(qZoneServiceProvider);
    try {
      await qzoneService.initialize(); // Initialize the service and load saved info
      
      // A short delay to show splash screen, can be removed or adjusted
      await Future.delayed(const Duration(milliseconds: 500)); 

      if (mounted) { // Check if the widget is still in the tree
        if (qzoneService.isLoggedIn()) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomeScreen(nickname: qzoneService.loginNickname)),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[SplashScreen] Initialization or navigation error: $e");
      }
      if (mounted) {
        // Fallback to LoginScreen on any error during init
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FlutterLogo(size: 60), // Using FlutterLogo as a placeholder
            SizedBox(height: 20),
            FProgress(),
            SizedBox(height: 10),
            Text("正在加载..."),
          ],
        ),
      ),
    );
  }
} 