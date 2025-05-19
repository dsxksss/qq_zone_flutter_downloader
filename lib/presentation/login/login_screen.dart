import 'dart:async'; // For StreamSubscription
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
// import 'package:qr_flutter/qr_flutter.dart'; // Removed as unused
import 'package:qq_zone_flutter_downloader/core/models/login_qr_result.dart';
import 'package:qq_zone_flutter_downloader/core/models/login_poll_result.dart'; // 确保此文件已创建
import 'package:qq_zone_flutter_downloader/core/models/qzone_api_exception.dart'; // Import QZoneLoginException
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart'; // Import HomeScreen
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart'; // Import provider
import 'package:flutter/foundation.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  LoginQrResult? _loginQrContext; // Stores loginSig and qrsig
  Uint8List? _qrImageBytes;

  bool isLoadingQr = false;
  String loginStatus = "请点击按钮获取二维码";
  String? errorMessage;

  StreamSubscription<LoginPollResult?>? _pollSubscription;

  @override
  void initState() {
    super.initState();
    // 检查是否已经登录
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfAlreadyLoggedIn();
    });
  }

  Future<void> _checkIfAlreadyLoggedIn() async {
    final qzoneService = ref.read(qZoneServiceProvider);
    if (qzoneService.isLoggedIn) {
      if (kDebugMode) {
        print("[LoginScreen] 用户已登录，自动跳转到主页");
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
    }
  }

  @override
  void dispose() {
    _pollSubscription?.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

  Future<void> _fetchAndDisplayQrCode() async {
    await _pollSubscription?.cancel(); // Cancel any existing polling
    setState(() {
      isLoadingQr = true;
      _qrImageBytes = null;
      errorMessage = null;
      _loginQrContext = null;
      loginStatus = "正在获取二维码...";
    });

    final qzoneService =
        ref.read(qZoneServiceProvider); // Get service from Riverpod

    try {
      final result = await qzoneService.getLoginQrImage();
      _loginQrContext = result;
      if (mounted) {
        setState(() {
          _qrImageBytes = result.qrImageBytes;
          isLoadingQr = false;
          loginStatus = "请使用手机QQ扫描二维码 (获取成功)"; // Initial poll message
        });
        if (_loginQrContext != null) {
          // Null check for _loginQrContext
          _startLoginPolling(_loginQrContext!.loginSig, _loginQrContext!.qrsig);
        }
      }
    } on QZoneLoginException catch (e) {
      if (mounted) {
        setState(() {
          isLoadingQr = false;
          errorMessage = "二维码获取失败: ${e.message}";
          loginStatus = "二维码获取失败，请重试。";
          // print("QZoneLoginException: ${e.message}, Underlying: ${e.underlyingError}");
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingQr = false;
          errorMessage = "发生未知错误: ${e.toString()}";
          loginStatus = "发生未知错误，请重试。";
          // print("Unknown error fetching QR: $e");
        });
      }
    }
  }

  void _startLoginPolling(String loginSig, String qrsig) {
    final qzoneService =
        ref.read(qZoneServiceProvider); // Get service from Riverpod
    final ptqrtoken = qzoneService.calculatePtqrtoken(qrsig);
    // print("Calculated ptqrtoken: $ptqrtoken");

    _pollSubscription = qzoneService
        .pollLoginStatus(
      loginSig: loginSig,
      qrsig: qrsig,
      ptqrtoken: ptqrtoken,
    )
        .listen((LoginPollResult? pollResult) {
      if (!mounted || pollResult == null) return;
      // print("Poll Result: $pollResult");
      setState(() {
        loginStatus = pollResult.message ?? loginStatus;
        switch (pollResult.status) {
          case LoginPollStatus.loginSuccess:
            errorMessage = null;
            loginStatus = "登录成功! 欢迎您, ${pollResult.nickname ?? '用户'}!";
            _pollSubscription?.cancel();
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (context) =>
                        HomeScreen(nickname: pollResult.nickname)),
              );
            }
            break;
          case LoginPollStatus.qrInvalidOrExpired:
            errorMessage = "二维码已失效，请重新获取。";
            _qrImageBytes = null; // Clear QR image
            _pollSubscription?.cancel(); // Stop polling
            break;
          case LoginPollStatus.qrNotScanned:
          case LoginPollStatus.qrScannedWaitingConfirmation:
            errorMessage = null;
            break;
          case LoginPollStatus.error:
            errorMessage = "轮询出错: ${pollResult.message ?? '未知错误'}";
            break;
          case LoginPollStatus.unknown:
            errorMessage = "轮询返回未知状态: ${pollResult.message ?? '未知状态'}";
            break;
        }
      });
    }, onError: (error) {
      if (!mounted) return;
      // print("Error in poll stream: $error");
      setState(() {
        errorMessage = "轮询流发生错误: ${error.toString()}";
        loginStatus = "登录状态检查中断。";
      });
    }, onDone: () {
      if (!mounted) return;
      // print("Polling stream done.");
      // If stream closes and not loginSuccess, it might be due to QR invalid or an error that closed the stream.
      // The state should already reflect this from the last emitted LoginPollResult.
    });
  }

  @override
  Widget build(BuildContext context) {
    // final fTheme = FTheme.of(context); // Your forui theme access

    return FScaffold(
      header: FHeader(
        title: Text('QQ空间下载器登录'),
        // Forui FHeader actions: According to forui.dev, FHeader does not have an 'actions' property.
        // Common alternatives:
        // 1. Use `trailing` property if FHeader supports it for a single widget.
        // 2. Use a Row in the `title` if you need multiple actions (might get complex).
        // 3. Place action buttons elsewhere in the FScaffold's body or a bottom navigation bar.
        // For now, I'll remove the actions from FHeader to avoid Linter errors.
        // You'll need to decide where to best place a refresh button based on forui's capabilities.
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: FCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (!isLoadingQr && _qrImageBytes == null)
                    FButton(
                      onPress: _fetchAndDisplayQrCode,
                      child: const Text('获取登录二维码'),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    loginStatus,
                    textAlign: TextAlign.center,
                    // style: TextStyle(fontSize: fTheme.fontSizes.md),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: isLoadingQr &&
                            _qrImageBytes ==
                                null // Show progress only if QR not yet loaded
                        ? const FProgress()
                        : _qrImageBytes != null
                            ? Image.memory(_qrImageBytes!)
                            : Container(
                                alignment: Alignment.center,
                                // child: Text("二维码将显示在此"),
                              ),
                  ),
                  const SizedBox(height: 24),
                  if (errorMessage != null)
                    Text(
                      errorMessage!,
                      // style: TextStyle(color: fTheme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
