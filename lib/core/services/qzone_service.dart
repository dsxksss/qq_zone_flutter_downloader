import 'dart:async';
import 'dart:convert'; // Import for jsonDecode
import 'dart:io'; // For HttpClient
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
      
      // 发起下载请求
      
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        throw QZoneApiException("下载失败：文件未创建");
      }
      
      // 获取文件大小
      final fileSize = await file.length();
      
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
        options: Options(responseType: ResponseType.plain),
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
          
          if (picPosInPage < photos.length) {
            final photo = photos[picPosInPage];
            
            if (photo['video_info'] != null) {
              final videoInfo = photo['video_info'];
              if (videoInfo['status'] == 2) { // 状态为2表示可以正常播放
                String? videoUrl = videoInfo['download_url'] ?? videoInfo['video_url'];
                return videoUrl;
              }
            }
          }
        }
      }
      
      return null;
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

    List<Photo> photos;
    try {
      // 尝试使用正常API获取照片列表
      photos = await getPhotoList(
        albumId: album.id,
        targetUin: targetUin,
        retryCount: 3, // 增加重试次数
      );
    } catch (e) {
      if (kDebugMode) {
        print("[QZoneService] 使用普通API获取照片列表失败，尝试备用API: $e");
      }
      
      // 如果正常API失败，尝试使用备用API获取照片列表
      try {
        photos = await _getPhotoListBackup(
          albumId: album.id,
          targetUin: targetUin,
        );
      } catch (e) {
        if (kDebugMode) {
          print("[QZoneService] 备用API也失败: $e");
        }
        throw QZoneApiException('无法获取相册照片: $e');
      }
    }

    if (photos.isEmpty) {
      throw QZoneApiException('相册内未找到任何照片');
    }

    int total = photos.length;
    int success = 0;
    int failed = 0;
    int skipped = 0;

    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final String fileName = _sanitizeFileName(photo.name);
      String fileExt = '';
      String message = '${i + 1}/$total: $fileName';

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
        String? url;

        if (photo.isVideo && photo.videoUrl != null) {
          url = photo.videoUrl;
        } else if (photo.url != null) {
          url = photo.url;
        } else {
          throw Exception('没有找到下载链接');
        }

        if (onProgress != null) {
          onProgress(i + 1, total, '$message - 正在下载...');
        }

        final response = await _dio.get(
          url!,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
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

        await file.writeAsBytes(response.data);
        success++;

        if (onProgress != null) {
          onProgress(i + 1, total, '$message - 下载完成');
        }
        if (onItemComplete != null) {
          onItemComplete({
            'status': 'success',
            'message': '下载成功',
            'filename': '$fileName$fileExt',
            'path': filePath,
            'photo': photo,
          });
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
} 

