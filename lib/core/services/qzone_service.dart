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
      print("[QZoneService CONSTRUCTOR] QZoneService instance created. HashCode: ${hashCode}");
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
            if (currentArg.startsWith("'"))
              currentArg = currentArg.substring(1);
            if (currentArg.endsWith("'"))
              currentArg = currentArg.substring(0, currentArg.length - 1);
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

  // TODO: Implement finalizeLogin (credential check)
  Future<List<Album>> getAlbumList({String? targetUinOverride, int retryCount = 2}) async {
    // Use the stored _loggedInUin and _gTk
    if (_loggedInUin == null || _gTk == null) {
      throw QZoneApiException("Not logged in or g_tk/uin not available. Cannot fetch albums.");
    }

    final String hostUin = targetUinOverride ?? _loggedInUin!; // If targetUinOverride is null, use loggedInUin
    final String uin = _loggedInUin!;
    final String gtk = _gTk!;
    
    // Cookie will be handled by Dio's CookieManager interceptor automatically

    // print("[QZoneService] GetAlbumList called with hostUin: $hostUin, uin: $uin, gtk: $gtk");

    List<Album> allAlbums = [];
    int pageStart = 0;
    const int pageNum = 30; // As per Go code
    bool hasMore = true;
    int currentRetry = 0;

    while (hasMore) {
      try {
        // Construct the URL based on Go code's GetAlbumList
        // String url = QZoneApiConstants.getAlbumListUrl(hostUin: hostUin, uin: uin, gtk: gtk, pageStart: pageStart, pageNum: pageNum);
        // From Go code: "https://user.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/fcg_list_album_v3?g_tk=%v&callback=shine_Callback&hostUin=%v&uin=%v&appid=4&inCharset=utf-8&outCharset=utf-8&source=qzone&plat=qzone&format=jsonp&notice=0&filter=1&handset=4&pageNumModeSort=40&pageNumModeClass=15&needUserInfo=1&idcNum=4&mode=2&pageStart=%d&pageNum=%d&callbackFun=shine"
        final Map<String, dynamic> params = {
          'g_tk': gtk,
          'callback': 'shine_Callback', // Placeholder, will be stripped
          'hostUin': hostUin,
          'uin': uin,
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
          'mode': '2', // Important from Go code
          'pageStart': pageStart.toString(),
          'pageNum': pageNum.toString(),
          'callbackFun': 'shine', // Callback function name
        };

        final uri = Uri.parse('https://user.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/fcg_list_album_v3').replace(queryParameters: params);
        final url = uri.toString();

        if (kDebugMode) {
          print("[QZoneService] Fetching albums (page): $url");
        }

        Response response = await _dio.get(
          url,
          options: Options(responseType: ResponseType.plain), // Get as plain text for JSONP
        );

        String responseBody = response.data.toString().trim(); // Trim whitespace
        
        // 检查是否403错误
        if (response.statusCode == 403) {
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 收到403错误，重试第$currentRetry次 (共$retryCount次)");
            }
            // 重试前等待一段时间
            await Future.delayed(Duration(seconds: 2));
            continue;
          } else {
            throw QZoneApiException("获取相册列表失败，服务器返回403禁止访问");
          }
        }

        // More robust JSONP stripping
        int startIndex = responseBody.indexOf('(');
        int endIndex = responseBody.lastIndexOf(')');

        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          responseBody = responseBody.substring(startIndex + 1, endIndex);
        } else {
            if (kDebugMode) {
                print("[QZoneService WARN] Could not find valid JSONP parentheses. Raw response (after trim): $responseBody");
            }
            
            // 尝试重试
            if (currentRetry < retryCount && responseBody.isEmpty) {
              currentRetry++;
              if (kDebugMode) {
                print("[QZoneService] 响应解析失败，重试第$currentRetry次 (共$retryCount次)");
              }
              // 重试前等待一段时间
              await Future.delayed(Duration(seconds: 2));
              continue;
            }
            
            // If parentheses are not found, it might be plain JSON or an error string.
            // We will let jsonDecode attempt to parse it. If it fails, it will throw a FormatException.
        }
        
        if (kDebugMode) {
            print("[QZoneService DEBUG] JSONP stripped body for decode: $responseBody");
        }

        // 如果响应体为空，可能需要重试
        if (responseBody.isEmpty) {
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 响应体为空，重试第$currentRetry次 (共$retryCount次)");
            }
            // 重试前等待一段时间
            await Future.delayed(Duration(seconds: 2));
            continue;
          } else {
            throw QZoneApiException("获取相册列表失败，响应内容为空");
          }
        }

        final Map<String, dynamic> jsonData = jsonDecode(responseBody);

        if (jsonData['code'] != 0) {
          throw QZoneApiException("Failed to load album list page. API Error: ${jsonData['message']} (code: ${jsonData['code']})");
        }

        final Map<String, dynamic> data = jsonData['data'] ?? {};
        final List<dynamic>? albumListJson = data['albumList'] as List<dynamic>?;

        if (albumListJson != null) {
          for (var albumJsonUntyped in albumListJson) {
            if (albumJsonUntyped is Map<String, dynamic>) {
              final Map<String, dynamic> albumJson = albumJsonUntyped; // Now definitely a Map
               // Check for allowAccess as in Go code
              final num allowAccessNum = albumJson['allowAccess'] ?? 1;
              final int allowAccess = allowAccessNum.toInt(); // Default to 1 if null
              if (allowAccess == 0) {
                  if (kDebugMode) print("[QZoneService DEBUG] Skipping album due to allowAccess=0: ${albumJson['name']}");
                  continue;
              }
              
              // Corrected coverUrl parsing based on observed log data where 'pre' is a String URL
              String? coverUrlValue = albumJson['pre'] as String?;
              // Fallback if 'pre' is null or empty, try 'url' (though 'url' wasn't seen in logs for album object directly)
              if (coverUrlValue == null || coverUrlValue.isEmpty) { 
                coverUrlValue = albumJson['url'] as String?;
              }

              if (kDebugMode) {
                print("[QZoneService DEBUG] Album: ${albumJson['name']}, Attempted coverUrl: $coverUrlValue, raw pre: ${albumJson['pre']}, raw url: ${albumJson['url']}");
              }

              allAlbums.add(Album(
                id: albumJson['id']?.toString() ?? '', // Ensure ID is a string
                name: albumJson['name'] as String? ?? '未知相册',
                photoCount: (albumJson['total'] as num?)?.toInt() ?? 0, // 'total' is usually photo count
                coverUrl: coverUrlValue,
              ));
            }
          }
        }
        
        // Pagination logic from Go
        // nextPageStart := t.Get("nextPageStart").Int()
	      // if nextPageStart == t.Get("albumsInUser").Int() { break }
        // pageStart = nextPageStart

        final int? nextPageStart = (data['nextPageStart'] as num?)?.toInt();
        final int? albumsInUser = (data['albumsInUser'] as num?)?.toInt();

        if (kDebugMode) {
           print("[QZoneService DEBUG] Album pagination: nextPageStart=$nextPageStart, albumsInUser=$albumsInUser, currentAlbumCount=${allAlbums.length}");
        }

        if (nextPageStart != null && albumsInUser != null && nextPageStart < albumsInUser && albumListJson != null && albumListJson.isNotEmpty) {
          pageStart = nextPageStart;
          hasMore = true;
        } else {
          hasMore = false;
        }
        
        // 成功获取一页数据后，重置重试计数
        currentRetry = 0;

      } on DioException catch (e,s) { // Added stack trace
          if (kDebugMode) {
            print("[QZoneService ERROR] DioException while fetching album list page: ${e.message}");
            print("[QZoneService ERROR] DioException Data: ${e.response?.data}"); // Print response data if available
            print("[QZoneService ERROR] DioException RuntimeType: ${e.runtimeType}");
            print("[QZoneService ERROR] DioException StackTrace: $s");
          }
          
          // 对网络错误进行重试
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 网络请求失败，重试第$currentRetry次 (共$retryCount次)");
            }
            await Future.delayed(Duration(seconds: 2));
            continue;
          }
          
        throw QZoneApiException('Network error while fetching album list page: ${e.message}', underlyingError: e);
      } catch (e, s) { // Added stack trace
        if (kDebugMode) {
            print("[QZoneService ERROR] Error during album list page processing (e.g., JSON parsing): $e");
            print("[QZoneService ERROR] RuntimeType: ${e.runtimeType}");
            print("[QZoneService ERROR] StackTrace: $s");
        }
        
        // 对解析错误进行重试
        if (currentRetry < retryCount) {
          currentRetry++;
          if (kDebugMode) {
            print("[QZoneService] 数据处理失败，重试第$currentRetry次 (共$retryCount次)");
          }
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        throw QZoneApiException('Unexpected error while fetching or parsing album list page: ${e.toString()}', underlyingError: e);
      }
    }
     if (kDebugMode) {
        print("[QZoneService] Total albums fetched: ${allAlbums.length}");
      }
    return allAlbums;
    
    // **** Remove Old Mock Implementation ****
    // await Future.delayed(const Duration(seconds: 2)); 
    // if (kDebugMode) {
    //   print("[QZoneService] Returning mock album list.");
    // }
    // return [
    //   Album(id: '1', name: '我的第一个相册', photoCount: 10),
    //   Album(id: '2', name: '旅行照片集锦', photoCount: 123, coverUrl: 'https://via.placeholder.com/150'),
    //   Album(id: '3', name: '家庭聚会回忆录', photoCount: 55),
    // ];
    // **** End Remove Old Mock Implementation ****
  }

  // TODO: Implement getPhotoList
  Future<List<Photo>> getPhotoList({
    required String albumId,
    String? targetUinOverride,
    int retryCount = 2
  }) async {
    // 检查登录状态
    if (_loggedInUin == null || _gTk == null) {
      throw QZoneApiException("Not logged in or g_tk/uin not available. Cannot fetch photos.");
    }

    final String hostUin = targetUinOverride ?? _loggedInUin!;
    final String uin = _loggedInUin!;
    final String gtk = _gTk!;
    
    List<Photo> allPhotos = [];
    int pageStart = 0;
    const int pageNum = 30;
    bool hasMore = true;
    int currentRetry = 0;

    while (hasMore) {
      try {
        // 构建请求参数
        final Map<String, dynamic> params = {
          'g_tk': gtk,
          'callback': 'shine_Callback',
          'hostUin': hostUin,
          'uin': uin,
          'appid': '4',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'source': 'qzone',
          'plat': 'qzone',
          'format': 'jsonp',
          'notice': '0',
          'filter': '1',
          'handset': '4',
          'topicId': albumId,
          'pageStart': pageStart.toString(),
          'pageNum': pageNum.toString(),
          'callbackFun': 'shine',
          'needUserInfo': '1',
          'singleurl': '1', // 获取单张原图URL
          'mode': '0', // 列表模式
        };

        final uri = Uri.parse('https://user.qzone.qq.com/proxy/domain/photo.qzone.qq.com/fcgi-bin/cgi_list_photo').replace(queryParameters: params);
        final url = uri.toString();

        if (kDebugMode) {
          print("[QZoneService] 获取相册照片 (page): $url");
        }

        Response response = await _dio.get(
          url,
          options: Options(responseType: ResponseType.plain),
        );

        String responseBody = response.data.toString().trim();
        
        // 检查是否403错误
        if (response.statusCode == 403) {
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 获取照片列表收到403错误，重试第$currentRetry次 (共$retryCount次)");
            }
            await Future.delayed(Duration(seconds: 2));
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
        } else {
          if (kDebugMode) {
            print("[QZoneService WARN] 照片列表：无法找到有效的JSONP括号. 原始响应: $responseBody");
          }
          
          if (currentRetry < retryCount && responseBody.isEmpty) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 照片列表解析失败，重试第$currentRetry次 (共$retryCount次)");
            }
            await Future.delayed(Duration(seconds: 2));
            continue;
          }
        }
        
        if (kDebugMode) {
          print("[QZoneService DEBUG] 照片列表JSONP去除括号后: $responseBody");
        }

        // 检查空响应
        if (responseBody.isEmpty) {
          if (currentRetry < retryCount) {
            currentRetry++;
            if (kDebugMode) {
              print("[QZoneService] 照片列表响应为空，重试第$currentRetry次 (共$retryCount次)");
            }
            await Future.delayed(Duration(seconds: 2));
            continue;
          } else {
            throw QZoneApiException("获取照片列表失败，响应内容为空");
          }
        }

        final Map<String, dynamic> jsonData = jsonDecode(responseBody);

        if (jsonData['code'] != 0) {
          throw QZoneApiException("获取照片列表失败. API错误: ${jsonData['message']} (code: ${jsonData['code']})");
        }

        final Map<String, dynamic> data = jsonData['data'] ?? {};
        final List<dynamic>? photoListJson = data['photoList'] as List<dynamic>?;

        if (photoListJson != null) {
          for (var photoJsonUntyped in photoListJson) {
            if (photoJsonUntyped is Map<String, dynamic>) {
              final Map<String, dynamic> photoJson = photoJsonUntyped;
              
              // 处理照片URL
              String? photoUrl = photoJson['url'] as String?;
              String? thumbUrl = photoJson['pre'] as String?;

              allPhotos.add(Photo(
                id: photoJson['lloc']?.toString() ?? photoJson['sloc']?.toString() ?? '',
                name: photoJson['name'] as String? ?? '未命名照片',
                desc: photoJson['desc'] as String?,
                url: photoUrl,
                thumbUrl: thumbUrl,
                uploadTime: (photoJson['uploadTime'] as num?)?.toInt(),
                width: (photoJson['width'] as num?)?.toInt(),
                height: (photoJson['height'] as num?)?.toInt(),
              ));
            }
          }
        }

        // 分页处理
        final int? totalPhoto = (data['totalPhoto'] as num?)?.toInt() ?? 0;
        if (pageStart + pageNum < (totalPhoto ?? 0) && photoListJson != null && photoListJson.isNotEmpty) {
          pageStart += pageNum;
          hasMore = true;
        } else {
          hasMore = false;
        }
        
        // 成功获取数据后重置重试计数
        currentRetry = 0;
        
      } on DioException catch (e, s) {
        if (kDebugMode) {
          print("[QZoneService ERROR] 获取照片列表DioException: ${e.message}");
          print("[QZoneService ERROR] DioException数据: ${e.response?.data}");
          print("[QZoneService ERROR] DioException类型: ${e.runtimeType}");
          print("[QZoneService ERROR] DioException堆栈: $s");
        }
        
        if (currentRetry < retryCount) {
          currentRetry++;
          if (kDebugMode) {
            print("[QZoneService] 照片列表网络请求失败，重试第$currentRetry次 (共$retryCount次)");
          }
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        throw QZoneApiException('获取照片列表网络错误: ${e.message}', underlyingError: e);
      } catch (e, s) {
        if (kDebugMode) {
          print("[QZoneService ERROR] 获取照片列表处理错误: $e");
          print("[QZoneService ERROR] 错误类型: ${e.runtimeType}");
          print("[QZoneService ERROR] 错误堆栈: $s");
        }
        
        if (currentRetry < retryCount) {
          currentRetry++;
          if (kDebugMode) {
            print("[QZoneService] 照片列表处理失败，重试第$currentRetry次 (共$retryCount次)");
          }
          await Future.delayed(Duration(seconds: 2));
          continue;
        }
        
        throw QZoneApiException('获取照片列表数据处理错误: ${e.toString()}', underlyingError: e);
      }
    }
    
    if (kDebugMode) {
      print("[QZoneService] 获取到照片总数: ${allPhotos.length}");
    }
    return allPhotos;
  }
  
  // TODO: Implement downloadFile (for photos/videos)
} 
