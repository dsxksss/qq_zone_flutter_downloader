import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );

    // 请求通知权限
    if (Platform.isAndroid) {
      // Android 13及以上需要请求通知权限
      try {
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (e) {
        if (kDebugMode) {
          print("[NotificationService] 请求通知权限失败: $e");
        }
      }
    }

    _isInitialized = true;
  }

  // 显示下载完成通知
  Future<void> showDownloadComplete({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'download_channel',
      '下载通知',
      channelDescription: '显示QQ空间照片和视频下载的通知',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // 显示批量下载完成通知
  Future<void> showBatchDownloadComplete({
    required String albumName,
    required int total,
    required int success,
    required int failed,
    required int skipped,
    String? savePath,
  }) async {
    await showDownloadComplete(
      title: '相册"$albumName"下载完成',
      body: '总数: $total, 成功: $success, 失败: $failed, 跳过: $skipped',
      payload: savePath,
    );
  }

  // 显示下载进度通知
  Future<void> showDownloadProgress({
    required int id,
    required String title,
    required String message,
    required double progress,
    required double maxProgress,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'download_progress_channel',
      '下载进度通知',
      channelDescription: '显示QQ空间照片和视频下载进度的通知',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: (progress * 100).toInt(),
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      message,
      notificationDetails,
    );
  }

  // 显示下载取消通知
  Future<void> showDownloadCancelled({
    required String albumName,
  }) async {
    await showDownloadComplete(
      title: '已取消下载',
      body: '相册"$albumName"的下载已被取消',
    );
  }
}
