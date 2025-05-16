class Photo {
  final String id;
  final String name;
  final String? desc;
  final String? url;
  final String? thumbUrl;
  final int? uploadTime;
  final int? width;
  final int? height;
  
  Photo({
    required this.id,
    required this.name,
    this.desc,
    this.url,
    this.thumbUrl,
    this.uploadTime,
    this.width,
    this.height,
  });
  
  @override
  String toString() {
    return 'Photo(id: $id, name: $name, url: $url)';
  }
} 