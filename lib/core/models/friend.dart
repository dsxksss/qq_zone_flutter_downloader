class Friend {
  final String uin;
  final String nickname;
  final String? avatarUrl;
  
  Friend({
    required this.uin,
    required this.nickname,
    this.avatarUrl,
  });
  
  @override
  String toString() {
    return 'Friend(uin: $uin, nickname: $nickname)';
  }
} 