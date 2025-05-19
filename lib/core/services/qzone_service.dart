import 'dart:async';
import 'dart:convert'; // Import for jsonDecode
import 'dart:io'; // For HttpClient
import 'dart:math'; // For min function
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:qq_zone_flutter_downloader/core/constants.dart';
import 'package:qq_zone_flutter_downloader/core/models/login_qr_result.dart';
import 'package:qq_zone_flutter_downloader/core/models/login_poll_result.dart';
import 'package:qq_zone_flutter_downloader/core/models/album.dart'; // 导入 Album 模型
import 'package:qq_zone_flutter_downloader/core/models/photo.dart'; // 导入 Photo 模型
import 'package:qq_zone_flutter_downloader/core/models/friend.dart'; // 导入 Friend 模型
import 'package:qq_zone_flutter_downloader/core/models/qzone_api_exception.dart'; // 导入 QZoneApiException
import 'package:qq_zone_flutter_downloader/core/utils/qzone_algorithms.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart'; // Import CookieManager
import 'package:path_provider/path_provider.dart'; // 导入path_provider
import 'package:path/path.dart' as p; // 导入path包
import 'package:shared_preferences/shared_preferences.dart'; // 导入shared_preferences

class QZoneService {
  late Dio _dio;
  late CookieJar _cookieJar;
  String? _gTk;
  String? _loggedInUin; // QQ号, 不带 'o'
  String? _rawUin; // 原始uin, 可能带 'o'
  bool _isInitialized = false;

  QZoneService() {
    if (kDebugMode) {
      print("[QZoneService CONSTRUCTOR] QZoneService instance created. HashCode: $hashCode");
    }
    _initializeService();
  }

