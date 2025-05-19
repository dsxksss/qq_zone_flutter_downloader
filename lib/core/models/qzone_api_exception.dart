class QZoneApiException implements Exception {
  final String message;
  final dynamic underlyingError;

  QZoneApiException(this.message, {this.underlyingError});

  @override
  String toString() {
    String result = 'QZoneApiException: $message';
    if (underlyingError != null) {
      result += ' (Underlying error: $underlyingError)';
    }
    return result;
  }
}

// 你可能已经有一个 QZoneLoginException，如果它的目的不同，则保留两者
// 如果 QZoneApiException 可以覆盖其功能，则可以考虑合并或替换
class QZoneLoginException extends QZoneApiException {
  QZoneLoginException(super.message, {super.underlyingError});
} 