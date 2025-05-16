import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qq_zone_flutter_downloader/core/services/qzone_service.dart';

// Provider for QZoneService
final qZoneServiceProvider = Provider<QZoneService>((ref) {
  return QZoneService(); 
}); 