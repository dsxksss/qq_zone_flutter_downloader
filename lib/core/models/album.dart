class Album {
  final String id; // 相册ID
  final String name; // 相册名
  final String desc; // 相册描述
  final int photoCount; // 照片数量
  final String? coverUrl; // 相册封面URL (可选)
  final DateTime createTime; // 创建时间
  final DateTime modifyTime; // 修改时间
  // 可以根据需要添加更多属性，例如创建时间、描述等

  Album({
    required this.id,
    required this.name,
    required this.desc,
    required this.createTime,
    required this.modifyTime,
    required this.photoCount,
    this.coverUrl,
  });

  @override
  String toString() {
    return 'Album{id: $id, name: $name, photoCount: $photoCount, coverUrl: $coverUrl, createTime: $createTime, desc: $desc}';
  }

  // 如果需要从JSON反序列化，可以添加 factory constructor
  factory Album.fromJson(Map<String, dynamic> json) {
    // API返回的时间戳是秒级的，需要乘以1000转为毫秒
    // Go 代码中使用的字段名: id, name, desc, total, coverUrl/pre, createtime, modifytime
    // Flutter 旧代码中: albumid, albumname, total_count, coverurl
    return Album(
      id: json['id']?.toString() ?? json['albumid']?.toString() ?? '',
      name: json['name']?.toString() ?? json['albumname']?.toString() ?? '未命名相册',
      desc: json['desc']?.toString() ?? '',
      // createtime 和 modifytime 在 Go 的实现中，json['data']['albumList'] 的元素里就有这些字段
      // 确保API返回的是数字类型的时间戳
      createTime: DateTime.fromMillisecondsSinceEpoch(
        ((json['createtime'] ?? json['createTime'] ?? 0) as num).toInt() * 1000
      ),
      modifyTime: DateTime.fromMillisecondsSinceEpoch(
        ((json['modifytime'] ?? json['modifyTime'] ?? 0) as num).toInt() * 1000
      ),
      photoCount: (json['total'] ?? json['total_count'] ?? 0) as int,
      coverUrl: json['coverUrl']?.toString() ?? json['pre']?.toString().trim(), // 有些 pre 字段可能包含空格
    );
  }
} 