import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'package:qq_zone_flutter_downloader/presentation/home/home_screen.dart';
import 'package:forui/forui.dart'; // For FHeader, FScaffold
import 'package:qq_zone_flutter_downloader/core/constants.dart'; // Import QZoneApiConstants

class WebViewLoginScreen extends ConsumerStatefulWidget {
  const WebViewLoginScreen({super.key});

  @override
  ConsumerState<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends ConsumerState<WebViewLoginScreen> {
  final CookieManager _cookieManager = CookieManager.instance();
  
  // TODO: Determine the best initial URL for QQ login via WebView
  // This might be a more generic login page that then offers username/password
  final String initialUrl = "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?appid=549000912&daid=5&style=22&s_url=https%3A%2F%2Fqzs.qq.com%2Fqzone%2Fv5%2Floginsucc.html%3Fpara%3Dizone";
  // Alternative: "https://ui.ptlogin2.qq.com/cgi-bin/login?daid=5&pt_style=22&appid=549000912&s_url=https%3A%2F%2Fqzs.qq.com%2Fqzone%2Fv5%2Floginsucc.html%3Fpara%3Dizone&hln_css=https%3A%2F%2Fqzs.qq.com%2Fqzone%2Fv6%2Fimg%2F பாரம்பரிய%2Fstyle%2Flogin_frame_blue_radius.css"

  bool _isLoadingPage = true;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _checkLoginSuccessAndExtractCookies(String url) async {
    if (kDebugMode) {
      print("[WebViewLoginScreen] URL changed/loaded: $url");
    }
    // setState(() { _currentUrl = url; }); // _currentUrl is unused for now

    bool isLoginSuccess = false;
    String? pSkey;
    String? uin;
    // String? nickname; // Unused local variable, nickname is hard to get from cookies

    if (Uri.tryParse(url)?.host.endsWith('qzone.qq.com') == true) {
      final qzoneCookies = await _cookieManager.getCookies(url: WebUri("https://qzone.qq.com")); // Changed to WebUri
      final qqComCookies = await _cookieManager.getCookies(url: WebUri("https://www.qq.com")); // Changed to WebUri
      
      List<Cookie> allCookies = [ ...qzoneCookies, ...qqComCookies ];
      
      if (kDebugMode) {
        print("[WebViewLoginScreen] Cookies for qzone.qq.com & qq.com:");
        for (var cookie in allCookies) {
          print("  ${cookie.name}=${cookie.value} (Domain: ${cookie.domain})");
          if (cookie.name == 'p_skey') pSkey = cookie.value;
          if (cookie.name == 'uin' || cookie.name == 'p_uin') uin = cookie.value;
          // Nickname usually isn't directly in cookies, might need JS injection or another API call
        }
      }

      if (pSkey != null && uin != null) {
        isLoginSuccess = true;
      }
    }
    
    // More specific check: if the redirect URL from扫码登录 is hit
    if (url.contains("ptlogin2.qzone.qq.com/check_sig") || url.contains("qzs.qq.com/qzone/v5/loginsucc.html")) {
        // This indicates a successful step in the login flow, let's grab all cookies we can
        // It's crucial that these cookies are set on domains dio can access or that we can transfer
        final List<Cookie> allDomainCookies = await _cookieManager.getAllCookies(); 
        if (kDebugMode) {
            print("[WebViewLoginScreen] ALL Cookies from CookieManager after check_sig/loginsucc URL:");
            for (var cookie in allDomainCookies) {
                print("  ${cookie.name}=${cookie.value} (Domain: ${cookie.domain})");
                if (cookie.domain != null && cookie.domain!.contains('qq.com')) {
                    if (cookie.name == 'p_skey') pSkey = cookie.value;
                    if (cookie.name == 'uin' || cookie.name == 'p_uin') uin = cookie.value;
                }
            }
        }
        if (pSkey != null && uin != null) {
            isLoginSuccess = true;
        }
    }


    if (isLoginSuccess && pSkey != null && uin != null) {
      setState(() { _isLoadingPage = true; }); // Show loading indicator while processing
      if (kDebugMode) {
        print("[WebViewLoginScreen] Login detected! p_skey: $pSkey, uin: $uin");
      }
      final qzoneService = ref.read(qZoneServiceProvider);
      
      // Manually set these values in QZoneService (similar to _handleCredentialRedirect)
      // QZoneService needs methods to accept these or a more direct way to init with them.
      // For now, let's assume we might need to adapt QZoneService or create a new login path.
      
      // This is a simplified simulation of what _handleCredentialRedirect does.
      // Ideally, QZoneService would have a method like: completeLoginWithCookies(String pSkey, String uin, String? nickname)
      qzoneService.dangerouslySetPskeyAndUinForWebViewLogin(pSkey, uin, null /*nickname not easily available*/);
      await qzoneService.saveLoginInfoAfterWebView(pSkey, uin, null);


      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(nickname: qzoneService.loginNickname)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader(
        title: const Text('QQ登录'),
        // leading: FIconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()), // Temporarily removed FIconButton and leading
      ),
      child: Column(
        children: [
          if (_isLoadingPage)
            const LinearProgressIndicator(),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
              initialSettings: InAppWebViewSettings(
                userAgent: QZoneApiConstants.userAgent, // Used QZoneApiConstants.userAgent
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                thirdPartyCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
                transparentBackground: true,
                // set support multiple windows for pages that use target="_blank"
                supportMultipleWindows: false, 
              ),
              onWebViewCreated: (controller) {
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoadingPage = true;
                });
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  _isLoadingPage = false;
                });
                if (url != null) {
                  await _checkLoginSuccessAndExtractCookies(url.toString());
                }
              },
              onUpdateVisitedHistory: (controller, url, androidIsReload) async {
                 if (url != null) {
                  // await _checkLoginSuccessAndExtractCookies(url.toString());
                }
              },
              onReceivedHttpAuthRequest: (controller, challenge) async {
                return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
              },
              onReceivedClientCertRequest: (controller, challenge) async{
                // Providing an empty string for certificatePath as it seems to be required even for CANCEL.
                // Other specific platform parameters might not be needed for CANCEL.
                return ClientCertResponse(action: ClientCertResponseAction.CANCEL, certificatePath: ''); 
              },
               shouldOverrideUrlLoading: (controller, navigationAction) async {
                // Allow most navigations
                return NavigationActionPolicy.ALLOW;
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (kDebugMode) {
                  print("[WebView CONSOLE] ${consoleMessage.message}");
                }
              },
            ),
          ),
          // Optional: Display current URL for debugging
          // if (_currentUrl != null) Padding(padding: EdgeInsets.all(8), child: Text(_currentUrl!, style: TextStyle(fontSize: 10))), 
        ],
      ),
    );
  }
}

// Placeholder for QZoneService user agent constant (actual one is in QZoneService)
// This is just for the snippet to be self-contained for linting.
// In real code, you'd import and use QZoneApiConstants.userAgent or similar.
// extension QZoneServiceUserAgent on QZoneService { // Removed temporary extension
//     static const String qzoneUserAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36";
// } 