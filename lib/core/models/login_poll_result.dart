enum LoginPollStatus {
  loginSuccess, // 登录成功
  qrInvalidOrExpired, // 二维码失效或过期
  qrNotScanned, // 二维码未扫描
  qrScannedWaitingConfirmation, // 二维码已扫描，等待确认
  error, // 轮询过程中发生错误
  unknown, // 未知状态
}

class LoginPollResult {
  final LoginPollStatus status;
  final String? message; // 状态描述信息
  final String? nickname; // 用户昵称 (登录成功时)
  final String? redirectUrl; // 跳转URL (登录成功时)

  LoginPollResult({
    required this.status,
    this.message,
    this.nickname,
    this.redirectUrl,
  });

  @override
  String toString() {
    return 'LoginPollResult(status: $status, message: $message, nickname: $nickname, redirectUrl: $redirectUrl)';
  }
} 