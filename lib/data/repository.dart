import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:resumable_upload_example/data/datasource.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import '../models/file_upload.dart';
import '../models/file_upload_status.dart';

const _kOneMB = 1024 * 1024;

///The chunk size should be a multiple of 256 KiB (256 x 1024 bytes)
const _kExpectedChunkSize = 8 * _kOneMB; // 8MB

/// https://cloud.google.com/storage/docs/resumable-uploads#introduction
/// A resumable upload must be completed within a week of being initiated, but can be cancelled at any time.
const _kUploadSessionTTL = Duration(days: 6, hours: 23);

class FileUploadRepository {
  static const _maxRetries = 3;

  FileUploadRepository({required FileUploadRemoteDatasource remoteDatasource})
    : _remoteDatasource = remoteDatasource;

  final FileUploadRemoteDatasource _remoteDatasource;

  // Queue management
  final _uploadQueue = <FileUploadStatus>[];
  final _uploadQueueController = BehaviorSubject<List<FileUploadStatus>>.seeded(
    [],
  );

  // Local storage
  Directory? _documentsDirectory;

  int get _maxConcurrentUploads => 8;

  // Stream of upload statuses
  Stream<List<FileUploadStatus>> get onUpdatedUploadQueue =>
      _uploadQueueController.stream;

  Future<void> init() async {
    debugPrint('Initializing file upload repository');
    _documentsDirectory = await getApplicationDocumentsDirectory();
  }

  void dispose() {
    debugPrint('Disposing FileUploadRepository');
    if (!_uploadQueueController.isClosed) _uploadQueueController.close();
  }

  /// Create and save a new file upload
  Future<FileUpload> create({
    required String filePath,
    Map<String, String> metadata = const {},
  }) async {
    // Ensure directory is initialized
    _documentsDirectory ??= await getApplicationDocumentsDirectory();

    final path = p.join(_documentsDirectory!.path, p.basename(filePath));
    final givenFile = File(filePath);
    await givenFile.copy(path);
    givenFile.delete();

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final fileUpload = FileUpload(
      id: const Uuid().v4(),
      totalSize: await file.length(),
      filePath: filePath,
      createdAt: DateTime.now(),
      metadata: metadata,
    );

    // File upload status
    final fileUploadStatus = FileUploadStatus(
      fileUpload: fileUpload,
      status: UploadStatus.ready,
      progress: 0.0,
    );
    _addToQueue(fileUploadStatus);

    _processQueue();

    return fileUpload;
  }

  /// Manually retry all failed uploads for an inspection
  Future<void> retryFailedUploads() async {
    debugPrint('Retrying all failed uploads');

    // All failed uploads for inspection
    final failedUploads =
        _uploadQueue.where((e) => e.status == UploadStatus.error).toList();

    if (failedUploads.isEmpty) return;

    // Retry all failed
    for (final failedUpload in failedUploads) {
      // Remove from queue
      _uploadQueue.removeWhere(
        (e) => e.fileUpload.id == failedUpload.fileUpload.id,
      );

      // Reset failed upload status
      final newStatus = FileUploadStatus(
        fileUpload: failedUpload.fileUpload,
        retryCount: 0,
        currentSize: 0,
        progress: 0.0,
        error: null,
        status: UploadStatus.ready,
      );

      _addToQueue(newStatus);
    }

    // Notify status change immediately before processing queue
    _notifyStatusChange();

    // Start uploading
    _processQueue();
  }

  // ** Helper functions **

