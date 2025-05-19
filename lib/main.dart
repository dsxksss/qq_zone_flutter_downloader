import 'package:flutter/material.dart';
import 'package:forui/forui.dart'; // 导入 forui
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 如果使用 Riverpod
// 导入 FontAwesome

// 假设您的登录界面会在这里
import 'package:qq_zone_flutter_downloader/presentation/splash/splash_screen.dart'; // 导入启动屏幕

void main() {
  runApp(
    const ProviderScope(
      child: Application(), // 改为 Application
    ),
  );
}

// 根据 forui 文档，创建一个 Application widget
class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) {
    // 从 forui 文档 (https://forui.dev/docs/themes) 和 Getting Started 页面，
    // FThemes.[colorSchemeName].[variant] 是获取预设主题的方式。
    // 例如: FThemes.zinc.light, FThemes.slate.dark
    final FThemeData fTheme = FThemes.zinc.light; // 请选择一个实际存在的主题

    return MaterialApp(
      builder: (context, child) => FTheme(
        data: fTheme,
        child: child!,
      ),
      home: const SplashScreen(), // 更改为启动屏幕
      debugShowCheckedModeBanner: false,
    );
  }
}
