class QZoneApiConstants {
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36';

  // URLs from qzone.go
  static const String loginSigUrl = 'https://xui.ptlogin2.qq.com/cgi-bin/xlogin?proxy_url=https://qzs.qq.com/qzone/v6/portal/proxy.html&daid=5&&hide_title_bar=1&low_login=0&qlogin_auto_login=1&no_verifyimg=1&link_target=blank&appid=549000912&style=22&target=self&s_url=https://qzs.qq.com/qzone/v5/loginsucc.html?para=izone&pt_qr_app=手机QQ空间&pt_qr_link=https://z.qzone.com/download.html&self_regurl=https://qzs.qq.com/qzone/v6/reg/index.html&pt_qr_help_link=https://z.qzone.com/download.html&pt_no_auth=0';
  
  // ptqrshow URL needs a random 't' parameter. We'll construct it dynamically.
  static String getQrShowUrl() {
    final t = DateTime.now().millisecondsSinceEpoch / 1000; // or use Random().nextDouble()
    return 'https://ssl.ptlogin2.qq.com/ptqrshow?appid=549000912&e=2&l=M&s=3&d=72&v=4&t=$t&daid=5&pt_3rd_aid=0';
  }

  // ptqrlogin URL also needs dynamic parameters.
  static String getPtQrLoginUrl({
    required String ptqrtoken,
    required String loginSig,
    String? u1RedirectUrl, // Default from Go code
    String action = '', // Will be calculated dynamically
  }) {
    final String effectiveU1 = u1RedirectUrl ?? 'https://qzs.qq.com/qzone/v5/loginsucc.html?para=izone';
    final String effectiveAction = action.isEmpty ? '0-0-${DateTime.now().millisecondsSinceEpoch}' : action;
    return 'https://ssl.ptlogin2.qq.com/ptqrlogin?u1=${Uri.encodeQueryComponent(effectiveU1)}&ptqrtoken=$ptqrtoken&ptredirect=0&h=1&t=1&g=1&from_ui=1&ptlang=2052&action=$effectiveAction&js_ver=21010623&js_type=1&login_sig=$loginSig&pt_uistyle=40&aid=549000912&daid=5&has_onekey=1';
  }
} 