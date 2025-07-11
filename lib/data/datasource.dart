import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'http_client/http_client.dart' as app;

//TODO: Add access token and bucket
const kAccessToken = 'add your access token here';
const kBucket = 'add your bucket here';

class FileUploadRemoteDatasource {
  FileUploadRemoteDatasource(this.httpClient);

  final app.HttpClient httpClient;

  Map<String, String> get defaultHeaders {
    return {'Authorization': 'Bearer $kAccessToken'};
  }

  Uri getBaseUri() {
    return Uri.parse(
      'https://storage.googleapis.com/upload/storage/v1/b/$kBucket/o',
    ).replace(queryParameters: {'uploadType': 'resumable'});
  }

  Future<String> createResumableUploadSession(
    String filePath,
    int fileSize,
    Map<String, dynamic> metadata,
  ) async {
    // Prepare the file name (used as the object name in GCS)
    final fileName = p.basename(filePath);

    // Get content type for the X-Upload-Content-Type header
    final contentType = lookupMimeType(filePath) ?? 'application/octet-stream';

    // Metadata according to GCS documentation
    final metadataMap = {
      'name': fileName,
      'contentType': contentType,
      'metadata': metadata,
    };

    // Get bucket URI for corresponding file type
    final uri = getBaseUri();
    final body = json.encode(metadataMap);

    // Prepare headers according to GCS documentation
    final headers = {
      ...defaultHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'X-Upload-Content-Type': contentType,
      'X-Upload-Content-Length': '$fileSize',
    };

    final response = await httpClient.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      final sessionUrl = response.headers['location'];
      if (sessionUrl == null) {
        throw Exception('No location header found in response');
      }

      print('Session URL: $sessionUrl');
      return sessionUrl;
    }

    throw Exception(
      'Failed to start resumable upload: ${response.statusCode}, ${response.body}',
    );
  }

  @override
  // https://cloud.google.com/storage/docs/performing-resumable-uploads#single-chunk-upload
  Future<void> singleChunkUpload({
    required String sessionUrl,
    required File file,
  }) async {
    var body = await file.readAsBytes();

    final headers = <String, String>{
      ...defaultHeaders,
      'Content-Length': body.length.toString(),
    };

    http.Response? response;
    try {
      response = await httpClient.put(
        Uri.parse(sessionUrl),
        headers: headers,
        body: body,
      );
    } finally {
      /// Force clean up to avoid memory leaks
      body = Uint8List(0);
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      debugPrint('debugging: single chunk uploaded successfully');
      return;
    }

    throw Exception(
      'Failed to continue upload: ${response.statusCode}, ${response.body}',
    );
  }

  @override
  // https://cloud.google.com/storage/docs/performing-resumable-uploads#chunked-upload
  Future<int> multiChunkUpload({
    required String sessionUrl,
    required int fileSize,
    required Uint8List buffer,
    required int startByte,
  }) async {
    final bytesLeft = fileSize - startByte;
    if (bytesLeft <= 0) return fileSize;

    final endByte = startByte + buffer.length - 1;

    final headers = <String, String>{
      ...defaultHeaders,
      'Content-Range': 'bytes $startByte-$endByte/$fileSize',
      'Content-Length': buffer.length.toString(),
    };

    final response = await httpClient.put(
      Uri.parse(sessionUrl),
      headers: headers,
      body: buffer,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Upload is complete
      return fileSize;
    } else if (response.statusCode == 308) {
      // Incomplete, continue with next chunk
      final range = response.headers['range'];
      if (range != null && range.startsWith('bytes=0-')) {
        final lastByte = int.parse(range.substring(8));
        return lastByte + 1;
      }
      // If range header is missing, assume the chunk was accepted
      return startByte + buffer.length;
    }

    throw Exception(
      'Failed to continue upload: ${response.statusCode}, ${response.body}',
    );
  }

  @override
  Future<int> fetchUploadStatus(String sessionUrl, int fileSize) async {
    final headers = <String, String>{
      ...defaultHeaders,
      'Content-Range': 'bytes */$fileSize',
      'Content-Length': '0',
    };

    final response = await httpClient.put(
      Uri.parse(sessionUrl),
      headers: headers,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Upload is complete
      debugPrint('Upload is already complete');
      return -1; // Indicates completed upload
    } else if (response.statusCode == 308) {
      // Incomplete
      final range = response.headers['range'];
      debugPrint('Status shows incomplete upload, range: $range');

      if (range != null && range.startsWith('bytes=')) {
        final lastByte = parseRangeHeader(range).last;
        debugPrint('Last byte received: $lastByte');
        return lastByte + 1;
      }
      debugPrint('No range header found, assuming no bytes uploaded yet');
      return 0;
    }

    throw Exception(
      'Failed to query upload status: ${response.statusCode}, ${response.body}',
    );
  }

  // Parses the content-range header, throws an exception when provided value is invalid
  // bytes=0-1048575
  List<int> parseRangeHeader(String range) {
    return range.split('=')[1].split('-').map((v) => int.parse(v)).toList();
  }
}
