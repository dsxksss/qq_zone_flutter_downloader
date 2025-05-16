import 'dart:typed_data';

class LoginQrResult {
  final Uint8List qrImageBytes;
  final String loginSig;
  final String qrsig;

  LoginQrResult({
    required this.qrImageBytes,
    required this.loginSig,
    required this.qrsig,
  });
} 