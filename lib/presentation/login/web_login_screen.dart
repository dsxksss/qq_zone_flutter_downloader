import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
            
            // 检查是否是登录成功的跳转
            if (url.contains('user.qzone.qq.com')) {
              _handlePossibleLogin();
            }
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('加载失败: ${error.description}')),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            // 处理QQ登录URL scheme
            if (request.url.startsWith('wtloginmqq://') ||
                request.url.startsWith('mqq://')) {
              try {
                // 使用原始URL，但移除 schemacallback 参数
                Uri originalUri = Uri.parse(request.url);
                Uri uriToLaunch = originalUri;
                if (originalUri.queryParameters.containsKey('schemacallback')) {
                  final params = Map<String, String>.from(originalUri.queryParameters);
                  params.remove('schemacallback');
                  uriToLaunch = originalUri.replace(queryParameters: params.isNotEmpty ? params : null);
                }

                if (await canLaunchUrl(uriToLaunch)) {
                  await launchUrl(
                    uriToLaunch,
                    mode: LaunchMode.externalApplication, // 使用外部应用模式打开
                  );
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法打开QQ应用，请确保已安装QQ')),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('打开QQ应用失败: ${e.toString()}')),
                  );
                }
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://qzone.qq.com/'),
      );
  }

  Future<void> _handlePossibleLogin() async {
    final qzoneService = ref.read(qZoneServiceProvider);
    
    try {
      // 获取WebView中的Cookies
      final cookies = await _controller.runJavaScriptReturningResult(
        "document.cookie",
      ) as String;

      if (cookies.contains('p_skey=') || cookies.contains('skey=')) {
        // 更新QzoneService中的cookies
        await qzoneService.updateCookiesFromString(cookies);
        
        if (mounted) {
          // 登录成功，跳转到主页
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const HomeScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录处理失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QQ空间登录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
} 