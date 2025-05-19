class Friend {
  final String uin;
  final String nickname;
  final String? avatarUrl;
  final String? remark;
  
  Friend({
    required this.uin,
    required this.nickname,
    this.avatarUrl,
    this.remark,
  });
  
  @override
  String toString() {
    return 'Friend(uin: $uin, nickname: $nickname${remark != null ? ", remark: $remark" : ""})';
  }
} 