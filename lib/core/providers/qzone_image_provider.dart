import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/providers/service_providers.dart';
import 'dart:ui' as ui;

// QQ空间图片提供器，用于加载需要认证的图片
class QzoneImageProvider extends ImageProvider<QzoneImageProvider> {
  final String url;
  final WidgetRef ref;

  QzoneImageProvider(this.url, this.ref);

  @override
  Future<QzoneImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<QzoneImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(QzoneImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<QzoneImageProvider>('Image key', key);
      },
    );
  }

  Future<ui.Codec> _loadAsync(QzoneImageProvider key, ImageDecoderCallback decode) async {
    try {
      final qzoneService = ref.read(qZoneServiceProvider);
      final bytes = await qzoneService.getPhotoWithFullAuth(url);
      
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to load image');
      }
      
      return await ui.instantiateImageCodec(bytes);
    } catch (e) {
      if (kDebugMode) {
        print("[QzoneImageProvider] 加载图片失败: $e");
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is QzoneImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
} 