class Photo {
  final String id;
  final String name;
  final String? desc;
  final String? url;
  final String? thumbUrl;
  final int? uploadTime;
  final int? width;
  final int? height;
  final bool isVideo;
  final String? videoUrl;
  
  Photo({
    required this.id,
    required this.name,
    this.desc,
    this.url,
    this.thumbUrl,
    this.uploadTime,
    this.width,
    this.height,
    this.isVideo = false,
    this.videoUrl,
  });
  
  bool get hasMedia => url != null || videoUrl != null;
  
  @override
  String toString() {
    return 'Photo(id: $id, name: $name, url: $url, isVideo: $isVideo)';
  }
} 