  Future<void> _initializeService() async {
    // 初始化使用持久化的CookieJar
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String appDocPath = appDocDir.path;
    final cookiePath = p.join(appDocPath, '.cookies');
    _cookieJar = PersistCookieJar(
      ignoreExpires: true, // 保存Cookie直到它们被明确清除或覆盖
      storage: FileStorage(cookiePath),
    );

    final options = BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': QZoneApiConstants.userAgent,
      },
      // Important for getLoginSig and getQRC to get Set-Cookie headers
      // Dio by default follows redirects, which is usually fine.
      // We need to ensure we can capture cookies from initial responses.
      // For the 'credential' step later, we'll need to handle redirects carefully.
      validateStatus: (status) {
        return status != null &&
            status < 500; // Accept most statuses to inspect headers
      },
    );
    _dio = Dio(options);

    // Add CookieManager interceptor
    _dio.interceptors.add(CookieManager(_cookieJar));

    // --- SSL Certificate Handling (for InsecureSkipVerify: true equivalent) ---
    // WARNING: This makes your app vulnerable to man-in-the-middle attacks.
    // Only use if absolutely necessary and you understand the risks.
    // Consider if there's a way to provide the correct CA chain instead.
    if (kDebugMode) {
      // Example: Only allow in debug mode
      try {
         final adapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.badCertificateCallback =
                  (X509Certificate cert, String host, int port) => true;
              return client;
            },
          );
        _dio.httpClientAdapter = adapter;
      } catch (e) {
        print(
            'Error setting IOHttpClientAdapter: $e. SSL verification might not be bypassed.');
      }
    }
    
    // Optional: Add logging interceptor for debugging
    _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: true));

    // 尝试从SharedPreferences恢复登录状态
    await _tryRestoreLoginState();
    _isInitialized = true;
  }

  Future<bool> _tryRestoreLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _gTk = prefs.getString('g_tk');
      _loggedInUin = prefs.getString('logged_in_uin');
      _rawUin = prefs.getString('raw_uin');
      
      if (_gTk != null && _loggedInUin != null) {
        if (kDebugMode) {
          print("[QZoneService] 成功恢复登录状态: g_tk=$_gTk, uin=$_loggedInUin");
        }
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 恢复登录状态失败: $e");
      }
    }
    return false;
  }

  Future<void> _saveLoginState() async {
    try {
      if (_gTk != null && _loggedInUin != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('g_tk', _gTk!);
        await prefs.setString('logged_in_uin', _loggedInUin!);
        if (_rawUin != null) {
          await prefs.setString('raw_uin', _rawUin!);
        }
        if (kDebugMode) {
          print("[QZoneService] 成功保存登录状态");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 保存登录状态失败: $e");
      }
    }
  }

  Future<void> clearLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('g_tk');
      await prefs.remove('logged_in_uin');
      await prefs.remove('raw_uin');
      _gTk = null;
      _loggedInUin = null;
      _rawUin = null;
      
      // 清除所有Cookie
      await _cookieJar.deleteAll();
      
      if (kDebugMode) {
        print("[QZoneService] 已清除登录状态和Cookie");
      }
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 清除登录状态失败: $e");
      }
    }
  }

  // 判断用户是否已登录
  bool get isLoggedIn => _gTk != null && _loggedInUin != null;
  
  // 判断服务是否已初始化完成
  bool get isInitialized => _isInitialized;

  String? _extractCookieValue(Headers headers, String cookieName) {
    final setCookieHeader = headers.map['set-cookie'];
    if (setCookieHeader != null) {
      for (String cookieStr in setCookieHeader) {
        if (cookieStr.startsWith('$cookieName=')) {
          final parts = cookieStr.split(';');
          final valuePart = parts[0].substring(cookieName.length + 1);
          return valuePart;
        }
      }
    }
    return null;
  }

  // Getter for g_tk (read-only from outside)
  String? get gTk => _gTk;
  // Getter for loggedInUin (read-only from outside)
  String? get loggedInUin => _loggedInUin;

  Future<void> _handleCredentialRedirect(String redirectUrl) async {
    if (kDebugMode) {
      print("[QZoneService DEBUG] === Starting _handleCredentialRedirect ===");
      print("[QZoneService DEBUG] redirectUrl: $redirectUrl");
    }
    try {
      Response response = await _dio.get(
        redirectUrl,
        options: Options(
          followRedirects: false, // Do not follow redirects automatically
          validateStatus: (status) { 
            return status != null && status < 400; // Allow 3xx statuses
          },
        ),
      );

      if (kDebugMode) {
        print("[QZoneService DEBUG] Credential redirect response status: ${response.statusCode}");
        print("[QZoneService DEBUG] Credential redirect response headers: ${response.headers.map}"); // Print all headers
      }

      final cookiesForRedirectUrl = await _cookieJar.loadForRequest(Uri.parse(redirectUrl));
      if (kDebugMode) {
        print("[QZoneService DEBUG] Cookies loaded for $redirectUrl from _cookieJar:");
        for (var c in cookiesForRedirectUrl) {
          print("[QZoneService DEBUG]   ${c.name}=${c.value}");
        }
      }
      
      String? pSkey;
      String? pUin; 
      String? skeyForFallback;

      for (var cookie in cookiesForRedirectUrl) {
        if (cookie.name == 'p_skey') {
          pSkey = cookie.value;
        }
        if (cookie.name == 'skey') { // Also capture skey for fallback
          skeyForFallback = cookie.value;
        }
        if (cookie.name == 'p_uin' || cookie.name == 'uin') {
            if (cookie.name == 'p_uin' || pUin == null) { 
                 pUin = cookie.value;
            }
        }
      }

      if (kDebugMode) {
        print("[QZoneService DEBUG] Extracted p_skey: $pSkey");
        print("[QZoneService DEBUG] Extracted skey (for fallback): $skeyForFallback");
        print("[QZoneService DEBUG] Extracted p_uin/uin: $pUin");
      }

      if (pSkey != null && pSkey.isNotEmpty) {
        _gTk = QZoneAlgorithms.calculateGtk(pSkey);
        if (kDebugMode) {
          print("[QZoneService DEBUG] Calculated g_tk: $_gTk from p_skey: $pSkey");
        }
      } else if (skeyForFallback != null && skeyForFallback.isNotEmpty) { // Fallback to skey
        _gTk = QZoneAlgorithms.calculateGtk(skeyForFallback);
        if (kDebugMode) {
          print("[QZoneService DEBUG] Calculated g_tk: $_gTk from skey: $skeyForFallback (p_skey was missing)");
        }
      } else {
        if (kDebugMode) {
            print("[QZoneService ERROR] Failed to calculate g_tk: p_skey and skey not found in cookies after redirect.");
        }
        throw QZoneApiException("Failed to calculate g_tk: p_skey and skey not found in cookies after login redirect.");
      }

      if (pUin != null && pUin.isNotEmpty) {
        _rawUin = pUin;
        // Store the uin without the 'o' prefix if it exists
        _loggedInUin = pUin.startsWith('o') ? pUin.substring(1) : pUin;
         if (kDebugMode) {
          print("[QZoneService] Logged in UIN: $_loggedInUin (raw: $_rawUin)");
        }
      } else {
        throw QZoneApiException("Failed to retrieve UIN from cookies after login redirect.");
      }
      
      // 保存登录状态
      await _saveLoginState();

    } on DioException catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] DioException in _handleCredentialRedirect: ${e.message}, Response: ${e.response?.data}");
      }
      throw QZoneApiException("Network error during credential handling: ${e.message}", underlyingError: e);
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] Unexpected error in _handleCredentialRedirect: ${e.toString()}");
      }
      throw QZoneApiException("Unexpected error during credential handling: ${e.toString()}", underlyingError: e);
    }
    if (kDebugMode) {
      print("[QZoneService DEBUG] === Finished _handleCredentialRedirect === gTk: $_gTk, loggedInUin: $_loggedInUin");
    }
  }

  /// Step 1 & 2 of Login: Get QR Code image, loginSig, and qrsig.
  Future<LoginQrResult> getLoginQrImage() async {
    String? loginSig;
    String? qrsig;
    Uint8List? qrImageBytes;

    try {
      // 1. Get login_sig
      // print('Fetching login_sig from: ${QZoneApiConstants.loginSigUrl}');
      Response sigResponse = await _dio.get(
        QZoneApiConstants.loginSigUrl,
        options: Options(
          // We don't need the body, just the headers
          responseType: ResponseType.plain, 
        ),
      );
      
      // print('Login_sig response status: ${sigResponse.statusCode}');
      // print('Login_sig response headers: ${sigResponse.headers}');

      loginSig = _extractCookieValue(sigResponse.headers, 'pt_login_sig');
      if (loginSig == null) {
        // Try to get from cookie jar as a fallback if interceptor already processed it
        final cookies = await _cookieJar
            .loadForRequest(Uri.parse(QZoneApiConstants.loginSigUrl));
        loginSig = cookies
            .firstWhere((c) => c.name == 'pt_login_sig',
                orElse: () => Cookie('', ''))
            .value;
        if (loginSig.isEmpty) {
          throw QZoneLoginException(
              'Failed to retrieve pt_login_sig from cookies. Headers: ${sigResponse.headers}');
        }
      }
      // print('Extracted login_sig: $loginSig');

      // 2. Get QR code image and qrsig
      final qrShowUrl = QZoneApiConstants.getQrShowUrl();
      // print('Fetching QR code from: $qrShowUrl');
      Response qrResponse = await _dio.get(
        qrShowUrl,
        options: Options(
          responseType: ResponseType.bytes, // Get image as bytes
        ),
      );

      // print('QR code response status: ${qrResponse.statusCode}');
      // print('QR code response headers: ${qrResponse.headers}');
      
      if (qrResponse.statusCode != 200 || qrResponse.data == null) {
        throw QZoneLoginException(
            'Failed to download QR code image. Status: ${qrResponse.statusCode}');
      }
      qrImageBytes = Uint8List.fromList(qrResponse.data as List<int>);

      qrsig = _extractCookieValue(qrResponse.headers, 'qrsig');
      if (qrsig == null) {
        // Try to get from cookie jar as a fallback
        final cookies = await _cookieJar
            .loadForRequest(Uri.parse(QZoneApiConstants.getQrShowUrl()));
        qrsig = cookies
            .firstWhere((c) => c.name == 'qrsig', orElse: () => Cookie('', ''))
            .value;
        if (qrsig.isEmpty) {
          throw QZoneLoginException(
              'Failed to retrieve qrsig from QR code response cookies. Headers: ${qrResponse.headers}');
        }
      }
      // print('Extracted qrsig: $qrsig');

      return LoginQrResult(
        qrImageBytes: qrImageBytes,
        loginSig: loginSig,
        qrsig: qrsig,
      );
    } on DioException catch (e) {
      // print('DioError in getLoginQrImage: ${e.message}');
      // if (e.response != null) {
      //   print('DioError response data: ${e.response?.data}');
      //   print('DioError response headers: ${e.response?.headers}');
      // }
      throw QZoneLoginException(
          'Network error while fetching QR login data: ${e.message}',
          underlyingError: e);
    } catch (e) {
      // print('Generic error in getLoginQrImage: $e');
      throw QZoneLoginException(
          'Unexpected error while fetching QR login data: ${e.toString()}',
          underlyingError: e);
    }
  }

  String calculatePtqrtoken(String qrsig) {
    return QZoneAlgorithms.calculatePtqrtoken(qrsig);
  }

  /// Polls the QQ login server to check QR code scan status.
  /// Returns a stream of LoginPollResult. Completes when login is successful or QR is invalid.
  Stream<LoginPollResult> pollLoginStatus({
    required String loginSig,
    required String qrsig,
    required String ptqrtoken,
  }) {
    late StreamController<LoginPollResult> controller;
    Timer? timer;
    bool isPolling = true;

    Future<void> checkStatus() async {
      if (!isPolling) return;

      final url = QZoneApiConstants.getPtQrLoginUrl(
          ptqrtoken: ptqrtoken, loginSig: loginSig);
      
      try {
        final response = await _dio.get(
          url,
          options: Options(
            headers: {'Cookie': 'qrsig=$qrsig;'},
            responseType: ResponseType.plain,
          ),
        );

        final String responseBody = response.data.toString();
        final regex = RegExp(r"ptuiCB\((.*)\)");
        final match = regex.firstMatch(responseBody);

        if (match != null && match.groupCount >= 1) {
          final argsString = match.group(1)!;
          final args = argsString.split("','").map((arg) {
            String currentArg = arg;
            if (currentArg.startsWith("'")) {
              currentArg = currentArg.substring(1);
            }
            if (currentArg.endsWith("'")) {
              currentArg = currentArg.substring(0, currentArg.length - 1);
            }
            return currentArg;
          }).toList();
          
          if (args.isNotEmpty) {
            final statusCode = args[0];
            final message = args.length > 4 ? args[4] : "No message";
            LoginPollResult result;

            switch (statusCode) {
              case '0': 
                isPolling = false;
                timer?.cancel();
                final redirectUrl = args.length > 2 ? args[2] : null;
                final nickname = args.length > 5 ? args[5] : null;

                if (redirectUrl != null) {
                  // IMPORTANT: Call _handleCredentialRedirect BEFORE adding to stream,
                  // so that g_tk and uin are available when HomeScreen loads.
                  _handleCredentialRedirect(redirectUrl).then((_) {
                    if (kDebugMode) {
                        print("[QZoneService DEBUG] _handleCredentialRedirect successful. Setting LoginPollStatus.loginSuccess.");
                    }
                result = LoginPollResult(
                  status: LoginPollStatus.loginSuccess,
                      redirectUrl: redirectUrl,
                      nickname: nickname,
                  message: message,
                );
                controller.add(result);
                    controller.close();
                  }).catchError((e) {
                    if (kDebugMode) {
                      print("[QZoneService ERROR] _handleCredentialRedirect failed: $e. Setting LoginPollStatus.error.");
                    }
                    result = LoginPollResult(
                      status: LoginPollStatus.error, 
                      message: "登录凭证处理失败: ${e.toString()}"
                    );
                    controller.add(result);
                    controller.close();
                  });
                } else {
                  result = LoginPollResult(
                    status: LoginPollStatus.error, // Or a more specific error status
                    message: "登录成功但未获取到跳转链接",
                    nickname: nickname,
                  );
                  controller.add(result);
                  controller.close();
                }
                // Do not add to controller here directly, it's handled in .then() or .catchError()
                break;
              case '65': 
                isPolling = false;
                timer?.cancel();
                result = LoginPollResult(
                    status: LoginPollStatus.qrInvalidOrExpired,
                    message: message);
                controller.add(result);
                await controller.close(); 
                break;
              case '66': 
                result = LoginPollResult(
                    status: LoginPollStatus.qrNotScanned, message: message);
                controller.add(result);
                break;
              case '67': 
                result = LoginPollResult(
                    status: LoginPollStatus.qrScannedWaitingConfirmation,
                    message: message);
                controller.add(result);
                break;
              default:
                result = LoginPollResult(
                    status: LoginPollStatus.unknown,
                    message:
                        "Unknown status code: $statusCode. Full args: $args");
                controller.add(result);
            }
            return; 
          }
        }
        controller.add(LoginPollResult(
            status: LoginPollStatus.error,
            message: "Failed to parse ptuiCB response: $responseBody"));
      } on DioException catch (e) {
        controller.add(LoginPollResult(
            status: LoginPollStatus.error,
            message: "Network error during polling: ${e.message}"));
      } catch (e) {
        controller.add(LoginPollResult(
            status: LoginPollStatus.error,
            message: "Unexpected error during polling: ${e.toString()}"));
        isPolling = false; 
        timer?.cancel();
        await controller.close();
      }
    }

    controller = StreamController<LoginPollResult>(
      onListen: () {
        checkStatus(); 
        timer =
            Timer.periodic(const Duration(seconds: 3), (_) => checkStatus());
      },
      onCancel: () {
        isPolling = false;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  Future<List<Album>> getAlbumList({String? targetUin}) async {
    if (!isLoggedIn) {
      throw QZoneApiException('未登录，请先登录');
    }

    final uin = targetUin ?? _loggedInUin;
    const String callbackFun = "shine"; // 与 Go 代码一致
    const String callbackName = "${callbackFun}_Callback"; // 与 Go 代码一致

    try {
      if (kDebugMode) {
        print("[QZoneService DEBUG] 开始获取相册列表 (主API)");
        print("[QZoneService DEBUG] 请求参数: targetUin=$targetUin, loggedInUin=$_loggedInUin, gTk=$_gTk");
      }

      // 获取完整Cookie
      final cookieString = await _getFullCookieString('https://user.qzone.qq.com/');

      // 主API - 相册列表V3
      final response = await _dio.get(
        'https://h5.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/fcg_list_album_v3',
        queryParameters: {
          'g_tk': _gTk,
          'hostUin': uin,
          'uin': _loggedInUin,
          'appid': '4',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'source': 'qzone',
          'plat': 'qzone',
          'format': 'jsonp',
          'notice': '0',
          'filter': '1',
          'handset': '4',
          'pageNumModeSort': '40',
          'pageNumModeClass': '15',
          'needUserInfo': '1',
          'idcNum': '4',
          'mode': '2',
          'pageStart': '0',
          'pageNum': '30',
          'callback': callbackName,
          'callbackFun': callbackFun,
          '_': DateTime.now().millisecondsSinceEpoch.toString(), // 添加时间戳防止缓存
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
            'Referer': 'https://user.qzone.qq.com/$uin',
            'Origin': 'https://user.qzone.qq.com',
            'Cookie': cookieString,
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      if (kDebugMode) {
        print("[QZoneService DEBUG] 主API响应状态码: ${response.statusCode}");
      }

      if (response.data != null && response.data.toString().isNotEmpty) {
        String responseData = response.data.toString().trim(); // Trim the whole string

        if (kDebugMode) {
          print("[QZoneService DEBUG] 主API响应体 (原始, trimmed): $responseData");
        }

        final String expectedPrefix = "$callbackName("; // e.g., "shine_Callback("

        if (responseData.startsWith(expectedPrefix)) {
          int lastParenIndex = responseData.lastIndexOf(')');
          if (lastParenIndex > expectedPrefix.length - 1) { // Ensure ')' is after the prefix
            responseData = responseData.substring(expectedPrefix.length, lastParenIndex);
          } else {
            if (kDebugMode) {
              print("[QZoneService WARN] 主API: JSONP prefix found, but closing ')' was not found or in unexpected position.");
            }
            // If stripping fails, responseData remains as is, potentially causing jsonDecode error later
          }
        } else if (responseData.startsWith("(") && responseData.endsWith(")")) {
           // Fallback for simple "({...})" case, unlikely if the error mentions callbackName
           responseData = responseData.substring(1, responseData.length - 1);
        }
        // Else: No known JSONP wrapper detected, assume responseData is (or should be) plain JSON.

        if (kDebugMode) {
          print("[QZoneService DEBUG] 主API响应体 (处理后 for jsonDecode): $responseData");
        }
        
        try {
        final jsonData = jsonDecode(responseData);
        if (jsonData['code'] == 0) {
          final List<Album> albums = [];
          final data = jsonData['data']?['albumList']; // 安全访问
          
          if (kDebugMode) {
            print("[QZoneService DEBUG] 解析到的相册数据: $data");
          }
          
          if (data != null && data is List) {
            for (var item in data) {
              if (kDebugMode) {
                print("[QZoneService DEBUG] 正在处理相册: ${item['name']}");
              }
              
              albums.add(Album.fromJson(item)); // 使用fromJson构造函数
            }
            
            if (kDebugMode) {
              print("[QZoneService DEBUG] 成功解析相册数量: ${albums.length}");
            }
            return albums;
          } else {
             if (kDebugMode) {
                print("[QZoneService WARN] 主API返回成功，但albumList为空或格式不正确: $data");
             }
          }
        } else {
          if (kDebugMode) {
            print("[QZoneService ERROR] 主API返回错误码: ${jsonData['code']}, 消息: ${jsonData['message']}");
          }
          // 不再立即抛出，而是尝试备用API
          }
        } catch (e) {
          if (kDebugMode) {
            print("[QZoneService ERROR] 主API JSON解析错误: $e");
          }
          // 继续尝试备用API
        }
      } else {
         if (kDebugMode) {
            print("[QZoneService WARN] 主API响应体为空");
         }
      }

      // 如果第一个API失败或未返回有效数据，尝试备用API (v2)
      if (kDebugMode) {
        print("[QZoneService DEBUG] 主API未成功或数据无效，尝试备用API (v2)");
      }
      
      // 备用API 1 - 相册列表V2
      final backupResponse = await _dio.get(
        'https://h5.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/fcg_list_album_v2',
        queryParameters: { 
          'g_tk': _gTk,
          'hostUin': uin,
          'uin': _loggedInUin,
          'format': 'jsonp',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'handset': '4',
          'pageNumModeSort': '40',
          'needUserInfo': '1',
          'callback': callbackName,
          'callbackFun': callbackFun,
          '_': DateTime.now().millisecondsSinceEpoch.toString(), // 添加时间戳防止缓存
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
            'Referer': 'https://user.qzone.qq.com/$uin',
            'Origin': 'https://user.qzone.qq.com',
            'Cookie': cookieString,
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      if (kDebugMode) {
        print("[QZoneService DEBUG] 备用API响应状态码: ${backupResponse.statusCode}");
      }

      if (backupResponse.data != null && backupResponse.data.toString().isNotEmpty) {
        String backupResponseData = backupResponse.data.toString().trim(); // Trim the whole string

        if (kDebugMode) {
          print("[QZoneService DEBUG] 备用API响应体 (原始, trimmed): $backupResponseData");
        }

        final String expectedPrefix = "$callbackName("; // e.g., "shine_Callback("

        if (backupResponseData.startsWith(expectedPrefix)) {
          int lastParenIndex = backupResponseData.lastIndexOf(')');
          if (lastParenIndex > expectedPrefix.length - 1) { // Ensure ')' is after the prefix
            backupResponseData = backupResponseData.substring(expectedPrefix.length, lastParenIndex);
          } else {
            if (kDebugMode) {
              print("[QZoneService WARN] 备用API: JSONP prefix found, but closing ')' was not found or in unexpected position.");
            }
          }
        } else if (backupResponseData.startsWith("(") && backupResponseData.endsWith(")")) {
           backupResponseData = backupResponseData.substring(1, backupResponseData.length - 1);
        }

        if (kDebugMode) {
          print("[QZoneService DEBUG] 备用API响应体 (处理后 for jsonDecode): $backupResponseData");
        }

        try {
        final jsonData = jsonDecode(backupResponseData);
        if (jsonData['code'] == 0) {
          final List<Album> albums = [];
          // v2 的数据结构可能是 data.album，而不是 data.albumList
          final data = jsonData['data']?['album'] ?? jsonData['data']?['albumList']; 
          
          if (kDebugMode) {
            print("[QZoneService DEBUG] 备用API解析到的相册数据: $data");
          }
          
          if (data != null && data is List) {
            for (var item in data) {
              albums.add(Album.fromJson(item)); // 使用fromJson构造函数
            }
            if (kDebugMode) {
              print("[QZoneService DEBUG] 备用API成功解析相册数量: ${albums.length}");
            }
            return albums;
          } else {
            if (kDebugMode) {
                print("[QZoneService WARN] 备用API返回成功，但albumList/album为空或格式不正确: $data");
             }
          }
        } else {
          if (kDebugMode) {
            print("[QZoneService ERROR] 备用API返回错误码: ${jsonData['code']}, 消息: ${jsonData['message']}");
          }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[QZoneService ERROR] 备用API JSON解析错误: $e");
          }
        }
      }
      
      // 备用API 2 - 使用qqzone-web的API
      try {
        final webBackupResponse = await _dio.get(
          'https://user.qzone.qq.com/proxy/domain/r.qzone.qq.com/cgi-bin/user/qzone_get_myself',
          queryParameters: {
            'uin': targetUin ?? _loggedInUin,
            'g_tk': _gTk,
            'qzonetoken': '',
            'format': 'jsonp',
            'callback': 'callback_${DateTime.now().millisecondsSinceEpoch}',
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://user.qzone.qq.com/$uin',
              'Cookie': cookieString,
              'Accept': '*/*',
              'Accept-Encoding': 'gzip, deflate, br',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            },
          ),
        );
        
        if (webBackupResponse.statusCode == 200 && webBackupResponse.data != null) {
          String webData = webBackupResponse.data.toString();
          final callbackMatch = RegExp(r'callback_\d+\((.*)\)').firstMatch(webData);
          if (callbackMatch != null && callbackMatch.groupCount >= 1) {
            final jsonString = callbackMatch.group(1);
            if (jsonString != null) {
              final jsonData = jsonDecode(jsonString);
              if (jsonData['code'] == 0 && jsonData['data'] != null) {
                // 创建一个基本的相册列表，至少包含"我的相册"
                final List<Album> basicAlbums = [];
                final now = DateTime.now();
                basicAlbums.add(Album(
                  id: '0', // 默认ID
                  name: '默认相册',
                  desc: '系统创建的默认相册',
                  coverUrl: null,
                  createTime: now,
                  modifyTime: now,
                  photoCount: 0,
                ));
                return basicAlbums;
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print("[QZoneService ERROR] Web备用API调用失败: $e");
        }
      }

      // 最后的备选方案 - 尝试从其他API获取信息
      try {
        final lastResponse = await _dio.get(
          'https://user.qzone.qq.com/proxy/domain/r.qzone.qq.com/cgi-bin/main_page_cgi',
          queryParameters: {
            'uin': targetUin ?? _loggedInUin,
            'param': '3',
            'g_tk': _gTk,
            'qzonetoken': '',
            'format': 'jsonp',
            'callback': 'callback_${DateTime.now().millisecondsSinceEpoch}',
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://user.qzone.qq.com/',
              'Cookie': cookieString,
              'Accept': '*/*',
              'Accept-Encoding': 'gzip, deflate, br',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            },
          ),
        );
        
        if (lastResponse.statusCode == 200) {
          // 创建一个基本的相册列表，至少让用户能看到一个相册入口
          final List<Album> fallbackAlbums = [];
          final now = DateTime.now();
          fallbackAlbums.add(Album(
            id: '0', // 默认ID
            name: '默认相册',
            desc: '由于API限制，无法获取完整相册列表',
            coverUrl: null,
            createTime: now,
            modifyTime: now,
            photoCount: 0,
          ));
          return fallbackAlbums;
        }
      } catch (e) {
        if (kDebugMode) {
          print("[QZoneService ERROR] 最后备选API调用失败: $e");
        }
      }

      if (kDebugMode) {
        print("[QZoneService ERROR] 主API和备用API均失败或未返回有效数据。");
      }
      throw QZoneApiException('获取相册列表失败，主API和备用API均未返回有效数据');
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService FATAL] 获取相册列表异常: $e");
        if (e is DioException) {
          print("[QZoneService FATAL] DioException: ${e.response?.data}, ${e.message}");
        }
      }
      
      // 返回一个友好的错误提示相册，而不是直接抛出异常
      if (targetUin != null) {
        final now = DateTime.now();
        return [
          Album(
            id: 'error',
            name: '暂时无法获取相册',
            desc: '该好友的相册可能设置了访问权限或网络连接问题',
            coverUrl: null,
            createTime: now,
            modifyTime: now,
            photoCount: 0,
          )
        ];
      }
      
      throw QZoneApiException('获取相册列表异常: $e');
    }
  }

  Future<List<Photo>> getPhotoList({
    required String albumId,
    String? targetUin,
    int retryCount = 2,
    int pageStart = 0
  }) async {
    if (!isLoggedIn) {
      throw QZoneApiException("未登录，请先登录");
    }

    final String hostUin = targetUin ?? _loggedInUin!;
    final String uin = _loggedInUin!;
    final String gtk = _gTk!;
    
    if (kDebugMode) {
      print("[QZoneService DEBUG] 开始获取相册照片");
      print("[QZoneService DEBUG] 参数: albumId=$albumId, targetUin=$targetUin");
      print("[QZoneService DEBUG] 登录信息: uin=$uin, hostUin=$hostUin, gtk=$gtk");
    }
    
    List<Photo> allPhotos = [];
    int currentPageStart = pageStart;
    const int pageNum = 30;
    bool hasMore = true;
    int currentRetry = 0;

    while (hasMore) {
      try {
        // 构建请求参数
        final Map<String, dynamic> params = {
          'g_tk': gtk,
          'hostUin': hostUin,
          'uin': uin,
          'appid': '4',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'source': 'qzone',
          'plat': 'qzone',
          'format': 'json',
          'notice': '0',
          'filter': '1',
          'handset': '4',
          'topicId': albumId,
          'pageStart': currentPageStart.toString(),
          'pageNum': pageNum.toString(),
          'needUserInfo': '1',
          'singleurl': '1',
          'mode': '0',
          't': DateTime.now().millisecondsSinceEpoch.toString(), // 添加时间戳防止缓存
          'sortOrder': '0', // 添加排序参数
          'viewMode': '0', // 添加查看模式
          'ownerMode': '1', // 添加所有者模式
          'PST': '1', // 添加PST参数
        };

        final uri = Uri.parse('https://h5.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/cgi_list_photo').replace(queryParameters: params);
        
        if (kDebugMode) {
          print("[QZoneService DEBUG] 请求URL: ${uri.toString()}");
        }

        Response response = await _dio.get(
          uri.toString(),
          options: Options(
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
              'Referer': 'https://user.qzone.qq.com/',
              'Cookie': await _getFullCookieString('https://user.qzone.qq.com/'),
              'Accept': '*/*',
              'Accept-Encoding': 'gzip, deflate, br, zstd',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
            responseType: ResponseType.plain,
          ),
        );

        if (kDebugMode) {
          print("[QZoneService DEBUG] 响应状态码: ${response.statusCode}");
          print("[QZoneService DEBUG] 响应头: ${response.headers}");
        }

        String responseBody = response.data.toString().trim();
        
        // 检查是否403错误
        if (response.statusCode == 403) {
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService DEBUG] 获取照片列表收到403错误，重试第$currentRetry次");
            }
            await Future.delayed(const Duration(seconds: 2));
            continue;
          } else {
            throw QZoneApiException("获取照片列表失败，服务器返回403禁止访问");
          }
        }

        // 解析JSONP响应
        int startIndex = responseBody.indexOf('(');
        int endIndex = responseBody.lastIndexOf(')');

        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          responseBody = responseBody.substring(startIndex + 1, endIndex);
        }
        
        if (kDebugMode) {
          print("[QZoneService DEBUG] 解析后的响应数据: $responseBody");
        }

        final Map<String, dynamic> jsonData = jsonDecode(responseBody);

        if (jsonData['code'] != 0) {
          // 特殊处理错误码-10805（回答错误，通常是加密相册）
          if (jsonData['code'] == -10805 && jsonData['data'] != null) {
            if (kDebugMode) {
              print("[QZoneService DEBUG] 检测到错误码-10805（加密相册），尝试继续处理数据");
            }
            // 继续处理，尝试从data中提取照片信息
          } else {
          throw QZoneApiException("获取照片列表失败. API错误: ${jsonData['message']} (code: ${jsonData['code']})");
          }
        }

        final Map<String, dynamic> data = jsonData['data'] ?? {};
        final List<dynamic>? photoListJson = data['photoList'] as List<dynamic>?;

        if (photoListJson != null) {
          for (var photoJsonUntyped in photoListJson) {
            if (photoJsonUntyped is Map<String, dynamic>) {
              final Map<String, dynamic> photoJson = photoJsonUntyped;
              
              if (kDebugMode) {
                print("[QZoneService DEBUG] 处理照片数据: $photoJson");
              }
              
              // 处理照片URL
              String? photoUrl = photoJson['url'] as String?;
              String? thumbUrl = photoJson['pre'] as String?;
              
              // 如果没有url，尝试从raw_url获取
              if (photoUrl == null || photoUrl.isEmpty) {
                photoUrl = photoJson['raw_url'] as String?;
              }
              
              // 如果还是没有，尝试从origin_url获取
              if (photoUrl == null || photoUrl.isEmpty) {
                photoUrl = photoJson['origin_url'] as String?;
              }
              
              // 判断是否为视频
              final bool isVideo = photoJson['is_video'] == 1 || 
                                  (photoJson['videoInfo'] != null) ||
                                  (photoJson['video_info'] != null);
              
              String? videoUrl;
              if (isVideo) {
                if (photoJson['videoInfo'] is Map<String, dynamic>) {
                  videoUrl = photoJson['videoInfo']['url'] as String?;
                } else if (photoJson['video_info'] is Map<String, dynamic>) {
                  videoUrl = photoJson['video_info']['url'] as String?;
                } else if (photoJson['video_url'] != null) {
                  videoUrl = photoJson['video_url'] as String?;
                } else if (photoJson['raw_url'] != null) {
                  videoUrl = photoJson['raw_url'] as String?;
                }
              }

              allPhotos.add(Photo(
                id: photoJson['lloc']?.toString() ?? photoJson['sloc']?.toString() ?? '',
                name: photoJson['name'] as String? ?? '未命名照片',
                desc: photoJson['desc'] as String?,
                url: photoUrl,
                thumbUrl: thumbUrl,
                uploadTime: (photoJson['uploadTime'] as num?)?.toInt(),
                width: (photoJson['width'] as num?)?.toInt(),
                height: (photoJson['height'] as num?)?.toInt(),
                isVideo: isVideo,
                videoUrl: videoUrl,
              ));
            }
          }
        }

        // 分页处理
        final int totalPhoto = (data['totalPhoto'] as num?)?.toInt() ?? 0;
        
        if (pageStart > 0) {
          hasMore = false;
        } else {
          if (currentPageStart + pageNum < (totalPhoto) && photoListJson != null && photoListJson.isNotEmpty) {
            currentPageStart += pageNum;
            hasMore = true;
          } else {
            hasMore = false;
          }
        }
        
        currentRetry = 0;
        
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print("[QZoneService ERROR] 获取照片列表失败: $e");
          print("[QZoneService ERROR] 堆栈: $stackTrace");
        }
        
        if (currentRetry < retryCount) {
          currentRetry++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        
        throw QZoneApiException('获取照片列表失败: ${e.toString()}');
      }
    }

    if (kDebugMode) {
      print("[QZoneService DEBUG] 成功获取照片数量: ${allPhotos.length}");
    }
    
    return allPhotos;
  }
  
  // 获取好友列表
  Future<List<Friend>> getFriendList() async {
    if (!isLoggedIn) {
      throw QZoneApiException('未登录，请先登录');
    }

    try {
      final response = await _dio.get(
        'https://h5.qzone.qq.com/proxy/domain/r.qzone.qq.com/cgi-bin/tfriend/friend_show_qqfriends.cgi',
        queryParameters: {
          'uin': _loggedInUin,
          'follow_flag': '0',
          'groupface_flag': '0',
          'fupdate': '1',
          'g_tk': _gTk,
          'qzonetoken': '',
          'format': 'json',
        },
        options: Options(
          headers: {
            'Referer': 'https://user.qzone.qq.com/$_loggedInUin/infocenter',
          },
        ),
      );

      if (response.data != null && response.data.toString().isNotEmpty) {
        final jsonData = jsonDecode(response.data.toString());
        if (jsonData['code'] == 0) {
          final List<Friend> friends = [];
          final data = jsonData['data']?['items'] ?? [];
          if (data is List) {
            for (var item in data) {
              if (item['uin'].toString() != _loggedInUin) { // 过滤掉自己
                friends.add(Friend(
                  uin: item['uin'].toString(),
                  nickname: item['name'] ?? '未知好友',
                  remark: item['remark'],
                  avatarUrl: item['img'],
                ));
              }
            }
          }
          return friends;
        }
      }

      // 如果第一个API失败，尝试备用API
      final backupResponse = await _dio.get(
        'https://h5.qzone.qq.com/proxy/domain/base.qzone.qq.com/cgi-bin/right/get_entryuinlist.cgi',
        queryParameters: {
          'uin': _loggedInUin,
          'fupdate': '1',
          'action': '1',
          'g_tk': _gTk,
          'qzonetoken': '',
          'format': 'json',
        },
        options: Options(
          headers: {
            'Referer': 'https://user.qzone.qq.com/$_loggedInUin/infocenter',
          },
        ),
      );

      if (backupResponse.data != null && backupResponse.data.toString().isNotEmpty) {
        final jsonData = jsonDecode(backupResponse.data.toString());
        if (jsonData['code'] == 0) {
          final List<Friend> friends = [];
          final data = jsonData['data']?['uinlist'] ?? [];
          if (data is List) {
            for (var item in data) {
              if (item['uin'].toString() != _loggedInUin) { // 过滤掉自己
                friends.add(Friend(
                  uin: item['uin'].toString(),
                  nickname: item['name'] ?? '未知好友',
                  remark: item['remark'],
                  avatarUrl: item['avatar'],
                ));
              }
            }
          }
          return friends;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 获取好友列表失败: $e");
      }
      throw QZoneApiException('获取好友列表失败: $e');
    }

    throw QZoneApiException('获取好友列表失败');
  }
  
  // 实现文件下载功能
  Future<Map<String, dynamic>> downloadFile({
    required String url, 
    required String savePath, 
    required String filename,
    bool isVideo = false,
    Function(int received, int total)? onProgress
  }) async {
    if (_loggedInUin == null || _gTk == null) {
      throw QZoneApiException("Not logged in or g_tk/uin not available. Cannot download file.");
    }
    
    try {
      // 创建保存目录
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      // 构建文件保存路径
      final filePath = p.join(savePath, filename);
      
      // 设置请求头
      final headers = {
        'User-Agent': QZoneApiConstants.userAgent,
        'Referer': 'https://user.qzone.qq.com/',
        'Cookie': await _getFullCookieString('https://user.qzone.qq.com/'),
      };
      
      // 对于视频，添加额外的请求头
      if (isVideo) {
        headers['Accept'] = '*/*';
        headers['Accept-Encoding'] = 'identity;q=1, *;q=0';
        headers['Range'] = 'bytes=0-';
        headers['Sec-Fetch-Dest'] = 'video';
        headers['Sec-Fetch-Mode'] = 'no-cors';
        headers['Sec-Fetch-Site'] = 'cross-site';
      }
      
      if (kDebugMode) {
        print("[QZoneService] 开始下载文件: $url");
        print("[QZoneService] 保存到: $filePath");
        print("[QZoneService] 是否视频: $isVideo");
      }
      
      // 视频URL清理 - 确保正确的视频URL
      if (isVideo && url.contains('?')) {
        // 有些视频URL带有多余的查询参数，尝试清理
        final uri = Uri.parse(url);
        if (uri.path.endsWith('.mp4') || uri.path.endsWith('.mov')) {
          // 尝试使用纯路径，去掉查询参数
          url = '${uri.scheme}://${uri.host}${uri.path}';
          if (kDebugMode) {
            print("[QZoneService] 清理后的视频URL: $url");
          }
        }
      }
      
      // 发起下载请求
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          followRedirects: true,
          validateStatus: (status) {
            return status != null && status < 500;
          }
        ),
        onReceiveProgress: (received, total) {
          if (kDebugMode && total > 0 && received % (total ~/ 10) == 0) {
            if (kDebugMode) {
              print("[QZoneService] 下载进度: ${(received / total * 100).toStringAsFixed(1)}% ($received/$total)");
            }
          }
          if (onProgress != null) {
            onProgress(received, total);
          }
        },
      );
      
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw QZoneApiException('下载失败：服务器响应状态码 ${response.statusCode}');
      }
      
      // 检查是否获取到了正确的内容
      if (isVideo) {
        // 检查Content-Type是否为视频类型
        final contentType = response.headers.value('content-type');
        if (kDebugMode) {
          print("[QZoneService] 视频下载响应Content-Type: $contentType");
          print("[QZoneService] 响应大小: ${response.data.length} 字节");
        }
        
        // QQ空间的视频响应类型可能不规范，放宽检查条件
        bool isLikelyVideo = false;
        
        // 检查文件头部特征
        if (response.data is List<int> && response.data.length > 16) {
          final bytes = response.data as List<int>;
          final fileSignature = bytes.sublist(0, min(16, bytes.length));
          
          // MP4文件头特征：以'ftyp'开头或包含特定字节序列
          if (bytes.length > 8) {
            if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) { // 'ftyp'
              isLikelyVideo = true;
              if (kDebugMode) {
                print("[QZoneService] 检测到MP4文件特征(ftyp)");
              }
            }
          }
        }
        
        // 通过内容类型判断
        if (contentType != null && 
           (contentType.contains('video') || 
            contentType.contains('octet-stream') || 
            contentType.contains('mp4') ||
            contentType.contains('binary'))) {
          isLikelyVideo = true;
        }
        
        // 通过URL判断
        if (url.toLowerCase().endsWith('.mp4') || url.toLowerCase().contains('/video/')) {
          isLikelyVideo = true;
        }
        
        // 通过文件大小初步判断
        if (response.data.length > 500 * 1024) { // 大于500KB可能是视频
          isLikelyVideo = true;
        }
        
        if (!isLikelyVideo) {
          if (kDebugMode) {
            print("[QZoneService WARNING] 可能不是视频文件: Content-Type=$contentType, 大小=${response.data.length}字节");
          }
          throw QZoneApiException("下载的不是视频文件，可能是缩略图或空文件。尝试检查视频URL。");
        }
      }
      
      if (kDebugMode) {
        print("[QZoneService] 下载完成，大小: ${response.data.length} 字节");
        final contentType = response.headers.value('content-type');
        print("[QZoneService] Content-Type: $contentType");
      }
      
      // 写入文件
      final file = File(filePath);
      await file.writeAsBytes(response.data, flush: true);
      
      // 检查文件是否存在
      if (!await file.exists()) {
        throw QZoneApiException("下载失败：文件未创建");
      }
      
      // 获取文件大小
      final fileSize = await file.length();
      
      if (kDebugMode) {
        print("[QZoneService] 文件已保存: $filePath ($fileSize 字节)");
      }
      
      // 返回下载结果
      return {
        'path': filePath,
        'filename': filename,
        'size': fileSize,
        'isVideo': isVideo,
      };
    } on DioException catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 下载文件失败 DioException: ${e.message}");
        if (e.response != null) {
          print("[QZoneService ERROR] 响应状态码: ${e.response?.statusCode}");
          print("[QZoneService ERROR] 响应头: ${e.response?.headers}");
        }
      }
      throw QZoneApiException('下载文件失败: ${e.message}', underlyingError: e);
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 下载文件失败: $e");
      }
      throw QZoneApiException('下载文件失败: ${e.toString()}', underlyingError: e);
    }
  }
  
  // 获取视频真实URL
  Future<String?> getVideoRealUrl({
    required String photoId,
    required String albumId,
    String? targetUin,
  }) async {
    if (_loggedInUin == null || _gTk == null) {
      throw QZoneApiException("Not logged in or g_tk/uin not available. Cannot get video URL.");
    }

    final String hostUin = targetUin ?? _loggedInUin!;
    final String uin = _loggedInUin!;
    final String gtk = _gTk!;
    
    try {
      if (kDebugMode) {
        print("[QZoneService] 开始获取视频真实URL: photoId=$photoId, albumId=$albumId");
      }
      
      // 构建请求参数
      final Map<String, dynamic> params = {
        'g_tk': gtk,
        'callback': 'viewer_Callback',
        'topicId': albumId,
        'picKey': photoId,
        'cmtOrder': '1',
        'fupdate': '1',
        'plat': 'qzone',
        'source': 'qzone',
        'cmtNum': '0',
        'inCharset': 'utf-8',
        'outCharset': 'utf-8',
        'callbackFun': 'viewer',
        'uin': uin,
        'hostUin': hostUin,
        'appid': '4',
        'isFirst': '1',
      };

      final uri = Uri.parse('https://h5.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/cgi_floatview_photo_list_v2').replace(queryParameters: params);
      final url = uri.toString();

      Response response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': QZoneApiConstants.userAgent,
            'Referer': 'https://user.qzone.qq.com/',
            'Cookie': await _getFullCookieString('https://user.qzone.qq.com/'),
          }
        ),
      );

      String responseBody = response.data.toString().trim();
      
      // 解析JSONP响应
      int startIndex = responseBody.indexOf('(');
      int endIndex = responseBody.lastIndexOf(')');

      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        responseBody = responseBody.substring(startIndex + 1, endIndex);
        
        final jsonData = jsonDecode(responseBody);
        final data = jsonData['data'];
        
        if (data != null && data['photos'] is List && data['photos'].isNotEmpty) {
          final int picPosInPage = data['picPosInPage'] ?? 0;
          final photos = data['photos'];
          
          if (kDebugMode) {
            print("[QZoneService DEBUG] 找到视频信息: picPosInPage=$picPosInPage, 总共照片数=${photos.length}");
          }
          
          String? videoUrl;
          
          // 首先尝试在picPosInPage位置查找视频
          if (picPosInPage < photos.length) {
            final photo = photos[picPosInPage];
            
            // 详细记录视频信息以便调试
            if (kDebugMode) {
              print("[QZoneService DEBUG] 视频照片信息(精简): ${photo['is_video']}");
              if (photo['video_info'] != null) {
                print("[QZoneService DEBUG] video_info: ${photo['video_info']}");
              }
              
              // 检查可能的URL字段
              final possibleUrlFields = ['raw_url', 'video_url', 'url', 'origin_url', 'download_url'];
              for (final field in possibleUrlFields) {
                if (photo[field] != null) {
                  print("[QZoneService DEBUG] $field: ${photo[field]}");
                }
              }
            }
            
            // 1. 优先使用video_info内的URL
            if (photo['video_info'] != null) {
              final videoInfo = photo['video_info'];
              // 尝试多种可能的URL字段
              videoUrl = videoInfo['download_url'] ?? videoInfo['video_url'] ?? videoInfo['url'] ?? videoInfo['raw_url'];
            }
            
            // 2. 尝试videoInfo字段（旧版API）
            if (videoUrl == null && photo['videoInfo'] != null) {
              final videoInfo = photo['videoInfo'];
              videoUrl = videoInfo['url'] ?? videoInfo['download_url'] ?? videoInfo['video_url'] ?? videoInfo['raw_url'];
            }
            
            // 3. 尝试直接使用其他字段
            if (videoUrl == null) {
              // 按照优先级尝试各个字段
              videoUrl = photo['video_url'] ?? photo['download_url'];
            }
            
            // 4. 最后尝试raw_url或url字段，如果它们看起来像视频
            if (videoUrl == null) {
              final String? rawUrl = photo['raw_url'];
              if (rawUrl != null && (rawUrl.toLowerCase().endsWith('.mp4') || rawUrl.contains('video'))) {
                videoUrl = rawUrl;
              }
              
              if (videoUrl == null) {
                final String? normalUrl = photo['url'];
                if (normalUrl != null && (normalUrl.toLowerCase().endsWith('.mp4') || normalUrl.contains('video'))) {
                  videoUrl = normalUrl;
                }
              }
            }
          }
          
          // 如果在指定位置没找到，尝试遍历所有照片查找
          if (videoUrl == null) {
            for (final photo in photos) {
              if (photo['is_video'] == 1 || photo['videoInfo'] != null || photo['video_info'] != null) {
                if (kDebugMode) {
                  print("[QZoneService DEBUG] 在全部照片中找到视频");
                }
                
                if (photo['video_info'] != null) {
                  final videoInfo = photo['video_info'];
                  videoUrl = videoInfo['download_url'] ?? videoInfo['video_url'] ?? videoInfo['url'];
                } else if (photo['videoInfo'] != null) {
                  final videoInfo = photo['videoInfo'];
                  videoUrl = videoInfo['url'] ?? videoInfo['download_url'];
                } else if (photo['video_url'] != null) {
                  videoUrl = photo['video_url'];
                } else if (photo['raw_url'] != null && photo['raw_url'].toString().contains('.mp4')) {
                  videoUrl = photo['raw_url'];
                }
                
                if (videoUrl != null) break;
              }
            }
          }
          
          // 处理和验证找到的URL
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (kDebugMode) {
              print("[QZoneService DEBUG] 找到视频URL: $videoUrl");
            }
            
            // 清理URL中的多余参数
            if (videoUrl.contains('?') && videoUrl.contains('.mp4')) {
              final uri = Uri.parse(videoUrl);
              if (uri.path.endsWith('.mp4')) {
                // 只保留基本URL，去掉查询参数
                videoUrl = '${uri.scheme}://${uri.host}${uri.path}';
                if (kDebugMode) {
                  print("[QZoneService DEBUG] 清理后的视频URL: $videoUrl");
                }
              }
            }
            
            return videoUrl;
          }
        }
      }
      
      // 尝试备用方法构造视频URL
      final possibleUrl = 'https://photovideo.photo.qq.com/${photoId}.mp4';
      if (kDebugMode) {
        print("[QZoneService DEBUG] 尝试备用URL构造方法: $possibleUrl");
      }
      return possibleUrl;
      
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 获取视频真实URL失败: $e");
      }
      return null;
    }
  }
  
  // 下载整个相册
  Future<Map<String, dynamic>> downloadAlbum({
    required Album album,
    required String savePath,
    String? targetUin,
    bool skipExisting = true,
    Function(int current, int total, String message)? onProgress,
    Function(Map<String, dynamic> result)? onItemComplete,
  }) async {
    if (!isLoggedIn) {
      throw QZoneApiException('未登录，请先登录');
    }

    final String albumPath = '$savePath/${album.name}';
    await Directory(albumPath).create(recursive: true);

    // 获取相册中的所有照片（包括分页）
    if (onProgress != null) {
      onProgress(0, album.photoCount, "正在获取照片列表...");
    }
    
    List<Photo> allPhotos = [];
    int pageStart = 0;
    const int pageSize = 30;
    bool hasMore = true;
    
    try {
    // 分页获取所有照片
    while (hasMore) {
      if (onProgress != null) {
          onProgress(allPhotos.length, album.photoCount, "正在获取照片列表 (${allPhotos.length}/${album.photoCount})...");
      }
      
        List<Photo> pagePhotos;
        try {
          // 尝试使用主API获取照片
          pagePhotos = await getPhotoList(
        albumId: album.id, 
        targetUin: targetUin,
            retryCount: 2,
        pageStart: pageStart
      );
        } catch (e) {
          if (kDebugMode) {
            print("[QZoneService] 主API获取照片列表失败，尝试备用API: $e");
          }
          
          // 如果主API失败，尝试使用备用API
          try {
            pagePhotos = await _getPhotoListBackup(
              albumId: album.id,
              targetUin: targetUin
            );
            // 备用API不支持分页，所以获取后直接设置hasMore为false
            hasMore = false;
          } catch (backupError) {
            if (kDebugMode) {
              print("[QZoneService] 备用API也失败: $backupError");
            }
            throw QZoneApiException('无法获取相册照片: $e');
          }
        }
      
      if (pagePhotos.isEmpty) {
        // 如果返回空列表，表示没有更多照片
        hasMore = false;
      } else {
          // 添加新照片到总列表，过滤重复项
        final newPhotos = pagePhotos.where((newPhoto) => 
            !allPhotos.any((existingPhoto) => existingPhoto.id == newPhoto.id)
        ).toList();
        
        if (kDebugMode) {
            print("[QZoneService] 已获取照片: ${allPhotos.length}/${album.photoCount}, 本页新增: ${newPhotos.length}");
        }
          
          allPhotos.addAll(newPhotos);
        
        // 更新分页参数
        pageStart += pageSize;
        
          // 如果本页获取的新照片数量少于页大小，或者已经获取的总数达到或超过相册声明的照片数，则结束
          if (newPhotos.length < pageSize || allPhotos.length >= album.photoCount) {
            hasMore = false;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 获取完整照片列表失败: $e");
      }
      
      // 如果已经获取了一些照片，则继续下载这些照片
      if (allPhotos.isEmpty) {
        throw QZoneApiException('获取相册照片列表失败: $e');
      }
      
      if (onProgress != null) {
        onProgress(0, allPhotos.length, "获取完整列表失败，将下载已获取的${allPhotos.length}张照片");
      }
    }

    if (allPhotos.isEmpty) {
      throw QZoneApiException('相册内未找到任何照片');
    }

    int total = allPhotos.length;
    int success = 0;
    int failed = 0;
    int skipped = 0;
    
    for (int i = 0; i < allPhotos.length; i++) {
      final photo = allPhotos[i];
      final String fileName = _sanitizeFileName(photo.name);
      String fileExt = '';
      String message = '${i + 1}/$total: $fileName';

      // 更新总进度
      if (onProgress != null) {
        onProgress(i, total, '$message - 准备下载...');
      }

      // 确定文件类型和扩展名
      if (photo.isVideo) {
        fileExt = '.mp4';
        message = '$message (视频)';
      } else {
        fileExt = '.jpg';
        message = '$message (照片)';
      }

      final String filePath = '$albumPath/$fileName$fileExt';
      final File file = File(filePath);

      // 检查文件是否已存在
      if (skipExisting && await file.exists()) {
        skipped++;
        if (onProgress != null) {
          onProgress(i + 1, total, '$message - 已跳过(已存在)');
        }
        if (onItemComplete != null) {
          onItemComplete({
            'status': 'skipped',
            'message': '文件已存在',
            'filename': '$fileName$fileExt',
            'path': filePath,
            'photo': photo,
          });
        }
        continue;
      }

            try {
        // 获取下载URL
        String? url;

        // 对于视频，尝试获取真实视频URL
        if (photo.isVideo) {
          try {
            // 先检查是否有videoUrl
            if (photo.videoUrl != null && photo.videoUrl!.isNotEmpty) {
              url = photo.videoUrl;
              if (kDebugMode) {
                print("[QZoneService] 使用Photo对象中的videoUrl: $url");
              }
            } else {
              // 尝试获取真实视频URL
              final videoUrl = await _tryAlternativeVideoURL(
                photo,
                album.id,
                targetUin,
              );
              
              if (videoUrl != null && videoUrl.isNotEmpty) {
                url = videoUrl;
                if (kDebugMode) {
                  print("[QZoneService] 成功获取视频真实URL: $videoUrl");
                }
              } else if (photo.url != null) {
                // 如果没有获取到视频URL，但有photo.url，可能是缩略图
                url = photo.url;
          if (kDebugMode) {
                  print("[QZoneService] 未获取到视频URL，尝试使用photo.url: ${photo.url}");
                }
          }
        }
      } catch (e) {
        if (kDebugMode) {
              print("[QZoneService] 获取视频URL失败: $e，将尝试使用photo.url");
            }
            
            // 如果获取视频URL失败，尝试使用photo.url（可能是缩略图）
            if (photo.url != null) {
              url = photo.url;
            }
          }
        } else if (photo.url != null) {
          // 照片使用普通URL
          url = photo.url;
        }

        // 如果没有URL，抛出异常
        if (url == null || url.isEmpty) {
          throw Exception('没有找到下载链接');
        }

      if (onProgress != null) {
          onProgress(i + 1, total, '$message - 正在下载...');
        }

        // 下载文件
        try {
          final result = await downloadFile(
            url: url,
            savePath: albumPath,
            filename: '$fileName$fileExt',
            isVideo: photo.isVideo,
            onProgress: (received, total) {
              if (onProgress != null && total > 0) {
                final percentage = received / total;
                final progressMessage = '$message - 下载中 ${(percentage * 100).toStringAsFixed(1)}%';
                onProgress(i + 1, allPhotos.length, progressMessage);
              }
            }
          );
          
          success++;
          
          if (onProgress != null) {
            onProgress(i + 1, total, '$message - 下载完成');
          }
          
          if (onItemComplete != null) {
            onItemComplete({
              'status': 'success',
              'message': '下载成功',
              'filename': '$fileName$fileExt',
              'path': result['path'],
              'photo': photo,
              'size': result['size'],
            });
          }
          
          continue;
        } catch (downloadError) {
          if (kDebugMode) {
            print("[QZoneService] 下载失败: $downloadError");
        }
        
          // 如果是视频并且下载失败，可能需要尝试其他URL
        if (photo.isVideo) {
            if (kDebugMode) {
              print("[QZoneService] 视频下载失败，尝试其他方法获取视频URL");
            }
            
            try {
              // 再次尝试获取视频真实URL（使用不同接口）
              final alternativeVideoUrl = await getVideoRealUrl(
            photoId: photo.id,
            albumId: album.id,
            targetUin: targetUin,
          );
          
              if (alternativeVideoUrl != null && alternativeVideoUrl != url) {
                if (kDebugMode) {
                  print("[QZoneService] 找到备用视频URL: $alternativeVideoUrl");
                }
                
                if (onProgress != null) {
                  onProgress(i + 1, total, '$message - 尝试备用URL下载...');
                }
                
                final result = await downloadFile(
                  url: alternativeVideoUrl,
                  savePath: albumPath,
                  filename: '$fileName$fileExt',
                  isVideo: true,
                  onProgress: (received, total) {
                    if (onProgress != null && total > 0) {
                      final percentage = received / total;
                      final progressMessage = '$message - 备用URL下载中 ${(percentage * 100).toStringAsFixed(1)}%';
                      onProgress(i + 1, allPhotos.length, progressMessage);
                    }
                  }
                );
                
                success++;
                
                if (onProgress != null) {
                  onProgress(i + 1, total, '$message - 备用URL下载完成');
                }
                
          if (onItemComplete != null) {
            onItemComplete({
                    'status': 'success',
                    'message': '使用备用URL下载成功',
                    'filename': '$fileName$fileExt',
                    'path': result['path'],
              'photo': photo,
                    'size': result['size'],
            });
          }
                
          continue;
              }
            } catch (e) {
              if (kDebugMode) {
                print("[QZoneService] 备用视频URL下载也失败: $e");
              }
            }
          }
          
          // 如果所有尝试都失败，记录失败
          failed++;
          
            if (onProgress != null) {
            onProgress(i + 1, total, '$message - 下载失败: $downloadError');
            }
        
        if (onItemComplete != null) {
            onItemComplete({
              'status': 'failed',
              'message': '下载失败: $downloadError',
              'filename': '$fileName$fileExt',
              'path': filePath,
              'photo': photo,
            });
          }
        }
      } catch (e) {
        failed++;
        if (kDebugMode) {
          print("[QZoneService ERROR] 下载失败: $e");
        }

        if (onProgress != null) {
          onProgress(i + 1, total, '$message - 下载失败: ${e.toString()}');
        }
        if (onItemComplete != null) {
          onItemComplete({
            'status': 'failed',
            'message': '下载失败: ${e.toString()}',
            'filename': '$fileName$fileExt',
            'path': filePath,
            'photo': photo,
          });
        }
      }
    }
    
    return {
      'total': total,
      'success': success,
      'failed': failed,
      'skipped': skipped,
      'albumName': album.name,
      'albumPath': albumPath,
      'fetchedPhotoCount': allPhotos.length,
      'totalPhotoCount': album.photoCount,
    };
  }
  
  // 备用方法获取照片列表（针对加密相册或特殊情况）
  Future<List<Photo>> _getPhotoListBackup({
    required String albumId, 
    String? targetUin
  }) async {
    if (!isLoggedIn) {
      throw QZoneApiException("未登录，请先登录");
    }

    final String hostUin = targetUin ?? _loggedInUin!;
    final String uin = _loggedInUin!;
    final String gtk = _gTk!;
    
    if (kDebugMode) {
      print("[QZoneService DEBUG] 使用备用方法获取照片列表");
      print("[QZoneService DEBUG] 参数: albumId=$albumId, targetUin=$targetUin");
    }
    
    List<Photo> allPhotos = [];
    
    try {
      // 使用不同的API端点获取照片
      final response = await _dio.get(
        'https://h5.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/cgi_list_photo',
        queryParameters: {
          'g_tk': gtk,
          'hostUin': hostUin,
          'uin': uin,
          'appid': '4',
          'albumid': albumId,
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'source': 'qzone',
          'plat': 'qzone',
          'mode': '0',
          'format': 'jsonp',
          'callback': 'viewer_Callback',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
            'Referer': 'https://user.qzone.qq.com/',
            'Cookie': await _getFullCookieString('https://user.qzone.qq.com/'),
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );
      
      if (response.statusCode != 200) {
        throw QZoneApiException("备用API请求失败，状态码: ${response.statusCode}");
      }
      
      String responseBody = response.data.toString();
      
      // 解析JSONP响应
      int startIndex = responseBody.indexOf('(');
      int endIndex = responseBody.lastIndexOf(')');

      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        responseBody = responseBody.substring(startIndex + 1, endIndex);
      }
      
      final Map<String, dynamic> jsonData = jsonDecode(responseBody);
      
      // 即使有错误码也尝试解析数据
      final Map<String, dynamic> data = jsonData['data'] ?? {};
      final List<dynamic>? photoListJson = data['photoList'] as List<dynamic>?;
      
      if (photoListJson != null) {
        for (var photoJson in photoListJson) {
          if (photoJson is Map<String, dynamic>) {
            String? photoUrl = photoJson['url'] as String?;
            String? thumbUrl = photoJson['pre'] as String?;
            
            // 如果没有url，尝试其他字段
            if (photoUrl == null || photoUrl.isEmpty) {
              photoUrl = photoJson['raw_url'] as String?;
            }
            if (photoUrl == null || photoUrl.isEmpty) {
              photoUrl = photoJson['origin_url'] as String?;
            }
            
            // 判断是否为视频
            final bool isVideo = photoJson['is_video'] == 1 || 
                                (photoJson['videoInfo'] != null) ||
                                (photoJson['video_info'] != null);
            
            String? videoUrl;
            if (isVideo) {
              if (photoJson['videoInfo'] is Map<String, dynamic>) {
                videoUrl = photoJson['videoInfo']['url'] as String?;
              } else if (photoJson['video_info'] is Map<String, dynamic>) {
                videoUrl = photoJson['video_info']['url'] as String?;
              } else if (photoJson['video_url'] != null) {
                videoUrl = photoJson['video_url'] as String?;
              } else if (photoJson['raw_url'] != null) {
                videoUrl = photoJson['raw_url'] as String?;
              }
            }
            
            if (photoUrl != null || thumbUrl != null) {
              allPhotos.add(Photo(
                id: photoJson['lloc']?.toString() ?? photoJson['sloc']?.toString() ?? '',
                name: photoJson['name'] as String? ?? '未命名照片',
                desc: photoJson['desc'] as String?,
                url: photoUrl,
                thumbUrl: thumbUrl,
                uploadTime: (photoJson['uploadTime'] as num?)?.toInt(),
                width: (photoJson['width'] as num?)?.toInt(),
                height: (photoJson['height'] as num?)?.toInt(),
                isVideo: isVideo,
                videoUrl: videoUrl,
              ));
            }
          }
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 备用方法获取照片列表失败: $e");
        print("[QZoneService ERROR] 堆栈: $stackTrace");
      }
      throw QZoneApiException('备用方法获取照片列表失败: ${e.toString()}');
    }
    
    if (kDebugMode) {
      print("[QZoneService DEBUG] 备用方法成功获取照片数量: ${allPhotos.length}");
    }
    
    return allPhotos;
  }

  // 文件名清理（移除不合法字符）
  String _sanitizeFileName(String fileName) {
    // 替换不允许用于文件名的字符
    final sanitized = fileName
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')  // 替换Windows不允许的字符
      .replaceAll(RegExp(r'[\x00-\x1F]'), '')    // 替换控制字符
      .trim();                                   // 移除首尾空格
      
    return sanitized.isEmpty ? '未命名文件' : sanitized;
  }

  // 获取完整的Cookie字符串，用于图片请求
  Future<String> _getFullCookieString(String url) async {
    try {
      final cookies = await _cookieJar.loadForRequest(Uri.parse(url));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 获取Cookie失败: $e");
      }
      return '';
    }
  }

  // 使用更完整的Header信息访问图片
  Future<Uint8List?> getPhotoWithFullAuth(String photoUrl) async {
    if (!isLoggedIn) {
      throw QZoneApiException('未登录，请先登录');
    }

    try {
      final cookieString = await _getFullCookieString('https://user.qzone.qq.com/');
      
      // 构建完整的请求头
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
        'Referer': 'https://user.qzone.qq.com/',
        'Cookie': cookieString,
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'image',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'same-site',
      };

      final response = await _dio.get(
        photoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          followRedirects: true,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data);
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService ERROR] 获取照片失败: $e");
      }
      return null;
    }
  }

  // 尝试通过备用方法获取视频URL
  Future<String?> _tryAlternativeVideoURL(Photo photo, String albumId, String? targetUin) async {
    try {
      // 日志记录照片对象信息用于调试
      if (kDebugMode) {
        print("[QZoneService] 尝试获取视频真实URL");
        print("[QZoneService] 照片ID: ${photo.id}");
        print("[QZoneService] 照片URL: ${photo.url}");
        print("[QZoneService] 视频URL (如果有): ${photo.videoUrl}");
        print("[QZoneService] 是否视频: ${photo.isVideo}");
      }
    
      // 方法1：尝试使用视频信息接口
      final videoUrl = await getVideoRealUrl(
        photoId: photo.id,
        albumId: albumId,
        targetUin: targetUin,
      );
      
      if (videoUrl != null && videoUrl.isNotEmpty) {
        // 验证URL是否包含视频域名或视频扩展名
        if (videoUrl.contains('.mp4') || 
            videoUrl.contains('video') || 
            videoUrl.contains('photovideo.photo.qq.com')) {
          if (kDebugMode) {
            print("[QZoneService] 成功通过视频信息接口获取视频URL: $videoUrl");
          }
          return videoUrl;
        } else {
          if (kDebugMode) {
            print("[QZoneService] 获取到的URL可能不是视频: $videoUrl");
          }
        }
      }
      
      // 方法2：检查URL中的特殊参数
      if (photo.url != null) {
        final url = photo.url!;
        // 检查是否包含QQ空间视频特定参数
        if (url.contains('.mp4') || url.contains('photovideo.photo.qq.com')) {
          if (kDebugMode) {
            print("[QZoneService] 照片URL可能是视频: $url");
          }
          return url;
        }
        
        // 方法3：尝试分析URL和重构视频URL
        try {
          if (url.contains('?')) {
            // 提取参数
            final uri = Uri.parse(url);
            final params = uri.queryParameters;
            
            // 检查是否含有视频相关参数
            if (params.containsKey('bo') || params.containsKey('rf')) {
              // 尝试查找lloc或sloc作为视频ID
              if (photo.id.isNotEmpty) {
                // 构建可能的视频URL格式 (根据QQ空间API分析)
                String possibleVideoUrl = 'https://photovideo.photo.qq.com/${photo.id}.f0.mp4';
                if (kDebugMode) {
                  print("[QZoneService] 尝试构建视频URL: $possibleVideoUrl");
                }
                
                // 尝试验证URL
                try {
                  final headResponse = await _dio.head(
                    possibleVideoUrl,
                    options: Options(
                      headers: {
                        'User-Agent': QZoneApiConstants.userAgent,
                        'Referer': 'https://user.qzone.qq.com/',
                        'Range': 'bytes=0-0',
                      },
                    ),
                  );
                  
                  // 检查响应内容类型
                  final contentType = headResponse.headers.value('content-type');
                  if (contentType != null && contentType.contains('video')) {
                    if (kDebugMode) {
                      print("[QZoneService] 成功验证视频URL: $possibleVideoUrl");
                    }
                    return possibleVideoUrl;
                  }
                } catch (e) {
                  // 验证失败，继续尝试其他方法
                  if (kDebugMode) {
                    print("[QZoneService] 验证构建的视频URL失败: $e");
                  }
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[QZoneService] 分析URL失败: $e");
          }
        }
      }
      
      // 方法4：检查照片对象中所有可能的URL字段
      if (photo.url != null && photo.url!.isNotEmpty) {
        // 检查URL是否是视频URL
        try {
          final response = await _dio.head(
            photo.url!,
            options: Options(
              headers: {
                'User-Agent': QZoneApiConstants.userAgent,
                'Referer': 'https://user.qzone.qq.com/',
                'Accept-Encoding': 'identity;q=1, *;q=0',
                'Range': 'bytes=0-0',
              },
            ),
          );
          
          final contentType = response.headers.value('content-type');
          response.headers.value('content-length');
          
          // 检查内容类型和大小
          if (contentType != null && contentType.contains('video')) {
            if (kDebugMode) {
              print("[QZoneService] 确认URL是视频: ${photo.url} (Content-Type: $contentType)");
            }
            return photo.url;
          }
          
          // 检查响应头中是否包含视频相关信息
          for (var entry in response.headers.map.entries) {
            if (entry.key.toLowerCase().contains('video') || 
                (entry.value.isNotEmpty && entry.value.first.contains('video'))) {
              if (kDebugMode) {
                print("[QZoneService] 在响应头中找到视频相关信息: ${entry.key}: ${entry.value}");
              }
              return photo.url;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("[QZoneService] 检查URL类型失败: $e");
          }
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 尝试备用视频URL方法失败: $e");
      }
      return null;
    }
  }
} 

