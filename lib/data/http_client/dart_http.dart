import 'dart:io';
import 'package:meta/meta.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart' as retry;
import 'http_client.dart' as app;

final class DartHttpClient extends app.HttpClient {
  DartHttpClient();

  @visibleForTesting
  late http.BaseClient Function() baseClientBuilder = () {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback =
        ((X509Certificate cert, String host, int port) => true);

    final ioClient = IOClient(httpClient);

    final client = retry.RetryClient(
      ioClient,
      when: (resp) => resp.statusCode >= 500,
      whenError: (error, _) {
        final commonExceptions = [
          'SocketException',
          'HttpException',
          'HandshakeException',
          'TimeoutException',
        ];

        final err = error.runtimeType.toString();
        return commonExceptions.any(err.contains);
      },
      delay: (c) => Duration(seconds: c * 2),
    );

    return client;
  };

  late final http.BaseClient _client = baseClientBuilder();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final resp = await _client.send(request);
    return resp;
  }
}
