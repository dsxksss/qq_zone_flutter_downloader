class Album {
  final String id; // 相册ID
  final String name; // 相册名
  final int photoCount; // 照片数量
  final String? coverUrl; // 相册封面URL (可选)
  // 可以根据需要添加更多属性，例如创建时间、描述等

  Album({
    required this.id,
    required this.name,
    this.photoCount = 0,
    this.coverUrl,
  });

  // 如果需要从JSON反序列化，可以添加 factory constructor
  // factory Album.fromJson(Map<String, dynamic> json) {
  //   return Album(
  //     id: json['albumid'] ?? '',
  //     name: json['albumname'] ?? '未知相册',
  //     photoCount: json['total_count'] ?? 0,
  //     coverUrl: json['coverurl'],
  //   );
  // }
} 