import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:resumable_upload_example/data/http_client/dart_http.dart';
import 'package:resumable_upload_example/models/file_upload_status.dart';
import 'package:resumable_upload_example/ui/upload_viewmodel.dart';
import 'package:resumable_upload_example/data/repository.dart';
import 'package:resumable_upload_example/data/datasource.dart';

import '../data/http_client/cupertino_http.dart';

class UploadView extends StatefulWidget {
  const UploadView({super.key, required this.title});

  final String title;

  @override
  State<UploadView> createState() => _UploadViewState();
}

class _UploadViewState extends State<UploadView> {
  late final UploadViewModel _viewModel;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // TODO: Here you can switch between the two http clients
    // final httpClient = CupertinoHttpClient();
    final httpClient = DartHttpClient();
    final remoteDatasource = FileUploadRemoteDatasource(httpClient);
    final repository = FileUploadRepository(remoteDatasource: remoteDatasource);

    // Initialize the view model
    _viewModel = UploadViewModel(fileUploadRepository: repository);

    // Initialize the repository and view model
    repository.init().then((_) {
      _viewModel.init();
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final List<XFile> medias = await _picker.pickMultipleMedia();

      if (medias.isNotEmpty) {
        for (final media in medias) {
          _viewModel.enqueue(media.path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library),
                label: const Text('Import Medias from Gallery'),
              ),
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _viewModel,
              builder: (context, child) {
                if (_viewModel.uploads.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No uploads yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap the button above to import videos',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: _viewModel.uploads.length,
                  itemBuilder: (context, index) {
                    final upload = _viewModel.uploads[index];
                    return _buildUploadListTile(upload);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadListTile(FileUploadStatus uploadStatus) {
    final fileName = uploadStatus.fileUpload.filePath.split('/').last;
    final fileSize = _formatFileSize(uploadStatus.fileUpload.totalSize);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(uploadStatus.status),
          child: Icon(_getStatusIcon(uploadStatus.status), color: Colors.white),
        ),
        title: Text(fileName, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Size: $fileSize'),
            if (uploadStatus.status == UploadStatus.uploading) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: uploadStatus.progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getStatusColor(uploadStatus.status),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(uploadStatus.progress * 100).toStringAsFixed(1)}% uploaded',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (uploadStatus.error != null) ...[
              const SizedBox(height: 4),
              Text(
                uploadStatus.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: _buildStatusWidget(uploadStatus),
      ),
    );
  }

  Widget _buildStatusWidget(FileUploadStatus uploadStatus) {
    return switch (uploadStatus.status) {
      UploadStatus.ready => const Chip(
        label: Text('Ready'),
        backgroundColor: Colors.blue,
        labelStyle: TextStyle(color: Colors.white),
      ),
      UploadStatus.uploading => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 4),
          Text(
            '${(uploadStatus.progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
      UploadStatus.success => const Chip(
        label: Text('Success'),
        backgroundColor: Colors.green,
        labelStyle: TextStyle(color: Colors.white),
      ),
      UploadStatus.error => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Chip(
            label: Text('Failed'),
            backgroundColor: Colors.red,
            labelStyle: TextStyle(color: Colors.white),
          ),
          if (uploadStatus.retryCount > 0)
            Text(
              'Retry: ${uploadStatus.retryCount}',
              style: const TextStyle(fontSize: 10),
            ),
        ],
      ),
    };
  }

  IconData _getStatusIcon(UploadStatus status) => switch (status) {
    UploadStatus.ready => Icons.schedule,
    UploadStatus.uploading => Icons.upload,
    UploadStatus.success => Icons.check,
    UploadStatus.error => Icons.error,
  };

  Color _getStatusColor(UploadStatus status) => switch (status) {
    UploadStatus.ready => Colors.blue,
    UploadStatus.uploading => Colors.orange,
    UploadStatus.success => Colors.green,
    UploadStatus.error => Colors.red,
  };

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
