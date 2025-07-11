import 'package:flutter/foundation.dart';
import 'package:resumable_upload_example/models/file_upload_status.dart';

import '../data/repository.dart';

class UploadViewModel extends ChangeNotifier {
  UploadViewModel({required FileUploadRepository fileUploadRepository})
    : _fileUploadRepository = fileUploadRepository;

  /// Dependencies
  final FileUploadRepository _fileUploadRepository;

  /// States
  List<FileUploadStatus> _uploads = [];

  List<FileUploadStatus> get uploads => _uploads;

  void init() {
    _fileUploadRepository.onUpdatedUploadQueue.listen((statuses) {
      _uploads = List<FileUploadStatus>.unmodifiable(statuses);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _fileUploadRepository.dispose();
    super.dispose();
  }

  void enqueue(String filePath) {
    _fileUploadRepository.create(
      filePath: filePath,
      metadata: {
      },
    );
  }
}
