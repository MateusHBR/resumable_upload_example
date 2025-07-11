class FileUpload {
  FileUpload({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.sessionUrl,
    this.sessionTTL,
    this.totalSize = 0,
    this.uploadedAt,
    this.metadata = const {},
  });

  final String id;
  final String filePath;
  final DateTime createdAt;
  final String? sessionUrl;
  final int? sessionTTL;
  final int totalSize;
  final DateTime? uploadedAt;
  final Map<String, String> metadata;

  FileUpload copyWith({
    String? filePath,
    DateTime? createdAt,
    String? reportMediaId,
    String? sessionUrl,
    int? sessionTTL,
    int? totalSize,
    DateTime? uploadedAt,
    Map<String, String>? metadata,
  }) {
    return FileUpload(
      id: id,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      sessionUrl: sessionUrl ?? this.sessionUrl,
      sessionTTL: sessionTTL ?? this.sessionTTL,
      totalSize: totalSize ?? this.totalSize,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
