import 'file_upload.dart';

class FileUploadStatus {
  FileUploadStatus({
    required this.fileUpload,
    required this.status,
    required this.progress,
    this.currentSize = 0,
    this.retryCount = 0,
    this.error,
  });

  final FileUpload fileUpload;
  final UploadStatus status;
  final double progress;
  final int currentSize;
  final int retryCount;
  final String? error;

  FileUploadStatus copyWith({
    FileUpload? fileUpload,
    UploadStatus? status,
    double? progress,
    int? currentSize,
    int? retryCount,
    String? error,
  }) {
    return FileUploadStatus(
      fileUpload: fileUpload ?? this.fileUpload,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentSize: currentSize ?? this.currentSize,
      retryCount: retryCount ?? this.retryCount,
      error: error ?? this.error,
    );
  }
}

enum UploadStatus { ready, uploading, success, error }