  // Process the upload queue
  Future<void> _processQueue() async {
    if (_uploadQueue.isEmpty) return;

    debugPrint('Processing queue with ${_uploadQueue.length} items');

    // Track failures and progress
    var failedUploads = 0;
    var totalProcessed = 0;
    var activeUploads = 0;
    final activeUploadFutures = <String, Future<void>>{};

    // Keep processing while there are items in the queue or active uploads
    while (_uploadQueue.isNotEmpty || activeUploads > 0) {
      // Get items ready to upload for this inspection
      final readyItems =
          _uploadQueue
              .where((item) => item.status == UploadStatus.ready)
              .toList();

      // Calculate how many new uploads we can start
      final availableSlots = _maxConcurrentUploads - activeUploads;

      if (availableSlots > 0 && readyItems.isNotEmpty) {
        // Start new uploads up to the available slots
        final itemsToProcess = readyItems.take(availableSlots).toList();

        for (final item in itemsToProcess) {
          activeUploads++;

          // For testing purposes - if remoteDatasource throws an exception
          // we need to decrement active uploads and mark item as failed
          try {
            // Start the upload process
            final uploadFuture = _processUpload(item)
                .then((_) {
                  totalProcessed++;
                })
                .catchError((e) {
                  failedUploads++;
                  debugPrint('Upload failed: ${e.toString()}');
                })
                .whenComplete(() {
                  activeUploads--;
                  activeUploadFutures.remove(item.fileUpload.id);
                });

            activeUploadFutures[item.fileUpload.id] = uploadFuture;
          } catch (e) {
            activeUploads--;
            failedUploads++;
            debugPrint('Upload failed to start: ${e.toString()}');
          }
        }
      }

      // If no active uploads and no ready items, but queue not empty,
      // it means all remaining items are in error state or for a different inspection
      if (activeUploads == 0 && readyItems.isEmpty && _uploadQueue.isNotEmpty) {
        if (readyItems.isEmpty) {
          // If there are no items ready to process at all, we're done
          // This prevents an infinite loop if all items are in error state
          break;
        }

        // Small delay to allow other items to possibly become ready
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // Small delay before checking queue again
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Wait for any remaining active uploads to complete
    if (activeUploadFutures.isNotEmpty) {
      await Future.wait(activeUploadFutures.values);
    }

    debugPrint(
      '[File Upload] Queue processing completed. Total processed: $totalProcessed, Failed: $failedUploads',
    );
  }

  // Process a single file upload
  Future<void> _processUpload(FileUploadStatus item) async {
    item = item.copyWith(status: UploadStatus.uploading);
    _updateStatus(item);

    debugPrint('Processing upload ${item.fileUpload.id}');

    try {
      // Ensure directory is initialized
      _documentsDirectory ??= await getApplicationDocumentsDirectory();

      final path = p.join(
        _documentsDirectory!.path,
        p.basename(item.fileUpload.filePath),
      );

      final file = File(path);
      if (!(await file.exists())) {
        debugPrint('File does not exist: ${item.fileUpload.filePath}');
        var newItem = item.copyWith(
          status: UploadStatus.error,
          error: 'File does not exist',
        );
        _updateStatus(newItem);
        throw Exception('File does not exist: ${item.fileUpload.filePath}');
      }

      // Start upload session if needed
      String? sessionUrl;
      try {
        final nowInMs = DateTime.now().millisecondsSinceEpoch;
        final isSessionAvailable = item.fileUpload.sessionUrl != null;
        final isSessionValid =
            item.fileUpload.sessionTTL != null &&
            item.fileUpload.sessionTTL! > nowInMs;
        if (isSessionAvailable && isSessionValid) {
          debugPrint(
            'Resuming available upload session for upload: ${item.fileUpload.id}',
          );
          sessionUrl = item.fileUpload.sessionUrl!;
        } else {
          final newSessionTTL =
              DateTime.now().add(_kUploadSessionTTL).millisecondsSinceEpoch;

          debugPrint(
            'Creating new upload session for upload session: ${item.fileUpload.id}',
          );
          sessionUrl = await _remoteDatasource.createResumableUploadSession(
            item.fileUpload.filePath,
            item.fileUpload.totalSize,
            item.fileUpload.metadata,
          );

          final uploadWithNewSession = item.fileUpload.copyWith(
            sessionUrl: sessionUrl,
            sessionTTL: newSessionTTL,
          );
          item = item.copyWith(fileUpload: uploadWithNewSession);
        }
      } catch (e) {
        // Handle session creation error immediately
        item = item.copyWith(
          status: UploadStatus.error,
          error: 'Failed to start upload: ${e.toString()}',
        );
        _updateStatus(item);
        rethrow;
      }

      Future<void> markUploadAsCompleted() async {
        debugPrint('Upload ${item.fileUpload.id} completed successfully');

        // Update file upload with upload completion
        final updatedFileUpload = item.fileUpload.copyWith(
          uploadedAt: DateTime.now(),
        );

        item = item.copyWith(
          status: UploadStatus.success,
          progress: 1.0,
          fileUpload: updatedFileUpload,
        );
        _updateStatus(item);
      }

      final totalSize = await file.length();
      final shouldUseSingleChunkUpload = totalSize < _kExpectedChunkSize;
      if (shouldUseSingleChunkUpload) {
        await _remoteDatasource.singleChunkUpload(
          sessionUrl: sessionUrl,
          file: file,
        );

        await markUploadAsCompleted();
        return;
      }

      final remoteSize = await _remoteDatasource.fetchUploadStatus(
        sessionUrl,
        totalSize,
      );
      if (remoteSize == -1) {
        await markUploadAsCompleted();
        return;
      } else {
        item = item.copyWith(currentSize: remoteSize);
      }

      final raf = await file.open(mode: FileMode.read);
      var buffer = Uint8List(0);
      try {
        while (item.currentSize < totalSize) {
          final remainingBytes = totalSize - item.currentSize;
          final currentChunkSize = math.min(
            remainingBytes,
            _kExpectedChunkSize,
          );

          await raf.setPosition(item.currentSize);
          buffer = await raf.read(currentChunkSize.toInt());

          final uploadedSize = await _remoteDatasource.multiChunkUpload(
            sessionUrl: sessionUrl,
            fileSize: totalSize,
            buffer: buffer,
            startByte: item.currentSize,
          );

          item = item.copyWith(
            status: UploadStatus.uploading,
            currentSize: uploadedSize,
            progress: uploadedSize / totalSize,
          );
          _updateStatus(item);
        }
      } finally {
        /// Force buffer clean up to avoid memory leaks
        buffer = Uint8List(0);

        await raf.close();
      }

      await markUploadAsCompleted();
    } catch (e, s) {
      if (item.retryCount < _maxRetries) {
        final newRetryCount = item.retryCount + 1;

        // Remove item from queue
        _uploadQueue.removeWhere((e) => e.fileUpload.id == item.fileUpload.id);

        // Reset upload state and retry
        var newItem = item.copyWith(
          retryCount: newRetryCount,
          currentSize: 0,
          status: UploadStatus.ready,
          progress: 0.0,
          error: 'Retrying upload (attempt $newRetryCount/$_maxRetries)',
        );

        print(
          'Upload ${item.fileUpload.id} failed, retrying ($newRetryCount/$_maxRetries)',
        );

        // Add back to queue with priority
        _addToQueue(newItem);
      } else {
        print(
          'Upload ${item.fileUpload.id} failed permanently after $_maxRetries attempts',
        );

        var newItem = item.copyWith(
          status: UploadStatus.error,
          error: 'Failed after $_maxRetries attempts: ${e.toString()}',
        );

        _updateStatus(newItem);
      }
    }
  }

  // Add a file upload to the queue
  void _addToQueue(FileUploadStatus fileUploadStatus) {
    final fileUpload = fileUploadStatus.fileUpload;

    // First, remove any existing item with the same ID to avoid duplicates
    _uploadQueue.removeWhere((item) => item.fileUpload.id == fileUpload.id);

    _uploadQueue.add(fileUploadStatus);
    debugPrint('Added file upload to queue: ${fileUpload.id}');

    // Notify status change
    _notifyStatusChange();
  }

  // Notify status change
  void _notifyStatusChange() {
    if (!_uploadQueueController.isClosed) {
      debugPrint('Notifying status change: ${_uploadQueue.length} statuses');
      _uploadQueueController.add(List.unmodifiable(_uploadQueue));
    }
  }

  // Update the status of a file upload
  void _updateStatus(FileUploadStatus newStatus) {
    final fileUploadId = newStatus.fileUpload.id;
    final status = newStatus.status;

    // Get index of item in queue
    final index = _uploadQueue.indexWhere(
      (s) => s.fileUpload.id == fileUploadId,
    );
    if (index == -1) return;

    if (status == UploadStatus.success) {
      // Remove item from queue
      _uploadQueue.removeAt(index);

      debugPrint('Upload $fileUploadId completed successfully');
    } else {
      // Update item
      _uploadQueue[index] = newStatus;

      final progress = newStatus.progress;
      final error = newStatus.error;

      debugPrint(
        'Upload status updated - ID: $fileUploadId, Status: ${status.name}, Progress: ${(progress * 100).toStringAsFixed(0)}%${error != null ? ', Error: $error' : ''}',
      );
    }

    _notifyStatusChange();
  }
}
